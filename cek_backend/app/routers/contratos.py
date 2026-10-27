# -*- coding: utf-8 -*-
"""CRUD de contratos (ligan un agente con un cliente)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, Cliente, Contrato, Usuario
from app.schemas import ContratoCreate, ContratoOut, ContratoUpdate

router = APIRouter(prefix="/contratos", tags=["Contratos"])


def _validar(db: Session, id_agente: int | None, id_cliente: int | None):
    if id_agente is not None and not db.get(Agente, id_agente):
        raise HTTPException(400, "El agente indicado no existe")
    if id_cliente is not None and not db.get(Cliente, id_cliente):
        raise HTTPException(400, "El cliente indicado no existe")


@router.get("", response_model=list[ContratoOut])
def listar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
    id_agente: int | None = None,
    id_cliente: int | None = None,
    activo: bool | None = None,
):
    query = db.query(Contrato)
    if id_agente is not None:
        query = query.filter(Contrato.id_agente == id_agente)
    if id_cliente is not None:
        query = query.filter(Contrato.id_cliente == id_cliente)
    if activo is not None:
        query = query.filter(Contrato.activo == activo)
    return query.order_by(Contrato.id.desc()).all()


@router.post("", response_model=ContratoOut, status_code=201)
def crear(data: ContratoCreate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    _validar(db, data.id_agente, data.id_cliente)
    contrato = Contrato(**data.model_dump())
    db.add(contrato)
    db.commit()
    db.refresh(contrato)
    return contrato


@router.get("/{id}", response_model=ContratoOut)
def obtener(id: int, db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    contrato = db.get(Contrato, id)
    if not contrato:
        raise HTTPException(404, "Contrato no encontrado")
    return contrato


@router.put("/{id}", response_model=ContratoOut)
def actualizar(id: int, data: ContratoUpdate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    contrato = db.get(Contrato, id)
    if not contrato:
        raise HTTPException(404, "Contrato no encontrado")
    cambios = data.model_dump(exclude_unset=True)
    _validar(db, cambios.get("id_agente"), cambios.get("id_cliente"))
    for campo, valor in cambios.items():
        setattr(contrato, campo, valor)
    db.commit()
    db.refresh(contrato)
    return contrato


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin"))):
    contrato = db.get(Contrato, id)
    if not contrato:
        raise HTTPException(404, "Contrato no encontrado")
    db.delete(contrato)
    db.commit()
