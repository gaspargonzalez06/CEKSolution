# -*- coding: utf-8 -*-
"""Reclamaciones de agentes (pueden identificarse hasta ~3 meses despues)."""
from datetime import datetime

from dateutil.relativedelta import relativedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Reclamacion, ReclamacionSeguimiento, Usuario
from app.schemas import (
    ReclamacionCreate,
    ReclamacionOut,
    ReclamacionUpdate,
    SeguimientoCreate,
    SeguimientoOut,
)

router = APIRouter(prefix="/reclamaciones", tags=["Reclamaciones"])

ESTADOS = ("identificada", "en_revision", "presentada", "aceptada", "rechazada")

# Nombre "humano" de cada estado, para las notas de seguimiento.
ETIQUETA_ESTADO = {
    "identificada": "Identificada",
    "en_revision": "En revisión",
    "presentada": "Presentada",
    "aceptada": "Aceptada",
    "rechazada": "Rechazada",
}


def _fecha_limite(fecha: datetime | None) -> datetime | None:
    return fecha + relativedelta(months=3) if fecha else None


def _registrar(db: Session, r: Reclamacion, usuario: str | None,
               estado: str | None = None, nota: str | None = None) -> None:
    """Agrega un movimiento a la bitácora de la reclamación."""
    db.add(ReclamacionSeguimiento(
        id_reclamacion=r.id,
        fecha=datetime.utcnow(),
        estado=estado,
        nota=nota,
        usuario=usuario,
    ))


@router.get("", response_model=list[ReclamacionOut])
def listar(
    db: Session = Depends(get_db),
    user: Usuario = Depends(get_current_user),
    id_agente: int | None = None,
    id_cliente: int | None = None,
    estado: str | None = None,
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
):
    """Lista reclamaciones. Admin/operador ven TODAS; los demás solo su acceso."""
    from datetime import date, datetime

    from sqlalchemy import or_

    from app.core import acceso

    query = db.query(Reclamacion)
    if id_agente is not None:
        query = query.filter(Reclamacion.id_agente == id_agente)
    if id_cliente is not None:
        query = query.filter(Reclamacion.id_cliente == id_cliente)
    if estado is not None:
        query = query.filter(Reclamacion.estado == estado)
    if periodo is not None:
        query = query.filter(Reclamacion.periodo == periodo)
    if desde:
        try:
            query = query.filter(
                Reclamacion.fecha_hecho >= datetime.combine(date.fromisoformat(desde), datetime.min.time())
            )
        except ValueError:
            pass
    if hasta:
        try:
            query = query.filter(
                Reclamacion.fecha_hecho <= datetime.combine(date.fromisoformat(hasta), datetime.max.time())
            )
        except ValueError:
            pass

    # Acceso: si el usuario no ve todo, limitar a sus agentes/clientes.
    if not acceso.ve_todo(user):
        agentes = acceso.agentes_permitidos(db, user) or set()
        clientes = acceso.clientes_permitidos(db, user) or set()
        condiciones = []
        if agentes:
            condiciones.append(Reclamacion.id_agente.in_(agentes))
        if clientes:
            condiciones.append(Reclamacion.id_cliente.in_(clientes))
        if not condiciones:
            return []
        query = query.filter(or_(*condiciones))

    return query.order_by(Reclamacion.fecha_limite.is_(None), Reclamacion.fecha_limite).all()


@router.post("", response_model=ReclamacionOut, status_code=201)
def crear(data: ReclamacionCreate, db: Session = Depends(get_db), user: Usuario = Depends(require_roles("admin", "operador"))):
    campos = data.model_dump()
    if campos.get("fecha_limite") is None:
        campos["fecha_limite"] = _fecha_limite(campos.get("fecha_hecho"))
    reclamacion = Reclamacion(**campos)
    db.add(reclamacion)
    db.commit()
    db.refresh(reclamacion)
    _registrar(db, reclamacion, user.usuario, estado=reclamacion.estado,
               nota="Reclamación creada")
    db.commit()
    return reclamacion


@router.get("/{id}", response_model=ReclamacionOut)
def obtener(id: int, db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    r = db.get(Reclamacion, id)
    if not r:
        raise HTTPException(404, "Reclamación no encontrada")
    return r


@router.put("/{id}", response_model=ReclamacionOut)
def actualizar(id: int, data: ReclamacionUpdate, db: Session = Depends(get_db), user: Usuario = Depends(require_roles("admin", "operador"))):
    r = db.get(Reclamacion, id)
    if not r:
        raise HTTPException(404, "Reclamación no encontrada")
    cambios = data.model_dump(exclude_unset=True)
    estado_anterior = r.estado
    if "estado" in cambios and cambios["estado"] not in ESTADOS:
        raise HTTPException(400, f"Estado inválido. Use uno de: {', '.join(ESTADOS)}")
    if "fecha_hecho" in cambios and "fecha_limite" not in cambios:
        r.fecha_limite = _fecha_limite(cambios["fecha_hecho"])
    for campo, valor in cambios.items():
        setattr(r, campo, valor)
    if "estado" in cambios and cambios["estado"] != estado_anterior:
        if r.estado == "presentada" and not r.fecha_presentacion:
            r.fecha_presentacion = datetime.utcnow()
        _registrar(
            db, r, user.usuario, estado=r.estado,
            nota=(
                f"Estado: {ETIQUETA_ESTADO.get(estado_anterior, estado_anterior)} "
                f"→ {ETIQUETA_ESTADO.get(r.estado, r.estado)}"
            ),
        )
    db.commit()
    db.refresh(r)
    return r


@router.get("/{id}/seguimiento", response_model=list[SeguimientoOut])
def listar_seguimiento(id: int, db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    if not db.get(Reclamacion, id):
        raise HTTPException(404, "Reclamación no encontrada")
    return (
        db.query(ReclamacionSeguimiento)
        .filter(ReclamacionSeguimiento.id_reclamacion == id)
        .order_by(ReclamacionSeguimiento.fecha, ReclamacionSeguimiento.id)
        .all()
    )


@router.post("/{id}/seguimiento", response_model=SeguimientoOut, status_code=201)
def agregar_seguimiento(id: int, data: SeguimientoCreate, db: Session = Depends(get_db), user: Usuario = Depends(require_roles("admin", "operador"))):
    """Agrega una nota de seguimiento y, opcionalmente, cambia el estado."""
    r = db.get(Reclamacion, id)
    if not r:
        raise HTTPException(404, "Reclamación no encontrada")
    estado = data.estado
    if estado is not None and estado not in ESTADOS:
        raise HTTPException(400, f"Estado inválido. Use uno de: {', '.join(ESTADOS)}")
    if estado and estado != r.estado:
        r.estado = estado
        if estado == "presentada" and not r.fecha_presentacion:
            r.fecha_presentacion = datetime.utcnow()
    mov = ReclamacionSeguimiento(
        id_reclamacion=id,
        fecha=datetime.utcnow(),
        estado=estado,
        nota=data.nota,
        usuario=user.usuario,
    )
    db.add(mov)
    db.commit()
    db.refresh(mov)
    return mov


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin"))):
    r = db.get(Reclamacion, id)
    if not r:
        raise HTTPException(404, "Reclamación no encontrada")
    db.delete(r)
    db.commit()


@router.get("/proximas/vencer", response_model=list[ReclamacionOut])
def por_vencer(db: Session = Depends(get_db), _: Usuario = Depends(get_current_user), dias: int = 30):
    """Reclamos cuyo plazo (fecha_limite) vence en los proximos N dias."""
    limite = datetime.utcnow() + relativedelta(days=dias)
    return (
        db.query(Reclamacion)
        .filter(Reclamacion.fecha_limite.isnot(None), Reclamacion.fecha_limite <= limite)
        .filter(Reclamacion.estado.notin_(("aceptada", "rechazada")))
        .order_by(Reclamacion.fecha_limite)
        .all()
    )
