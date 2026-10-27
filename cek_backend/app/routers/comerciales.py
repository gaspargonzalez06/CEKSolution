# -*- coding: utf-8 -*-
"""Endpoints de los Reportes Comerciales (Comercial, DTER, Ley 15, Cobros)."""

from fastapi import APIRouter, Depends, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.core.database import get_db

import app.services.comerciales as svc
from app.models import Agente

router = APIRouter(prefix="/comerciales", tags=["Comerciales"])


def _agente_de_periodo(periodo: str) -> tuple[int, int]:
    p = (periodo or "").strip()
    if len(p) != 6 or not p.isdigit():
        raise ValueError("El periodo debe ser AAAAMM")
    return int(p[:4]), int(p[4:6])


def _generador(db: Session, codigo: str) -> str:
    codigo = (codigo or "").strip().upper()
    if not codigo:
        raise ValueError("Debe indicar el agente generador")
    return codigo


@router.get("/agentes")
def agentes_disponibles(db: Session = Depends(get_db), _=Depends(get_current_user)):
    """Generadores gestionados (ordenados por nombre) para los selectores."""
    rows = (
        db.query(Agente)
        .filter(Agente.gestionado.is_(True), Agente.activo.is_(True))
        .order_by(Agente.nombre)
        .all()
    )
    return [{"codigo": a.codigo, "nombre": a.nombre or a.codigo, "ley15": float(a.ley15 or 0)} for a in rows]


@router.get("/comercial")
def comercial(
    agente: str = Query(...),
    periodo: str = Query(..., description="AAAAMM"),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    try:
        generador = _generador(db, agente)
        annio, mes = _agente_de_periodo(periodo)
        return svc.reporte_comercial(db, generador, f"{annio}{mes:02d}")
    except ValueError as e:
        return {"error": str(e)}


@router.get("/comercial/html", response_class=HTMLResponse)
def comercial_html(agente: str, periodo: str, db: Session = Depends(get_db)):
    annio, mes = _agente_de_periodo(periodo)
    datos = svc.reporte_comercial(db, (agente or "").strip().upper(), f"{annio}{mes:02d}")
    return HTMLResponse(svc.render_html(datos))


@router.get("/dter")
def dter(
    agente: str = Query(...),
    annio: int = Query(...),
    mes: int = Query(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    generador = _generador(db, agente)
    return svc.reporte_comercial_dter(db, generador, annio, mes)


@router.get("/dter/html", response_class=HTMLResponse)
def dter_html(agente: str, annio: int, mes: int, db: Session = Depends(get_db)):
    generador = (agente or "").strip().upper()
    return HTMLResponse(svc.render_html(svc.reporte_comercial_dter(db, generador, annio, mes)))


@router.get("/ley15")
def ley15(
    agente: str = Query(...),
    annio: int = Query(...),
    mes: int = Query(...),
    solo_con_factor: bool = True,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    generador = _generador(db, agente)
    return svc.reporte_ley15(db, generador, annio, mes, solo_con_factor)


@router.get("/ley15/html", response_class=HTMLResponse)
def ley15_html(agente: str, annio: int, mes: int, db: Session = Depends(get_db)):
    generador = (agente or "").strip().upper()
    return HTMLResponse(svc.render_html(svc.reporte_ley15(db, generador, annio, mes)))


@router.get("/cobros")
def cobros(
    agente: str = Query(...),
    annio: int = Query(...),
    mes: int = Query(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    generador = _generador(db, agente)
    return svc.detalle_cobros(db, generador, annio, mes)


@router.get("/cobros/html", response_class=HTMLResponse)
def cobros_html(agente: str, annio: int, mes: int, db: Session = Depends(get_db)):
    generador = (agente or "").strip().upper()
    return HTMLResponse(svc.render_html(svc.detalle_cobros(db, generador, annio, mes)))
