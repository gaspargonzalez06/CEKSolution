# -*- coding: utf-8 -*-
"""Analisis tipo "Centro de Control · Sustentos CND" (portado del dashboard Python).

Construye, a partir de las tablas resumen (rapidas), la estructura que consumen
las graficas del frontend Flutter: evolucion diaria, proyeccion, "pintado" por
version, parcial vs total, ajuste por medida, perfil horario, top de agentes y
BRILLOSOL.

El mes en curso es el ultimo periodo cargado; el mes cerrado, el anterior.
"""
import calendar
import datetime as dt

from sqlalchemy import text

MEDS = ["consumo", "energia_asignada", "perdida_consumo", "ocasional_monto"]
MED_LABEL = {
    "consumo": "Consumo",
    "energia_asignada": "Energía asignada",
    "perdida_consumo": "Pérdida en consumo",
    "ocasional_monto": "Monto ocasional",
}


def _f(x):
    return round(float(x), 1) if x is not None else 0.0


def _dias_mes(periodo: str) -> int:
    y, m = int(periodo[:4]), int(periodo[4:6])
    return calendar.monthrange(y, m)[1]


def construir(db, periodo: str | None = None, agente: str | None = None,
              version: int | None = None) -> dict:
    periodos = [r[0] for r in db.execute(
        text("SELECT DISTINCT periodo FROM sustento_version_resumen ORDER BY periodo")
    ).all()]
    if not periodos:
        raise ValueError("Aún no hay datos de sustento cargados.")

    # Periodo elegido (por defecto el ultimo cargado). El "cerrado" es el
    # anterior al elegido, para poder comparar parcial vs total.
    if periodo and periodo in periodos:
        idx = periodos.index(periodo)
    else:
        idx = len(periodos) - 1
    mes_curso = periodos[idx]
    mes_cerrado = periodos[idx - 1] if idx > 0 else None

    def versiones(periodo):
        if not periodo:
            return []
        filas = db.execute(
            text(
                """
                SELECT version_num, reporte_id, reporte_tipo, fecha_pub, dias, filas,
                       consumo, energia_asignada, perdida_consumo, ocasional_monto, es_total
                FROM sustento_version_resumen
                WHERE periodo = :p
                ORDER BY version_num
                """
            ),
            {"p": periodo},
        ).mappings().all()
        return [dict(f) for f in filas]

    def daily(periodo, version):
        if not periodo:
            # No hay mes anterior (se pidió el primer período cargado).
            return []
        n = _dias_mes(periodo)
        if version is None:
            return [None] * n
        filas = db.execute(
            text(
                """
                SELECT DAY(fecha) AS d, ROUND(SUM(consumo), 1) AS c
                FROM sustento_diahora_resumen
                WHERE periodo = :p AND version_num = :v
                GROUP BY DAY(fecha)
                """
            ),
            {"p": periodo, "v": version},
        ).all()
        vals = {int(d): _f(c) for d, c in filas}
        return [vals.get(i) for i in range(1, n + 1)]

    def perfil(periodo, version):
        if version is None:
            return [None] * 24
        filas = db.execute(
            text(
                """
                SELECT hora, ROUND(AVG(consumo), 1) AS c
                FROM sustento_diahora_resumen
                WHERE periodo = :p AND version_num = :v
                GROUP BY hora ORDER BY hora
                """
            ),
            {"p": periodo, "v": version},
        ).all()
        vals = {int(h): _f(c) for h, c in filas}
        return [vals.get(i) for i in range(1, 25)]

    vers_curso = versiones(mes_curso)
    vers_cerr = versiones(mes_cerrado)

    # Version a mostrar del mes en curso: la elegida o, por defecto, la ultima.
    versiones_curso = [v["version_num"] for v in vers_curso]
    if version is not None and version in versiones_curso:
        vfinal_curso = version
    else:
        vfinal_curso = max(versiones_curso, default=None)
    # version "final" (DTE Sustentos) por periodo; si no existe, la ultima.
    final_cerr = None
    for v in vers_cerr:
        if v["es_total"]:
            final_cerr = v["version_num"]
    if final_cerr is None and vers_cerr:
        final_cerr = vers_cerr[-1]["version_num"]

    # --- series del sistema ---
    curso = daily(mes_curso, vfinal_curso)
    curso_ok = [x for x in curso if x is not None]
    dias_curso = len(curso_ok)
    total_curso = sum(curso_ok)
    prom_curso = total_curso / dias_curso if dias_curso else 0.0
    dias_mes_curso = _dias_mes(mes_curso)
    proy_curso = prom_curso * dias_mes_curso

    cerr_total = daily(mes_cerrado, final_cerr) if mes_cerrado else []
    cerr_parcial = daily(mes_cerrado, (final_cerr - 1) if final_cerr else None)
    total_cerr = sum(x for x in cerr_total if x)
    total_parc = sum(x for x in cerr_parcial if x)
    ajuste = total_cerr - total_parc

    # proyeccion lineal restante (para graficar)
    proy_serie = list(curso)
    for i in range(dias_curso, dias_mes_curso):
        proy_serie.append(round(prom_curso, 1))

    def acum(seq):
        out, acc = [], 0.0
        for x in seq:
            if x is None:
                out.append(None)
            else:
                acc += x
                out.append(round(acc, 1))
        return out

    acum_serie = {str(v["version_num"]): acum(daily(mes_curso, v["version_num"]))
                  for v in vers_curso}

    # --- ajuste por medida (mes cerrado: final vs ultimo parcial) ---
    agv = {v["version_num"]: v for v in vers_cerr}
    ajuste_medidas = []
    for m in MEDS:
        par = _f(agv.get((final_cerr - 1) if final_cerr else None, {}).get(m, 0))
        tot = _f(agv.get(final_cerr, {}).get(m, 0))
        ajuste_medidas.append({
            "medida": MED_LABEL[m],
            "clave": m,
            "parcial": par,
            "total": tot,
            "pct": round((tot - par) / par * 100, 3) if par else 0.0,
        })

    # --- top agentes (mes elegido), filtrable por agente ---
    agente_sel = (agente or "").strip() or None
    filtro_ag = " AND agente = :a" if agente_sel else ""
    top_params: dict = {"p": mes_curso}
    if agente_sel:
        top_params["a"] = agente_sel
    top = [dict(agente=r[0], consumo=_f(r[1])) for r in db.execute(
        text(
            "SELECT agente, consumo FROM sustento_agente_resumen "
            "WHERE periodo = :p AND consumo > 0" + filtro_ag +
            " ORDER BY consumo DESC LIMIT 12"
        ),
        top_params,
    ).all()]

    # Lista de agentes del periodo (para el selector) y serie por version del
    # agente elegido (permite comparar versiones parciales vs final).
    agentes_disponibles = [
        r[0] for r in db.execute(
            text(
                "SELECT DISTINCT agente FROM sustento_agente_resumen "
                "WHERE periodo = :p ORDER BY agente"
            ),
            {"p": mes_curso},
        ).all()
    ]
    agente_serie: list[dict] = []
    if agente_sel:
        agente_serie = [
            dict(version=int(r[0]), consumo=_f(r[1])) for r in db.execute(
                text(
                    "SELECT version_num, consumo FROM sustento_agente_resumen "
                    "WHERE periodo = :p AND agente = :a ORDER BY version_num"
                ),
                {"p": mes_curso, "a": agente_sel},
            ).all()
        ]

    # --- BRILLOSOL diario ---
    def bri_daily(periodo, version, campo):
        n = _dias_mes(periodo)
        if version is None:
            return [None] * n
        filas = db.execute(
            text(
                """
                SELECT DAY(fecha) AS d, %s AS val
                FROM sustento_bri_resumen
                WHERE periodo = :p AND version_num = :v
                """ % campo
            ),
            {"p": periodo, "v": version},
        ).all()
        vals = {int(d): _f(x) for d, x in filas}
        return [vals.get(i, 0.0) for i in range(1, n + 1)]

    bri_curso = bri_daily(mes_curso, vfinal_curso, "ocasional_monto")
    bri_cerr = bri_daily(mes_cerrado, final_cerr, "ocasional_monto") if mes_cerrado else []
    bri_ener_curso = sum(bri_daily(mes_curso, vfinal_curso, "energia_asignada"))
    bri_ener_cerr = sum(bri_daily(mes_cerrado, final_cerr, "energia_asignada")) if mes_cerrado else 0.0
    bri_total = sum(x for x in bri_curso if x)
    bri_dias = len([x for x in bri_curso if x])
    bri_prom = bri_total / bri_dias if bri_dias else 0.0
    bri_proy = bri_prom * dias_mes_curso
    bri_cerr_total = sum(x for x in bri_cerr if x)

    versiones_out = []
    for periodo, lst in ((mes_curso, vers_curso), (mes_cerrado, vers_cerr)):
        for v in lst:
            versiones_out.append({
                "periodo": periodo,
                "reporte_id": v["reporte_id"],
                "reporte_tipo": v["reporte_tipo"] or "",
                "version": v["version_num"],
                "fecha_pub": v["fecha_pub"].isoformat(sep=" ") if v["fecha_pub"] else "",
                "dias": v["dias"],
                "filas": v["filas"],
                "consumo": _f(v["consumo"]),
                "es_total": bool(v["es_total"]),
            })

    return {
        "generado": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "mes_curso": mes_curso,
        "mes_cerrado": mes_cerrado,
        "dias_mes_curso": dias_mes_curso,
        "dias_mes_cerrado": _dias_mes(mes_cerrado) if mes_cerrado else 0,
        "kpis": {
            "dias_curso": dias_curso, "total_curso": round(total_curso, 1),
            "prom_curso": round(prom_curso, 1), "proy_curso": round(proy_curso, 1),
            "total_cerr": round(total_cerr, 1), "total_parc": round(total_parc, 1),
            "ajuste": round(ajuste, 1),
            "ajuste_pct": round(ajuste / total_parc * 100, 3) if total_parc else 0.0,
            "bri_total": round(bri_total, 1), "bri_prom": round(bri_prom, 1),
            "bri_proy": round(bri_proy, 1), "bri_cerr": round(bri_cerr_total, 1),
            "bri_ener_cerr": round(bri_ener_cerr, 1),
            "bri_ener_curso": round(bri_ener_curso, 1),
        },
        "labels_curso": [str(i) for i in range(1, dias_mes_curso + 1)],
        "labels_cerrado": [str(i) for i in range(1, (_dias_mes(mes_cerrado) if mes_cerrado else 0) + 1)],
        "curso": curso,
        "proy_serie": proy_serie,
        "cerr_total": cerr_total,
        "cerr_parcial": cerr_parcial,
        "ajuste_dia": [
            round(cerr_total[i] - cerr_parcial[i], 1)
            if (i < len(cerr_total) and i < len(cerr_parcial)
                and cerr_total[i] is not None and cerr_parcial[i] is not None)
            else None
            for i in range(len(cerr_total))
        ],
        "acum_serie": acum_serie,
        "ajuste_medidas": ajuste_medidas,
        "perfil_curso": perfil(mes_curso, vfinal_curso),
        "perfil_cerrado": perfil(mes_cerrado, final_cerr) if mes_cerrado else [None] * 24,
        "top": top,
        "versiones": versiones_out,
        "periodos": periodos,
        "periodo": mes_curso,
        "periodos_disponibles": periodos,
        "agentes": agentes_disponibles,
        "agente_sel": agente_sel,
        "agente_serie": agente_serie,
        "version_sel": vfinal_curso,
        "bri_curso": bri_curso,
        "bri_cerrado": bri_cerr,
    }
