# -*- coding: utf-8 -*-
"""Series de consumo para las graficas de la factura.

Todos los valores salen de datos reales de la base:
  - sustento_horario (columna `consumo`, en MWh) -> se convierten a kWh (x1000)
  - facturas (columna `total`) -> costo promedio B/./kWh

No se inventan ni ajustan valores: si un mes no tiene sustento, no aparece.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session

MESES_CORTO = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
               "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
MESES_LARGO = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
               "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]


def nombre_mes(periodo: str) -> str:
    try:
        return MESES_LARGO[int(periodo[4:6])]
    except (ValueError, IndexError):
        return periodo


def etiqueta_mes(periodo: str) -> str:
    """'202609' -> 'Sep 26' (para el eje X)."""
    try:
        return f"{MESES_CORTO[int(periodo[4:6])]} {periodo[2:4]}"
    except (ValueError, IndexError):
        return periodo


def _version_final(db: Session, periodo: str, agente: str):
    return db.execute(text(
        "SELECT MAX(version_num) FROM sustento_horario "
        "WHERE periodo=:p AND agente=:a"
    ), {"p": periodo, "a": agente}).scalar()


def consumo_diario(db: Session, agente: str | None = None, periodo: str = "",
                   cliente: str | None = None) -> list[dict]:
    """[{fecha, dia, kwh, cms_prom}] del periodo. Usa `mediciones_diarias` si existe."""
    if cliente:
        filas = db.execute(text(
            "SELECT fecha, consumo_kwh, cms_prom FROM mediciones_diarias "
            "WHERE UPPER(cliente)=:c AND periodo=:p ORDER BY fecha"
        ), {"c": cliente.upper(), "p": periodo}).fetchall()
        return [
            {"fecha": f.isoformat(), "dia": f.day, "kwh": round(float(k or 0), 1), "cms_prom": float(cms) if cms is not None else None}
            for f, k, cms in filas
        ]
    if not agente:
        return []
    v = _version_final(db, periodo, agente)
    if v is None:
        return []
    filas = db.execute(text(
        "SELECT fecha, SUM(consumo) FROM sustento_horario "
        "WHERE periodo=:p AND version_num=:v AND agente=:a "
        "GROUP BY fecha ORDER BY fecha"
    ), {"p": periodo, "v": v, "a": agente}).fetchall()
    return [
        {"fecha": f.isoformat(), "dia": f.day, "kwh": round(float(c or 0) * 1000, 1), "cms_prom": None}
        for f, c in filas
    ]


def _costos_por_periodo(db: Session, id_cliente: int) -> dict[str, float]:
    """{periodo: costo total B/.} tomado de las facturas (sin anuladas)."""
    try:
        filas = db.execute(text(
            "SELECT periodo, SUM(total) FROM facturas "
            "WHERE id_cliente=:c AND (estado IS NULL OR estado<>'anulada') "
            "GROUP BY periodo"
        ), {"c": id_cliente}).fetchall()
    except Exception:
        return {}
    return {p: float(t or 0) for p, t in filas}


def consumo_mensual(db: Session, agente: str, id_cliente: int) -> list[dict]:
    """[{periodo, etiqueta, mwh, kwh, costo_kwh}] por mes. Datos reales."""
    if not agente:
        return []
    filas = db.execute(text(
        "SELECT s.periodo, ROUND(SUM(s.consumo),3) FROM sustento_horario s "
        "JOIN (SELECT periodo, MAX(version_num) v FROM sustento_horario "
        "      WHERE agente=:a GROUP BY periodo) m "
        "  ON m.periodo=s.periodo AND m.v=s.version_num "
        "WHERE s.agente=:a GROUP BY s.periodo ORDER BY s.periodo"
    ), {"a": agente}).fetchall()
    costos = _costos_por_periodo(db, id_cliente)
    out: list[dict] = []
    for per, mwh in filas:
        mwh_f = float(mwh or 0)
        kwh = mwh_f * 1000
        total = costos.get(per)
        costo_kwh = (total / kwh) if (total and kwh > 0) else None
        out.append({
            "periodo": per,
            "etiqueta": etiqueta_mes(per),
            "mes": nombre_mes(per),
            "mwh": round(mwh_f, 3),
            "kwh": round(kwh, 1),
            "costo_kwh": round(costo_kwh, 5) if costo_kwh else None,
        })
    return out


def consumo_mensual_mediciones(
    db: Session,
    cliente: str,
    id_cliente: int | None = None,
    hasta: str | None = None,
    limite: int = 13,
) -> list[dict]:
    """[{periodo, etiqueta, mes, mwh, kwh, costo_kwh}] desde `mediciones`.

    Es la tabla que usaba el sistema viejo (fn_historialconsumo) y la MISMA
    fuente que la columna "Consumos" de la factura: siempre hay datos para el
    periodo facturado, por lo que la grafica nunca sale vacia. `hasta` limita
    los meses al de la factura (Fecha <= corte).
    """
    if not cliente:
        return []
    sql = "SELECT periodo, SUM(consumo) FROM mediciones WHERE UPPER(cliente)=:c"
    par: dict = {"c": cliente.upper()}
    if hasta:
        sql += " AND periodo<=:h"
        par["h"] = hasta
    sql += " GROUP BY periodo ORDER BY periodo DESC LIMIT :n"
    par["n"] = limite
    filas = list(reversed(db.execute(text(sql), par).fetchall()))

    costos = _costos_por_periodo(db, id_cliente) if id_cliente else {}
    out: list[dict] = []
    for per, mwh in filas:
        mwh_f = float(mwh or 0)
        kwh = mwh_f * 1000
        total = costos.get(per)
        costo_kwh = (total / kwh) if (total and kwh > 0) else None
        out.append({
            "periodo": per,
            "etiqueta": etiqueta_mes(per),
            "mes": nombre_mes(per),
            "mwh": round(mwh_f, 6),
            "kwh": round(kwh, 1),
            "costo_kwh": round(costo_kwh, 5) if costo_kwh else None,
        })
    return out
