# -*- coding: utf-8 -*-
"""Estado por periodo: que agentes/clientes ya tienen la liquidacion CND.

La liquidacion mensual del CND es el documento que permite emitir la factura y
suele publicarse ~el dia 6 del mes siguiente. Al importarla se registra el
consumo medido (tabla ``mediciones``) y los cargos de mercado (tabla ``dte``).

Aqui se reporta, por agente y periodo, cuantos de sus clientes ya tienen ese
dato (listos para facturar) y cuantos siguen pendientes. No modifica nada: solo
lee el estado actual de la base de datos.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models import Agente, Factura
from app.services.facturas import clientes_del_agente


def _clientes_con_dato(db: Session, tabla: str, periodo: str) -> set[str]:
    """Codigos de cliente (en mayusculas) con filas en `tabla` para el periodo."""
    try:
        filas = db.execute(
            text(f"SELECT DISTINCT cliente FROM {tabla} WHERE periodo = :p"),
            {"p": periodo},
        ).fetchall()
    except Exception:
        return set()
    return {(r[0] or "").upper() for r in filas if r[0]}


def estado_periodo(
    db: Session,
    periodo: str,
    *,
    id_agentes: set[int] | None = None,
    clientes_permitidos: set[int] | None = None,
) -> dict:
    """Resumen de preparacion de la facturacion para un periodo (AAAAMM).

    Un cliente esta *listo* cuando tiene el dato del periodo (medicion del
    consumo y/o cargos DTE). Un agente esta *listo* cuando TODOS sus clientes
    lo estan.
    """
    med = _clientes_con_dato(db, "mediciones", periodo)
    dte = _clientes_con_dato(db, "dte", periodo)
    facturados = {
        r[0]
        for r in db.query(Factura.id_cliente).filter(Factura.periodo == periodo).all()
    }

    # Por defecto se listan SIEMPRE los 14 agentes gestionados, aunque todavia
    # no tengan clientes cargados (antes se omitian y solo se veian 4).
    consulta = db.query(Agente)
    if id_agentes is None:
        consulta = consulta.filter(Agente.gestionado.is_(True))
    agentes = consulta.order_by(Agente.nombre).all()
    if id_agentes is not None:
        agentes = [a for a in agentes if a.id in id_agentes]

    filas: list[dict] = []
    total_clientes = 0
    total_listos = 0
    for a in agentes:
        clientes = clientes_del_agente(db, a.id)
        if clientes_permitidos is not None:
            clientes = [c for c in clientes if c.id in clientes_permitidos]
        detalle = []
        for c in clientes:
            cod = (c.codigo or "").upper()
            tiene_med = cod in med
            tiene_dte = cod in dte
            listo = tiene_med or tiene_dte
            detalle.append({
                "id": c.id,
                "codigo": c.codigo,
                "nombre": c.nombre,
                "medicion": tiene_med,
                "dte": tiene_dte,
                "factura": c.id in facturados,
                "listo": listo,
            })
        n = len(detalle)
        listos = sum(1 for d in detalle if d["listo"])
        total_clientes += n
        total_listos += listos
        filas.append({
            "id": a.id,
            "codigo": a.codigo,
            "nombre": a.nombre,
            "clientes_total": n,
            "clientes_listos": listos,
            "clientes_pendientes": n - listos,
            "porcentaje": round(listos * 100 / n) if n else 0,
            "listo": n > 0 and listos == n,
            "sin_clientes": n == 0,
            "clientes": detalle,
        })

    agentes_listos = sum(1 for f in filas if f["listo"])
    pct_clientes = round(total_listos * 100 / total_clientes) if total_clientes else 0
    pct_agentes = round(agentes_listos * 100 / len(filas)) if filas else 0
    return {
        "periodo": periodo,
        "resumen": {
            "agentes_total": len(filas),
            "agentes_listos": agentes_listos,
            "agentes_pendientes": len(filas) - agentes_listos,
            "clientes_total": total_clientes,
            "clientes_listos": total_listos,
            "clientes_pendientes": total_clientes - total_listos,
            "porcentaje": pct_clientes,
            "porcentaje_clientes": pct_clientes,
            "porcentaje_agentes": pct_agentes,
        },
        "agentes": filas,
    }
