# -*- coding: utf-8 -*-
"""Endpoints de dashboard: resumen de la empresa y del mercado."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models import Agente, Cliente, Contrato, Factura, Reclamacion, Usuario
from app.routers.reclamaciones import ESTADOS
from app.services.estado import estado_periodo

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


def _mercado(
    db: Session,
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
):
    """Agregados por periodo desde la tabla resumen (rapida).

    La tabla sustento_mercado_resumen la genera app.services.resumen tras cargar
    sustento_horario, para no agregar millones de filas en cada carga del panel.
    """
    try:
        if desde or hasta:
            a = desde or hasta or ""
            b = hasta or desde or a
            filas = db.execute(
                text(
                    """
                    SELECT periodo, version_num, filas, consumo,
                           energia_asignada, ocasional_monto
                    FROM sustento_mercado_resumen
                    WHERE periodo >= :a AND periodo <= :b
                    ORDER BY periodo
                    """
                ),
                {"a": a, "b": b},
            ).mappings().all()
        elif periodo:
            filas = db.execute(
                text(
                    """
                    SELECT periodo, version_num, filas, consumo,
                           energia_asignada, ocasional_monto
                    FROM sustento_mercado_resumen
                    WHERE periodo <= :p
                    ORDER BY periodo
                    """
                ),
                {"p": periodo},
            ).mappings().all()
        else:
            filas = db.execute(
                text(
                    """
                    SELECT periodo, version_num, filas, consumo,
                           energia_asignada, ocasional_monto
                    FROM sustento_mercado_resumen
                    ORDER BY periodo
                    """
                )
            ).mappings().all()
        return [dict(f) for f in filas]
    except Exception:
        return []


def _periodos_disponibles(db: Session) -> list[str]:
    """Periodos reales con datos en cualquiera de las fuentes del panel."""
    periodos: set[str] = set()
    for tabla in (
        "mediciones",
        "mediciones_diarias",
        "facturas",
        "sustento_agente_resumen",
        "sustento_mercado_resumen",
    ):
        try:
            filas = db.execute(text(f"SELECT DISTINCT periodo FROM {tabla}")).scalars().all()
            for p in filas:
                if p:
                    periodos.add(str(p))
        except Exception:
            continue
    return sorted(periodos, reverse=True)


def _top_agentes(
    db: Session,
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
):
    """Consumo del periodo por agente GESTIONADO (no codigos sueltos del CND).

    Se arma desde la misma lista de agentes del sistema para que las barras
    correspondan a los 14 agentes administrados y muestren su nombre real.
    """
    cards = _agentes_cards(db, periodo, desde, hasta)
    out = [
        {
            "agente": c["nombre"] or c["codigo"],
            "codigo": c["codigo"],
            "id": c["id"],
            "consumo": c["consumo"],
            "n_clientes": c["n_clientes"],
            "generador": c["generador"],
            "distribuidor": c["distribuidor"],
        }
        for c in cards
        if float(c["consumo"] or 0) > 0
    ]
    out.sort(key=lambda x: x["consumo"], reverse=True)
    return out


def _facturacion(
    db: Session,
    desde: str | None = None,
    hasta: str | None = None,
):
    q = (
        db.query(
            Factura.periodo,
            func.count(Factura.id),
            func.coalesce(func.sum(Factura.total), 0),
        )
        .filter(Factura.estado != "anulada")
    )
    if desde or hasta:
        a = desde or hasta or ""
        b = hasta or desde or a
        q = q.filter(Factura.periodo >= a, Factura.periodo <= b)
    filas = q.group_by(Factura.periodo).order_by(Factura.periodo).all()
    return [
        {"periodo": p, "cantidad": c, "total": float(t or 0)}
        for p, c, t in filas
    ]


def _ultimo_periodo_con_datos(db: Session) -> str | None:
    """Periodo mas reciente que tiene datos en mediciones o dte."""
    for tabla in ("mediciones", "dte"):
        try:
            p = db.execute(text(f"SELECT MAX(periodo) FROM {tabla}")).scalar()
            if p:
                return str(p)
        except Exception:
            continue
    return None


def _kpis_dashboard(
    db: Session,
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
) -> dict:
    """KPIs principales (un mes o un rango de meses)."""
    periodos = _periodos_disponibles(db)

    # Resolver rango. Sin `desde/hasta` se comporta como un solo mes.
    if desde or hasta:
        a = desde or hasta or ""
        b = hasta or desde or a
        if a > b:
            a, b = b, a
        rango = sorted([p for p in periodos if a <= p <= b])
        desde, hasta = a, b
        periodo = b
    else:
        periodo = periodo or _ultimo_periodo_con_datos(db) or (periodos[0] if periodos else None)
        desde = hasta = periodo
        rango = [periodo] if periodo else []

    if not periodo:
        return {
            "periodo": None,
            "desde": None,
            "hasta": None,
            "n_periodos": 0,
            "consumo_gestionado_mwh": 0.0,
            "costo_medio_bskwh": 0.0,
            "facturado_periodo": 0.0,
            "proyeccion_mwh": 0.0,
            "agentes_listos": 0,
            "agentes_total": 14,
            "clientes_gestionados": 0,
            "variacion_consumo_pct": None,
            "dias_con_datos": 0,
            "dias_mes": 0,
        }

    # Codigos de los agentes gestionados (se cachean para todo el rango).
    try:
        agentes_codigos = db.execute(
            text("SELECT codigo FROM agentes WHERE gestionado = TRUE")
        ).scalars().all()
    except Exception:
        agentes_codigos = []
    codigos_set = {str(c).upper() for c in agentes_codigos}

    def consumo_de(per: str) -> float:
        total = 0.0
        try:
            rows = db.execute(
                text(
                    "SELECT generador, COALESCE(SUM(consumo), 0) as consumo "
                    "FROM mediciones WHERE periodo = :p GROUP BY generador"
                ),
                {"p": per},
            ).mappings().all()
            for r in rows:
                if str(r["generador"]).upper() in codigos_set:
                    total += float(r["consumo"] or 0)
        except Exception:
            pass
        return total

    consumo_gestionado = sum(consumo_de(p) for p in rango)

    # Variacion contra el bloque anterior de igual tamano.
    variacion = None
    try:
        anteriores = [p for p in periodos if desde is not None and p < desde]
        if anteriores and rango:
            prevs = anteriores[-len(rango):]
            prev = sum(consumo_de(p) for p in prevs)
            if prev > 0:
                variacion = round((consumo_gestionado - prev) / prev * 100, 2)
    except Exception:
        variacion = None

    # Costo medio del rango (B/./MWh -> B/./kWh).
    costo_medio = 0.0
    try:
        r = db.execute(
            text(
                "SELECT AVG(cms_prom) FROM mediciones_diarias "
                "WHERE periodo >= :a AND periodo <= :b "
                "AND cms_prom IS NOT NULL AND cms_prom > 0"
            ),
            {"a": desde, "b": hasta},
        ).scalar()
        if r:
            costo_medio = float(r) / 1000.0
    except Exception:
        pass

    # Facturado del rango.
    facturado = 0.0
    try:
        r = db.execute(
            text(
                "SELECT COALESCE(SUM(total), 0) FROM facturas "
                "WHERE periodo >= :a AND periodo <= :b AND estado != 'anulada'"
            ),
            {"a": desde, "b": hasta},
        ).scalar()
        facturado = float(r or 0)
    except Exception:
        pass

    # Dias con datos y dias naturales del rango.
    dias_con_datos = 0
    try:
        dias_con_datos = db.execute(
            text(
                "SELECT COUNT(*) FROM ("
                "  SELECT DISTINCT periodo, fecha FROM mediciones_diarias "
                "  WHERE periodo >= :a AND periodo <= :b"
                ") t"
            ),
            {"a": desde, "b": hasta},
        ).scalar() or 0
    except Exception:
        pass

    dias_mes = 0
    try:
        from calendar import monthrange

        for p in rango:
            dias_mes += monthrange(int(p[:4]), int(p[4:]))[1]
    except Exception:
        pass

    proyeccion = consumo_gestionado

    # Clientes distintos con medicion en el rango.
    clientes = 0
    try:
        clientes = db.execute(
            text(
                "SELECT COUNT(DISTINCT cliente) FROM mediciones "
                "WHERE periodo >= :a AND periodo <= :b"
            ),
            {"a": desde, "b": hasta},
        ).scalar() or 0
    except Exception:
        pass

    # Estado del ultimo mes del rango (los agentes listos son mensuales).
    est = estado_periodo(db, hasta)
    agentes_listos = est["resumen"]["agentes_listos"]
    agentes_total = est["resumen"]["agentes_total"]

    return {
        "periodo": periodo,
        "desde": desde,
        "hasta": hasta,
        "n_periodos": len(rango),
        "consumo_gestionado_mwh": round(consumo_gestionado, 2),
        "costo_medio_bskwh": round(costo_medio, 6),
        "facturado_periodo": round(facturado, 2),
        "proyeccion_mwh": round(proyeccion, 2),
        "agentes_listos": agentes_listos,
        "agentes_total": agentes_total,
        "clientes_gestionados": int(clientes),
        "variacion_consumo_pct": variacion,
        "dias_con_datos": int(dias_con_datos),
        "dias_mes": int(dias_mes),
    }


def _agentes_cards(
    db: Session,
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
) -> list[dict]:
    """Datos para las tarjetas de agente en el dashboard (navegan a análisis)."""
    try:
        periodo = periodo or _ultimo_periodo_con_datos(db)
        if not periodo:
            return []
        # Evita colisiones de collation: traemos agentes y mediciones por separado
        agentes = db.execute(
            text("SELECT id, codigo, nombre, generador, distribuidor FROM agentes WHERE gestionado = TRUE ORDER BY nombre")
        ).mappings().all()
        if desde or hasta:
            a = desde or hasta or periodo
            b = hasta or desde or periodo
            med = db.execute(
                text(
                    "SELECT generador, COALESCE(SUM(consumo), 0) as consumo, "
                    "COUNT(DISTINCT cliente) as n_clientes "
                    "FROM mediciones WHERE periodo >= :a AND periodo <= :b "
                    "GROUP BY generador"
                ),
                {"a": a, "b": b},
            ).mappings().all()
        else:
            med = db.execute(
                text(
                    "SELECT generador, COALESCE(SUM(consumo), 0) as consumo, COUNT(DISTINCT cliente) as n_clientes "
                    "FROM mediciones WHERE periodo = :p GROUP BY generador"
                ),
                {"p": periodo},
            ).mappings().all()
        med_map = {str(r["generador"]).upper(): r for r in med}
        out = []
        for a in agentes:
            codigo_up = (a["codigo"] or "").upper()
            m = med_map.get(codigo_up, {"consumo": 0, "n_clientes": 0})
            out.append({
                "id": a["id"],
                "codigo": a["codigo"],
                "nombre": a["nombre"],
                "generador": a["generador"],
                "distribuidor": a["distribuidor"],
                "consumo": float(m["consumo"] or 0),
                "n_clientes": int(m["n_clientes"] or 0),
                "periodo": periodo,
            })
        out.sort(key=lambda x: x["consumo"], reverse=True)
        return out
    except Exception:
        return []


def _codigos_gestionados(db: Session) -> set[str]:
    try:
        codigos = db.execute(
            text("SELECT codigo FROM agentes WHERE gestionado = TRUE")
        ).scalars().all()
    except Exception:
        codigos = []
    return {str(c).upper() for c in codigos}


def _serie_global(
    db: Session,
    desde: str | None,
    hasta: str | None,
) -> list[dict]:
    """Consumo total (MWh) por periodo de los agentes gestionados.

    Sirve para la grafica global de puntos: la evolucion del consumo de la
    empresa en el rango de meses elegido (no por agente).
    """
    if not desde and not hasta:
        return []
    a = desde or hasta or ""
    b = hasta or desde or a
    codigos = _codigos_gestionados(db)
    try:
        rows = db.execute(
            text(
                "SELECT periodo, generador, COALESCE(SUM(consumo), 0) AS c "
                "FROM mediciones WHERE periodo >= :a AND periodo <= :b "
                "GROUP BY periodo, generador"
            ),
            {"a": a, "b": b},
        ).mappings().all()
    except Exception:
        return []
    por_periodo: dict[str, float] = {}
    for r in rows:
        gen = str(r["generador"] or "").upper()
        if gen not in codigos:
            continue
        p = str(r["periodo"])
        por_periodo[p] = por_periodo.get(p, 0.0) + float(r["c"] or 0)
    return [
        {"periodo": p, "mwh": round(por_periodo[p], 3)}
        for p in sorted(por_periodo)
    ]


def _serie_diaria_global(db: Session, periodo: str | None) -> list[dict]:
    """Consumo diario total (kWh) de los agentes gestionados en un periodo.

    Da los "puntos" globales del mes (suma de todos los agentes), sin inventar
    valores: solo los dias que tienen medicion diaria real.
    """
    if not periodo:
        return []
    codigos = _codigos_gestionados(db)
    try:
        rows = db.execute(
            text(
                "SELECT fecha, generador, COALESCE(SUM(consumo_kwh), 0) AS k "
                "FROM mediciones_diarias WHERE periodo = :p "
                "GROUP BY fecha, generador"
            ),
            {"p": periodo},
        ).mappings().all()
    except Exception:
        return []
    por_dia: dict[str, float] = {}
    for r in rows:
        gen = str(r["generador"] or "").upper()
        if gen not in codigos:
            continue
        f = r["fecha"]
        clave = f.isoformat() if hasattr(f, "isoformat") else str(f)
        por_dia[clave] = por_dia.get(clave, 0.0) + float(r["k"] or 0)
    return [
        {"fecha": k, "kwh": round(por_dia[k], 1)}
        for k in sorted(por_dia)
    ]


@router.get("/resumen")
def resumen(
    periodo: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
):
    por_estado = {e: db.query(func.count(Reclamacion.id)).filter(Reclamacion.estado == e).scalar() for e in ESTADOS}
    kpis = _kpis_dashboard(db, periodo, desde, hasta)
    per = kpis.get("periodo")
    d = kpis.get("desde")
    h = kpis.get("hasta")
    agentes_cards = _agentes_cards(db, per, d, h)
    return {
        "entidades": {
            "agentes": db.query(func.count(Agente.id)).filter(Agente.gestionado.is_(True)).scalar(),
            "distribuidores": db.query(func.count(Agente.id)).filter(Agente.distribuidor.is_(True)).scalar(),
            "generadores": db.query(func.count(Agente.id)).filter(Agente.generador.is_(True), Agente.gestionado.is_(True)).scalar(),
            "clientes": db.query(func.count(Cliente.id)).scalar(),
            "contratos": db.query(func.count(Contrato.id)).scalar(),
            "usuarios": db.query(func.count(Usuario.id)).scalar(),
            "facturas": db.query(func.count(Factura.id)).scalar(),
        },
        "reclamaciones": {
            "total": db.query(func.count(Reclamacion.id)).scalar(),
            "por_estado": por_estado,
        },
        "periodos": _periodos_disponibles(db),
        "mercado": _mercado(db, per if not (d and h and d != h) else None, d if d != h else None, h if d != h else None),
        "top_agentes": _top_agentes(db, per, d, h),
        "facturacion": _facturacion(db, d if d != h else None, h if d != h else None),
        "kpis": kpis,
        "agentes_cards": agentes_cards,
        "serie_global": _serie_global(db, d, h),
        "serie_diaria_global": _serie_diaria_global(db, h),
    }
