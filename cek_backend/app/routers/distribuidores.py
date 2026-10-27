# -*- coding: utf-8 -*-
"""Distribuidores = agentes con el flag 'distribuidor' (las agencias que venden luz)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, Usuario
from app.schemas import AgenteCreate, AgenteOut, AgenteUpdate

router = APIRouter(prefix="/distribuidores", tags=["Distribuidores"])


@router.get("", response_model=list[AgenteOut])
def listar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
    gestionado: bool | None = True,
    todos: bool = False,
):
    """Distribuidores (agentes con el flag 'distribuidor').

    Por defecto solo los gestionados por CEK. Use `todos=true` para ver
    tambien las contrapartes del mercado (ENSA, EDEMET, EDECHI...).
    """
    query = db.query(Agente).filter(Agente.distribuidor.is_(True))
    if todos:
        gestionado = None
    if gestionado is not None:
        query = query.filter(Agente.gestionado == gestionado)
    return query.order_by(Agente.nombre).all()


@router.post("", response_model=AgenteOut, status_code=201)
def crear(data: AgenteCreate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    if db.query(Agente).filter(Agente.codigo == data.codigo).first():
        raise HTTPException(400, "Ya existe un agente con ese código")
    data.distribuidor = True
    campos = data.model_dump(exclude={"credencial"})
    agente = Agente(**campos)
    db.add(agente)
    db.commit()
    db.refresh(agente)
    return agente


@router.put("/{id}", response_model=AgenteOut)
def actualizar(id: int, data: AgenteUpdate, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Distribuidor no encontrado")
    cambios = data.model_dump(exclude_unset=True, exclude={"credencial"})
    cambios["distribuidor"] = True
    for campo, valor in cambios.items():
        setattr(agente, campo, valor)
    db.commit()
    db.refresh(agente)
    return agente


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin"))):
    agente = db.get(Agente, id)
    if not agente:
        raise HTTPException(404, "Distribuidor no encontrado")
    db.delete(agente)
    db.commit()
