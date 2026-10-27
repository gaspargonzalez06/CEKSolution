# -*- coding: utf-8 -*-
"""CRUD de clientes (cuelgan de un distribuidor)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core import acceso
from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, Cliente, Contrato, Precio, Usuario
from app.schemas import ClienteCreate, ClienteDetalle, ClienteOut, ClienteUpdate
from app.services import consumo as svc_consumo
from app.services import facturas as svc

router = APIRouter(prefix="/clientes", tags=["Clientes"])


def _con_agente(db: Session, clientes: list[Cliente]) -> list[dict]:
    """Agrega el agente/contrato/tarifa con el que se factura a cada cliente.

    La asociacion real vive en `contratos.id_agente`; `id_distribuidor` es solo
    el distribuidor comercial. Si no hay contrato, se usa el distribuidor.
    """
    if not clientes:
        return []
    agentes = {a.id: a for a in db.query(Agente).all()}
    contratos: dict[int, Contrato] = {}
    for c in db.query(Contrato).order_by(Contrato.id.desc()).all():
        if c.id_cliente not in contratos:
            contratos[c.id_cliente] = c
    salida: list[dict] = []
    for cl in clientes:
        base = ClienteOut.model_validate(cl).model_dump()
        ct = contratos.get(cl.id)
        ag = agentes.get(ct.id_agente) if ct else agentes.get(cl.id_distribuidor)
        tarifa = None
        if ct is not None:
            pr = (
                db.query(Precio)
                .filter(Precio.id_contrato == ct.id)
                .order_by(Precio.inicia.desc())
                .first()
            )
            tarifa = pr.tarifa if pr else None
        base.update({
            "id_agente": ag.id if ag else None,
            "agente_codigo": ag.codigo if ag else None,
            "agente_nombre": ag.nombre if ag else None,
            "contrato": ct.contrato if ct else None,
            "tarifa": tarifa,
        })
        salida.append(base)
    return salida


@router.get("", response_model=list[ClienteDetalle])
def listar(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
    q: str | None = None,
    id_distribuidor: int | None = None,
    id_agente: int | None = None,
):
    query = db.query(Cliente)
    permitidos = acceso.clientes_permitidos(db, usuario)
    if permitidos is not None:
        query = query.filter(Cliente.id.in_(permitidos))
    if q:
        like = f"%{q}%"
        query = query.filter((Cliente.nombre.like(like)) | (Cliente.codigo.like(like)) | (Cliente.nis.like(like)))
    if id_distribuidor is not None:
        query = query.filter(Cliente.id_distribuidor == id_distribuidor)
    clientes = query.order_by(Cliente.nombre).all()
    if id_agente is not None:
        ids = {
            c.id_cliente
            for c in db.query(Contrato).filter(Contrato.id_agente == id_agente).all()
        }
        clientes = [c for c in clientes if c.id in ids]
    return _con_agente(db, clientes)


@router.post("", response_model=ClienteOut, status_code=201)
def crear(data: ClienteCreate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    if db.query(Cliente).filter(Cliente.codigo == data.codigo).first():
        raise HTTPException(400, "Ya existe un cliente con ese código")
    cliente = Cliente(**data.model_dump())
    db.add(cliente)
    db.commit()
    db.refresh(cliente)
    return cliente


@router.get("/{id}", response_model=ClienteDetalle)
def obtener(id: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    cliente = db.get(Cliente, id)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    if not acceso.puede_ver_cliente(db, usuario, id):
        raise HTTPException(403, "Sin acceso a este cliente")
    return _con_agente(db, [cliente])[0]


@router.get("/{id}/precio")
def precio_del_cliente(
    id: int,
    periodo: str | None = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Precio y tarifa vigentes del contrato del cliente (tabla `precios`).

    Lo usa la pantalla de facturacion para autorellenar el precio en vez de
    escribir uno fijo; el sistema viejo tomaba el precio de `Precios`.
    Tambien devuelve el consumo medido del periodo, si existe. Si el periodo
    aun no tiene medicion cargada, se toma la mas reciente hasta ese corte
    (mismo criterio que /facturas/generar) para no autorellenar en 0.
    """
    cliente = db.get(Cliente, id)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    if not acceso.puede_ver_cliente(db, usuario, id):
        raise HTTPException(403, "Sin acceso a este cliente")
    contrato = (
        db.query(Contrato)
        .filter(Contrato.id_cliente == id)
        .order_by(Contrato.id.desc())
        .first()
    )
    precio, tarifa = svc.precio_vigente(db, contrato.id if contrato else None, periodo or "")
    consumo = svc.consumo_desde_mediciones(db, cliente.codigo, periodo) if periodo else None
    if periodo and consumo is None:
        # Misma regla que /facturas/generar: si el mes aun no tiene medicion,
        # usar la ultima medicion hasta el corte (evita factura en 0).
        hist = svc.historial_mediciones(db, cliente.codigo, hasta=periodo, limite=1)
        consumo = next(iter(hist.values()), None) if hist else None
    return {
        "id_cliente": cliente.id,
        "codigo": cliente.codigo,
        "id_contrato": contrato.id if contrato else None,
        "contrato": contrato.contrato if contrato else None,
        "periodo": periodo,
        "precio": precio,
        "tarifa": tarifa,
        "consumo_mwh": consumo,
    }


@router.get("/{id}/consumo")
def consumo_del_cliente(
    id: int,
    hasta: str | None = None,
    limite: int = 13,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Consumo mensual del cliente (tabla `mediciones`) para las graficas.

    Misma fuente que la columna "Consumos" de la factura; `hasta` limita al mes
    del corte (AAAAMM) para no mostrar meses posteriores.
    """
    cliente = db.get(Cliente, id)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    if not acceso.puede_ver_cliente(db, usuario, id):
        raise HTTPException(403, "Sin acceso a este cliente")
    serie = svc_consumo.consumo_mensual_mediciones(
        db, cliente.codigo, cliente.id, hasta=(hasta or None), limite=limite)
    return {
        "id_cliente": cliente.id,
        "codigo": cliente.codigo,
        "nombre": cliente.nombre or cliente.codigo,
        "hasta": hasta,
        "serie": serie,
    }


@router.put("/{id}", response_model=ClienteOut)
def actualizar(id: int, data: ClienteUpdate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    cliente = db.get(Cliente, id)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(cliente, campo, valor)
    db.commit()
    db.refresh(cliente)
    return cliente


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin"))):
    cliente = db.get(Cliente, id)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    db.delete(cliente)
    db.commit()
