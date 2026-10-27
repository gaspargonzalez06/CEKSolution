# -*- coding: utf-8 -*-
"""CRUD de precios (tarifas con vigencia) asociados a un contrato.

Replica la tabla 'Precios' del sistema viejo: cada contrato puede tener varios
precios; el vigente se determina por la fecha (Inicia <= periodo <= Termina).
"""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Contrato, Precio, Usuario
from app.schemas import PrecioCreate, PrecioOut, PrecioUpdate

router = APIRouter(prefix="/precios", tags=["Precios"])


def _validar_contrato(db: Session, id_contrato: int | None):
    if id_contrato is not None and not db.get(Contrato, id_contrato):
        raise HTTPException(400, "El contrato indicado no existe")


@router.get("", response_model=list[PrecioOut])
def listar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
    id_contrato: int | None = None,
    vigente: bool = False,
    fecha: datetime | None = None,
):
    query = db.query(Precio)
    if id_contrato is not None:
        query = query.filter(Precio.id_contrato == id_contrato)
    if vigente:
        ref = fecha or datetime.utcnow()
        query = query.filter(
            (Precio.inicia.is_(None)) | (Precio.inicia <= ref),
            (Precio.termina.is_(None)) | (Precio.termina >= ref),
        )
    return query.order_by(Precio.id_contrato, Precio.inicia).all()


@router.post("", response_model=PrecioOut, status_code=201)
def crear(data: PrecioCreate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    _validar_contrato(db, data.id_contrato)
    precio = Precio(**data.model_dump())
    db.add(precio)
    db.commit()
    db.refresh(precio)
    return precio


@router.get("/{id}", response_model=PrecioOut)
def obtener(id: int, db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    precio = db.get(Precio, id)
    if not precio:
        raise HTTPException(404, "Precio no encontrado")
    return precio


@router.put("/{id}", response_model=PrecioOut)
def actualizar(id: int, data: PrecioUpdate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    precio = db.get(Precio, id)
    if not precio:
        raise HTTPException(404, "Precio no encontrado")
    cambios = data.model_dump(exclude_unset=True)
    _validar_contrato(db, cambios.get("id_contrato"))
    for campo, valor in cambios.items():
        setattr(precio, campo, valor)
    db.commit()
    db.refresh(precio)
    return precio


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin"))):
    precio = db.get(Precio, id)
    if not precio:
        raise HTTPException(404, "Precio no encontrado")
    db.delete(precio)
    db.commit()
