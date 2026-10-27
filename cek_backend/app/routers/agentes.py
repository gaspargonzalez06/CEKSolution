# -*- coding: utf-8 -*-
"""CRUD de agentes + sus credenciales de portal (para la automatizacion)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core import acceso
from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, AgenteCredencial, Cliente, Contrato, Usuario
from app.schemas import AgenteCreate, AgenteOut, AgenteUpdate, ClienteOut, CredencialIn, CredencialOut
from app.services import facturas as svc_facturas
from app.services.crypto import cifrar, descifrar

router = APIRouter(prefix="/agentes", tags=["Agentes"])
admin = require_roles("admin", "operador")


def _agentes_visibles(db: Session, usuario: Usuario) -> list[int] | None:
    """IDs de agentes que un usuario restringido puede ver, o None si ve todo.

    Incluye los agentes asignados y los agentes de los clientes permitidos
    (via contrato o id_distribuidor).
    """
    if acceso.ve_todo(usuario):
        return None
    agentes, _ = acceso.asignados(db, usuario)
    clientes = acceso.clientes_permitidos(db, usuario) or set()
    if clientes:
        for (id_ag,) in (
            db.query(Contrato.id_agente).filter(Contrato.id_cliente.in_(clientes)).all()
        ):
            if id_ag is not None:
                agentes.add(id_ag)
        for (id_dist,) in (
            db.query(Cliente.id_distribuidor).filter(Cliente.id.in_(clientes)).all()
        ):
            if id_dist is not None:
                agentes.add(id_dist)
    return sorted(agentes)


def _aplicar_credencial(db: Session, agente: Agente, data: CredencialIn | None):
    if data is None:
        return
    cred = agente.credencial
    if cred is None:
        cred = AgenteCredencial(id_agente=agente.id)
        db.add(cred)
    if data.usuario_portal is not None:
        cred.usuario_portal = data.usuario_portal
    if data.password_portal is not None:  # None = no tocar; "" = limpiar
        cred.password_portal_enc = cifrar(data.password_portal) if data.password_portal else None
    if data.url_portal is not None:
        cred.url_portal = data.url_portal
    cred.activo = data.activo


@router.get("", response_model=list[AgenteOut])
def listar(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
    q: str | None = None,
    distribuidor: bool | None = None,
    generador: bool | None = None,
    activo: bool | None = None,
    gestionado: bool | None = True,
    todos: bool = False,
):
    """Lista de agentes.

    Por defecto solo devuelve el universo gestionado por CEK (14 agentes).
    Use `gestionado=false` para ver solo las contrapartes del mercado, o
    `todos=true` para ver todos (gestionados + contrapartes).
    """
    query = db.query(Agente)
    visibles = _agentes_visibles(db, usuario)
    if visibles is not None:
        query = query.filter(Agente.id.in_(visibles))
    if q:
        like = f"%{q}%"
        query = query.filter((Agente.nombre.like(like)) | (Agente.codigo.like(like)) | (Agente.codigo_cnd.like(like)))
    if distribuidor is not None:
        query = query.filter(Agente.distribuidor == distribuidor)
    if generador is not None:
        query = query.filter(Agente.generador == generador)
    if activo is not None:
        query = query.filter(Agente.activo == activo)
    if todos:
        gestionado = None
    if gestionado is not None:
        query = query.filter(Agente.gestionado == gestionado)
    return query.order_by(Agente.nombre).all()


@router.get("/{id}", response_model=AgenteOut)
def obtener(id: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    visibles = _agentes_visibles(db, usuario)
    if visibles is not None and id not in visibles:
        raise HTTPException(403, "Sin acceso a este agente")
    return agente


@router.get("/{id}/clientes", response_model=list[ClienteOut])
def clientes_del_agente(
    id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Clientes que pertenecen al agente (via contratos / id_distribuidor).

    Lo usa la pantalla de facturacion en lote: primero se elige el agente y
    despues se muestran sus clientes para generar las facturas del periodo.
    """
    if not db.get(Agente, id):
        raise HTTPException(404, "Agente no encontrado")
    permitidos = acceso.clientes_permitidos(db, usuario)
    clientes = svc_facturas.clientes_del_agente(db, id)
    if permitidos is not None:
        clientes = [c for c in clientes if c.id in permitidos]
    return clientes


@router.post("", response_model=AgenteOut, status_code=201)
def crear(data: AgenteCreate, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    if db.query(Agente).filter(Agente.codigo == data.codigo).first():
        raise HTTPException(400, "Ya existe un agente con ese código")
    campos = data.model_dump(exclude={"credencial"})
    agente = Agente(**campos)
    db.add(agente)
    db.flush()  # obtiene el id
    _aplicar_credencial(db, agente, data.credencial)
    db.commit()
    db.refresh(agente)
    return agente


@router.put("/{id}", response_model=AgenteOut)
def actualizar(id: int, data: AgenteUpdate, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    cambios = data.model_dump(exclude_unset=True, exclude={"credencial"})
    if "codigo" in cambios:
        dup = db.query(Agente).filter(Agente.codigo == cambios["codigo"], Agente.id != id).first()
        if dup:
            raise HTTPException(400, "Ya existe otro agente con ese código")
    for campo, valor in cambios.items():
        setattr(agente, campo, valor)
    _aplicar_credencial(db, agente, data.credencial)
    db.commit()
    db.refresh(agente)
    return agente


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    db.delete(agente)
    db.commit()


# --------------------------------------------------------------------------- #
# Credenciales
# --------------------------------------------------------------------------- #
@router.get("/{id}/credencial", response_model=CredencialOut)
def ver_credencial(id: int, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    agente = db.get(Agente, id)
    if not agente or not agente.credencial:
        raise HTTPException(404, "El agente no tiene credenciales configuradas")
    return agente.credencial


@router.get("/{id}/credencial/clave")
def ver_clave_credencial(
    id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(require_roles("admin")),
):
    """Devuelve la clave del portal CND descifrada.

    Solo para administradores: es la unica via en que la contraseña sale del
    sistema, y se usa para auditarla cuando se olvida. La app la revela bajo
    demanda en la pestaña "Credenciales CND" del agente.
    """
    agente = db.get(Agente, id)
    if not agente or not agente.credencial:
        raise HTTPException(404, "El agente no tiene credenciales configuradas")
    return {
        "usuario_portal": agente.credencial.usuario_portal,
        "password_portal": descifrar(agente.credencial.password_portal_enc),
        "activo": agente.credencial.activo,
    }


@router.put("/{id}/credencial", response_model=CredencialOut)
def guardar_credencial(id: int, data: CredencialIn, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    _aplicar_credencial(db, agente, data)
    db.commit()
    db.refresh(agente)
    return agente.credencial
