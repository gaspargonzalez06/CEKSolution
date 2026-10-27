# -*- coding: utf-8 -*-
"""Automatizacion: consulta el plan y lanza el scraper con las credenciales del agente."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, Usuario
from app.services import automatizacion

router = APIRouter(prefix="/automatizacion", tags=["Automatización"])


@router.get("/plan/{id_agente}")
def plan(id_agente: int, ext: str | None = None, db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    agente = db.get(Agente, id_agente)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    return automatizacion.plan_sync(agente, ext)


@router.post("/sync/{id_agente}")
def sync(id_agente: int, ext: str | None = None, db: Session = Depends(get_db), _: Usuario = Depends(require_roles("admin", "operador"))):
    agente = db.get(Agente, id_agente)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")
    resultado = automatizacion.lanzar_sync(agente, ext)
    if resultado.get("ok"):
        automatizacion.marcar_login(db, agente)
    return resultado
