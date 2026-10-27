# -*- coding: utf-8 -*-
"""Ajustes / Reclamos publicados por el CND.

Cuando el CND atiende un reclamo reemite el mes completo con el sufijo AjN
(Aj1, Aj2, ...). Estos archivos viven en el portal y ya se descargan a raw_data
por el scraper; aqui los exponemos y los clasificamos por mes (periodo).
"""
import json
import re

from fastapi import APIRouter, Depends
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import AjusteCND, Usuario
from app.schemas import AjusteCNDOut, AjusteSyncResult

router = APIRouter(prefix="/ajustes", tags=["Ajustes CND"])

# Mismo criterio que el scraper: token "Aj" / "Ajuste" seguido de numero.
_AJ_RE = re.compile(r"(?:^|[_/\s])aj(?:uste)?[0-9]", re.I)
_COD_RE = re.compile(r"aj(?:uste)?([0-9]+)", re.I)


def es_ajuste(nombre: str | None) -> bool:
    return bool(_AJ_RE.search(nombre or ""))


def codigo_ajuste(nombre: str | None) -> str | None:
    m = _COD_RE.search(nombre or "")
    return f"AJ{m.group(1)}" if m else None


def _sql_ajustes() -> str:
    return (
        "SELECT reporte_id, cliente_codigo, periodo, reporte_tipo, "
        "       archivo_nombre, archivo_origen, data_json "
        "FROM raw_data "
        "WHERE LOWER(archivo_nombre) REGEXP '(^|_)aj(uste)?[0-9]' "
        "   OR LOWER(archivo_origen) REGEXP '(^|[/_])aj(uste)?[0-9]' "
        "ORDER BY periodo, reporte_id"
    )


@router.get("", response_model=list[AjusteCNDOut])
def listar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
    periodo: str | None = None,
    codigo: str | None = None,
):
    q = db.query(AjusteCND)
    if periodo:
        q = q.filter(AjusteCND.periodo == periodo)
    if codigo:
        q = q.filter(AjusteCND.codigo == codigo)
    return q.order_by(AjusteCND.periodo, AjusteCND.codigo, AjusteCND.nombre).all()


@router.get("/periodos")
def periodos(db: Session = Depends(get_db), _: Usuario = Depends(get_current_user)):
    """Resumen: por mes cuantos ajustes y de que codigos (AJ1, AJ2...)."""
    filas = (
        db.query(AjusteCND.periodo, AjusteCND.codigo, func.count(AjusteCND.id))
        .group_by(AjusteCND.periodo, AjusteCND.codigo)
        .order_by(AjusteCND.periodo)
        .all()
    )
    agg: dict[str, dict] = {}
    for periodo, codigo, n in filas:
        agg.setdefault(periodo, {})[codigo or "?"] = n
    return [
        {"periodo": p, "codigos": c, "total": sum(c.values())}
        for p, c in sorted(agg.items())
    ]


@router.post("/sincronizar", response_model=AjusteSyncResult)
def sincronizar(
    db: Session = Depends(get_db),
    _: Usuario = Depends(require_roles("admin", "operador")),
):
    """Escanea raw_data en busca de archivos AjN y los registra/actualiza."""
    filas = db.execute(text(_sql_ajustes())).all()
    existentes = {a.reporte_id: a for a in db.query(AjusteCND).all()}

    nuevos = 0
    periodos: set[str] = set()
    for reporte_id, cliente, periodo, tipo, nombre, origen, data_json in filas:
        codigo = codigo_ajuste(nombre)
        local = None
        try:
            local = json.loads(data_json or "{}").get("archivo_local")
        except Exception:
            local = None
        actual = existentes.get(reporte_id)
        if actual is None:
            actual = AjusteCND(reporte_id=reporte_id)
            db.add(actual)
            nuevos += 1
        actual.periodo = periodo or ""
        actual.codigo = codigo
        actual.nombre = nombre
        actual.tipo = tipo
        actual.cliente_codigo = cliente
        actual.origen = origen
        actual.archivo_local = local
        periodos.add(periodo or "")
    db.commit()

    detalle = db.query(AjusteCND).order_by(AjusteCND.periodo, AjusteCND.nombre).all()
    return AjusteSyncResult(
        revisados=len(filas),
        nuevos=nuevos,
        ya_existian=len(filas) - nuevos,
        periodos=sorted(p for p in periodos if p),
        detalle=detalle,
    )
