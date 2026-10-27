# -*- coding: utf-8 -*-
"""Facturas del sistema viejo (tabla Facturas de SQL Server / CEK).

Solo lectura: se conservan como registro historico. Se cargan con
`importar_facturas_antiguas.py` a partir del CSV/TSV exportado de la base vieja.
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models import FacturaHistorica, Usuario
from app.schemas import FacturaHistoricaOut

router = APIRouter(prefix="/facturas-historicas", tags=["Facturas historicas"])


@router.get("", response_model=list[FacturaHistoricaOut])
def listar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
    generador: str | None = None,
    cliente: str | None = None,
    contrato: str | None = None,
    annio: int | None = None,
    mes: int | None = None,
    id_contrato: int | None = None,
    limite: int = Query(200, ge=1, le=2000),
    offset: int = Query(0, ge=0),
):
    query = db.query(FacturaHistorica)
    if generador:
        query = query.filter(FacturaHistorica.generador == generador)
    if cliente:
        query = query.filter(FacturaHistorica.cliente == cliente)
    if contrato:
        query = query.filter(FacturaHistorica.contrato == contrato)
    if id_contrato is not None:
        query = query.filter(FacturaHistorica.id_contrato == id_contrato)
    if annio is not None:
        query = query.filter(FacturaHistorica.annio == annio)
    if mes is not None:
        query = query.filter(FacturaHistorica.mes == mes)
    return (
        query.order_by(
            FacturaHistorica.annio.desc(),
            FacturaHistorica.mes.desc(),
            FacturaHistorica.generador,
            FacturaHistorica.cliente,
        )
        .offset(offset)
        .limit(limite)
        .all()
    )


@router.get("/resumen")
def resumen(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
):
    """Totales por año/mes para una vista rapida."""
    filas = (
        db.query(
            FacturaHistorica.annio,
            FacturaHistorica.mes,
            func.count(FacturaHistorica.id).label("facturas"),
            func.sum(FacturaHistorica.consumo).label("consumo"),
            func.sum(FacturaHistorica.valor).label("valor"),
            func.sum(FacturaHistorica.costo).label("costo"),
        )
        .group_by(FacturaHistorica.annio, FacturaHistorica.mes)
        .order_by(FacturaHistorica.annio.desc(), FacturaHistorica.mes.desc())
        .all()
    )
    return [
        {
            "annio": f.annio,
            "mes": f.mes,
            "facturas": int(f.facturas or 0),
            "consumo": float(f.consumo or 0),
            "valor": float(f.valor or 0),
            "costo": float(f.costo or 0),
        }
        for f in filas
    ]
