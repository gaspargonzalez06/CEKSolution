# -*- coding: utf-8 -*-
"""Generacion de facturas.

- Toma los cargos reales del mercado desde los DTE tabulares del CND.
- Arma las lineas de la factura (energia en contratos + cargos de mercado).
- Renderiza un HTML autonomo (pagina 1 = factura, pagina 2 = grafica de consumo).
"""
from __future__ import annotations

import html
from datetime import datetime
from pathlib import Path
from typing import Iterable

from sqlalchemy import text

BASE_DIR = Path(__file__).resolve().parents[3]
SCRAPER_DIR = BASE_DIR / "CND_Scraper"
RAW_DIR = SCRAPER_DIR / "raw"

MESES = [
    "", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
]

MES_ABR = [
    "", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
    "Jul", "Ago", "Sep", "Oct", "Nov", "Dic",
]

# Orden en que queremos mostrar los cargos del mercado (nombre CND -> etiqueta factura)
CARGOS = [
    ("Energía en Mercado Ocasional", "Energía en Mercado Ocasional"),
    ("Energía en Pérdidas de Transmisión", "Energía en Pérdidas de transmisión"),
    ("Extra Costo por Generación Obligada", "Extra costo por generación obligada"),
    ("Servicio Auxiliar de seguimiento de la demanda", "Servicio Auxiliar de seguimiento de la demanda"),
    ("Servicios Auxiliares", "Servicios Auxiliares"),
]


def nombre_mes(periodo: str) -> str:
    try:
        return MESES[int(periodo[4:6])]
    except (ValueError, IndexError):
        return periodo


def anio(periodo: str) -> str:
    return periodo[:4] if periodo and len(periodo) >= 4 else ""


def periodo_largo(periodo: str) -> str:
    return f"{nombre_mes(periodo)} {anio(periodo)}".strip()


def mes_abrev(periodo: str) -> str:
    """'202607' -> 'Jul-2026' (etiqueta de la columna Consumos)."""
    try:
        return f"{MES_ABR[int(periodo[4:6])]}-{periodo[2:4]}"
    except (ValueError, IndexError):
        return periodo


def periodo_anterior(periodo: str) -> str:
    """'202607' -> '202606'. Para el DTER del mes previo (regla del sistema viejo)."""
    if len(periodo) == 6 and periodo.isdigit():
        a, m = int(periodo[:4]), int(periodo[4:6])
        m -= 1
        if m == 0:
            m, a = 12, a - 1
        return f"{a:04d}{m:02d}"
    return periodo


def precio_vigente(db, id_contrato: int | None, periodo: str) -> tuple[float | None, str | None]:
    """(precio, tarifa) vigente del contrato para el periodo (tabla `precios`).

    Replica el uso que hacia el sistema viejo de la tabla `Precios`: el precio
    vigente es el que cubre el primer dia del periodo (Inicia <= periodo <=
    Termina). Si ninguno cubre el rango (p. ej. periodo sin tarifa cargada) usa
    el mas reciente del contrato. Devuelve (None, None) si el contrato no tiene
    precios.
    """
    if not id_contrato:
        return None, None
    from app.models import Precio  # import local: evita ciclos con routers

    try:
        ref = datetime(int(periodo[:4]), int(periodo[4:6]), 1)
    except (ValueError, IndexError, TypeError):
        ref = datetime.utcnow()
    base = db.query(Precio).filter(Precio.id_contrato == id_contrato)
    p = (
        base.filter((Precio.inicia.is_(None)) | (Precio.inicia <= ref))
        .filter((Precio.termina.is_(None)) | (Precio.termina >= ref))
        .order_by(Precio.inicia.desc())
        .first()
    ) or base.order_by(Precio.inicia.desc()).first()
    if not p:
        return None, None
    return (float(p.precio) if p.precio is not None else None, p.tarifa)


def truncar(v: float, dec: int = 3) -> float:
    """Trunca (no redondea) a 'dec' decimales.

    El sistema viejo calcula la energia con el consumo medido a 6 decimales
    pero lo *muestra* truncado a 3 (102.7766 -> 102.776). Sin esto la factura
    no cuadraria al centavo con la del sistema anterior.
    """
    factor = 10 ** dec
    valor = abs(float(v)) * factor
    # +1e-9 corrige el error de coma flotante (102.7766*1000 = 102776.5999...)
    return int(valor + 1e-9) / factor * (1 if v >= 0 else -1)


def clientes_del_agente(db, id_agente: int) -> list:
    """Clientes que pertenecen a un agente (ordenados por nombre).

    La relacion real en los datos es via `contratos.id_agente` (cada cliente
    tiene un contrato con su agente emisor); `clientes.id_distribuidor` se usa
    como respaldo por si el cliente esta marcado directamente con su
    distribuidor.
    """
    from app.models import Cliente, Contrato  # import local: evita ciclos

    por_contrato = (
        db.query(Cliente)
        .join(Contrato, Contrato.id_cliente == Cliente.id)
        .filter(Contrato.id_agente == id_agente)
        .distinct()
        .all()
    )
    vistos = {c.id for c in por_contrato}
    extras = db.query(Cliente).filter(Cliente.id_distribuidor == id_agente).all()
    todos = list(por_contrato) + [c for c in extras if c.id not in vistos]
    return sorted(todos, key=lambda c: ((c.nombre or c.codigo or "").lower()))



def _num(txt: str) -> float:
    txt = (txt or "").strip().replace(",", "")
    if not txt:
        return 0.0
    try:
        return float(txt)
    except ValueError:
        return 0.0


def leer_texto(archivo: Path) -> str:
    """Los DTE del portal son UTF-8; leerlos como latin-1 corrompia los nombres
    de transaccion ("Energía" -> "EnergÃ­a") y los cargos no coincidian con
    la lista CARGOS, asi que se omitian de la factura."""
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return archivo.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return archivo.read_text(encoding="latin-1", errors="replace")


def cargar_cargos_dte(codigo_cliente: str, periodo: str) -> dict[str, dict[str, float]]:
    """Agrega los cargos del DTE del cliente (por transaccion) en un periodo.

    Busca en CND_Scraper/raw/*/CND_DTE_TABULAR/<periodo>/*<codigo>*.txt los
    archivos del cliente y suma CANTIDAD / DEBITO / CREDITO por TRANSACCION.
    Devuelve {transaccion: {mwh, debito, credito}}.
    """
    resultado: dict[str, dict[str, float]] = {}
    if not RAW_DIR.exists():
        return resultado
    codigo = codigo_cliente.upper()
    for carpeta in RAW_DIR.rglob("CND_DTE_TABULAR"):
        sub = carpeta / periodo
        if not sub.is_dir():
            continue
        for archivo in sub.glob("*.txt"):
            if codigo not in archivo.name.upper():
                continue
            try:
                texto = leer_texto(archivo)
            except Exception:
                continue
            for linea in texto.splitlines()[1:]:
                if not linea.strip():
                    continue
                p = linea.split("\t")
                if len(p) < 9:
                    continue
                if p[1].strip().strip('"').upper() != codigo:
                    continue
                trans = p[2].strip().strip('"')
                d = resultado.setdefault(trans, {"mwh": 0.0, "debito": 0.0, "credito": 0.0})
                d["mwh"] += _num(p[6])
                d["debito"] += _num(p[7])
                d["credito"] += _num(p[8])
    return resultado


def cargos_desde_dte(
    db, codigo_cliente: str, periodo: str, tipo: str = "Regular"
) -> dict[str, dict[str, float]]:
    """Cargos de mercado leidos de la tabla `dte`.

    Equivale a `fn_costos` / `fn_CostoMercado` del sistema viejo: agrupa por
    TRANSACCION y suma DEBITO / CREDITO de los DTE del cliente en el periodo.
    Devuelve la MISMA forma que `cargar_cargos_dte`:
        {transaccion: {"mwh": float, "debito": float, "credito": float}}
    El neto de una transaccion = debito - credito.
    """
    filas = db.execute(
        text(
            "SELECT transaccion, "
            "       SUM(CASE WHEN atributo='Debito'  THEN valor    ELSE 0 END) AS debito, "
            "       SUM(CASE WHEN atributo='Credito' THEN valor    ELSE 0 END) AS credito, "
            "       SUM(CASE WHEN atributo='Debito'  THEN cantidad ELSE 0 END) AS mwh "
            "FROM dte "
            "WHERE UPPER(cliente) = :c AND periodo = :p AND tipo = :t "
            "GROUP BY transaccion"
        ),
        {"c": codigo_cliente.upper(), "p": periodo, "t": tipo},
    ).mappings().all()
    return {
        r["transaccion"]: {
            "mwh": float(r["mwh"] or 0),
            "debito": float(r["debito"] or 0),
            "credito": float(r["credito"] or 0),
        }
        for r in filas
    }


def dter_desde_tabla(db, codigo_cliente: str, periodo: str) -> float:
    """DTER del periodo leido de la tabla `dter` (equivale a `fn_DTER_Mes`).

    Neto = SUM(Debito) - SUM(Credito) para el cliente y periodo.
    """
    monto = db.execute(
        text(
            "SELECT SUM(CASE WHEN atributo='Debito' THEN valor ELSE -valor END) "
            "FROM dter WHERE UPPER(cliente) = :c AND periodo = :p"
        ),
        {"c": codigo_cliente.upper(), "p": periodo},
    ).scalar()
    return float(monto or 0)


def consumo_desde_mediciones(db, codigo_cliente: str, periodo: str) -> float | None:
    """Consumo mensual medido (MWh) leido de la tabla `mediciones`.

    Es el consumo que el sistema viejo tomaba de la tabla `Mediciones` para
    facturar la energia (fn_historialconsumo). Aqui ya esta pre-agregado por
    (cliente, generador, periodo) a 6 decimales.
    Devuelve None si el cliente/periodo no tiene medicion cargada.
    """
    valor = db.execute(
        text(
            "SELECT SUM(consumo) FROM mediciones "
            "WHERE UPPER(cliente) = :c AND periodo = :p"
        ),
        {"c": codigo_cliente.upper(), "p": periodo},
    ).scalar()
    return float(valor) if valor is not None else None


def historial_mediciones(
    db, codigo_cliente: str, hasta: str | None = None, limite: int = 13
) -> dict[str, float]:
    """{periodo: consumo} de los ultimos `limite` meses medidos del cliente.

    Replica `fn_historialconsumo` del sistema viejo: TOP 13 meses de
    SUM(Consumo) agrupados por mes, mas reciente primero. `hasta` corta en el
    periodo de la factura (Fecha <= @Corte).
    """
    sql = (
        "SELECT periodo, SUM(consumo) AS consumo FROM mediciones "
        "WHERE UPPER(cliente) = :c"
    )
    params: dict = {"c": codigo_cliente.upper()}
    if hasta:
        sql += " AND periodo <= :h"
        params["h"] = hasta
    sql += " GROUP BY periodo ORDER BY periodo DESC LIMIT :n"
    params["n"] = limite
    filas = db.execute(text(sql), params).mappings().all()
    return {r["periodo"]: float(r["consumo"] or 0) for r in filas}


def lineas_factura(
    cargos_dte: dict[str, dict[str, float]],
    consumo_mwh: float,
    precio_kwh: float,
    incluir_dte: bool = True,
    periodo: str = "",
    dter_monto: float | None = None,
    dter_periodo: str | None = None,
    descuento: float | None = None,
    otros_cargos: list[dict] | None = None,
) -> list[dict]:
    """Arma la lista de lineas de detalle (dicts listos para FacturaDetalle).

    Replica el detalle del sistema viejo (factura CEK):
      - Energia en contratos = consumo(MWh) x 1000 x precio($/kWh)
      - Rubro "Costo de Mercado de <Mes> <Anio>" con los cargos reales del DTE
      - DTER del mes anterior (fn_DTER_Mes del sistema viejo)
      - Otros cargos (nombre + monto) capturados a mano en la factura
      - Descuento por pronto pago (se resta; en el viejo es Facturas.Descuento)
    """
    lineas: list[dict] = []
    orden = 0

    monto_contratos = round(consumo_mwh * 1000 * precio_kwh, 2)
    lineas.append(dict(
        orden=orden, categoria=None, descripcion="Energía en contratos",
        consumo=mes_abrev(periodo), cantidad=truncar(float(consumo_mwh), 3), unidad="MWh",
        monto=monto_contratos, es_total=True,
    ))
    orden += 1

    if incluir_dte and cargos_dte:
        lineas.append(dict(
            orden=orden, categoria=None,
            descripcion=f"Costo de Mercado de {periodo_largo(periodo)}".strip(),
            consumo="", cantidad=None, unidad="", monto=None, es_total=False,
        ))
        orden += 1
        for nombre_cnd, etiqueta in CARGOS:
            if nombre_cnd == "Energía en Mercado Ocasional":
                continue  # ya se factura como "Energía en contratos"
            d = cargos_dte.get(nombre_cnd)
            if not d or (abs(d["debito"]) < 0.005 and abs(d["mwh"]) < 0.0005):
                continue
            monto = round(d["debito"] - d["credito"], 2)
            lineas.append(dict(
                orden=orden, categoria=None, descripcion=etiqueta,
                consumo="", cantidad=round(d["mwh"], 3) if d["mwh"] else None,
                unidad="MWh" if d["mwh"] else "", monto=monto, es_total=True,
            ))
            orden += 1

    # DTER del mes anterior (cargo regional que el CND factura con un mes de rezago).
    if incluir_dte and dter_monto is not None and abs(dter_monto) > 0.004:
        dp = dter_periodo or periodo_anterior(periodo)
        lineas.append(dict(
            orden=orden, categoria=None,
            descripcion=f"DTER de {periodo_largo(dp)}".strip(),
            consumo="", cantidad=None, unidad="", monto=round(dter_monto, 2),
            es_total=True,
        ))
        orden += 1

    # Otros cargos capturados a mano (nombre + monto). Permite varios.
    for c in (otros_cargos or []):
        nombre = (c.get("nombre") or "").strip()
        monto = c.get("monto")
        if not nombre or monto is None or abs(float(monto)) < 0.005:
            continue
        lineas.append(dict(
            orden=orden, categoria=None, descripcion=nombre,
            consumo="", cantidad=None, unidad="", monto=round(float(monto), 2),
            es_total=True,
        ))
        orden += 1

    # Descuento por pronto pago: se resta del subtotal (Facturas.Descuento del viejo).
    if descuento is not None and abs(float(descuento)) > 0.004:
        lineas.append(dict(
            orden=orden, categoria=None, descripcion="Descuento por pronto pago",
            consumo="", cantidad=None, unidad="",
            monto=-round(abs(float(descuento)), 2), es_total=True,
        ))
        orden += 1
    return lineas



def totales(lineas: Iterable[dict], itbms_pct: float) -> tuple[float, float, float]:
    subtotal = round(sum(l["monto"] or 0 for l in lineas if l["es_total"]), 2)
    itbms = round(subtotal * (itbms_pct / 100.0), 2)
    return subtotal, itbms, round(subtotal + itbms, 2)


# --------------------------------------------------------------------------- #
# HTML
# --------------------------------------------------------------------------- #
def _esc(x) -> str:
    return html.escape(str(x))


def _abrev(v: float) -> str:
    a = abs(v)
    if a >= 1_000_000:
        return f"{v/1_000_000:.1f}M"
    if a >= 10_000:
        return f"{v/1000:.0f}k"
    if a >= 1000:
        return f"{v/1000:.1f}k"
    if a >= 10:
        return f"{v:.0f}"
    return f"{v:.1f}".rstrip("0").rstrip(".")


def _svg_grafica(p: dict, ancho: int = 940, alto: int = 360) -> str:
    """Grafica profesional de barras (y linea opcional con segundo eje).

    p = {
      titulo, subtitulo, unidad, unidad_derecha,
      eje_x: [...], 
      series: [ {nombre, valores:[...]} ],
      linea: {nombre, valores:[...]} | None,
    }
    Barras verticales azul/morado, fondo blanco, cuadricula gris clara.
    No se calculan ni alteran datos: solo se grafican los valores recibidos.
    """
    etiquetas = list(p.get("eje_x") or [])
    series = p.get("series") or []
    valores = list(series[0].get("valores") if series else [])
    n = len(valores)
    if n == 0:
        return ("<div style='padding:24px;color:#5d6875;text-align:center;"
                "border:1px dashed #c3ccd6;border-radius:8px'>Sin datos de consumo "
                "para este periodo.</div>")

    modo = (p.get("modo") or "barras").strip().lower()
    linea = p.get("linea") or None
    vals_lin = list((linea or {}).get("valores") or [])
    con_linea = bool(linea) and any(v is not None for v in vals_lin)

    m_izq, m_sup, m_inf = 74, 16, 52
    m_der = 78 if con_linea else 26
    area_w = ancho - m_izq - m_der
    area_h = alto - m_sup - m_inf

    techo = max([v for v in valores if v is not None] + [0]) or 0
    techo = techo * 1.12 if techo > 0 else 1.0

    paso = area_w / n
    ancho_barra = max(3.0, min(58.0, paso * 0.62))

    partes = [
        f"<svg viewBox='0 0 {ancho} {alto}' width='100%' preserveAspectRatio='xMidYMid meet' "
        f"role='img' aria-label='{_esc(p.get('titulo') or 'Consumo')}' "
        "xmlns='http://www.w3.org/2000/svg' font-family='Arial,Helvetica,sans-serif'>",
        # fondo
        f"<rect x='0' y='0' width='{ancho}' height='{alto}' fill='#ffffff'/>",
    ]

    base_y = m_sup + area_h
    # cuadricula + eje Y izquierdo (kWh)
    for i in range(5):
        gy = m_sup + area_h * i / 4
        val = techo * (4 - i) / 4
        partes.append(
            f"<line x1='{m_izq}' y1='{gy:.1f}' x2='{m_izq + area_w}' y2='{gy:.1f}' "
            "stroke='#e6ebf1' stroke-width='1'/>"
        )
        partes.append(
            f"<text x='{m_izq - 8}' y='{gy + 3.5:.1f}' text-anchor='end' "
            "font-size='10' fill='#6b7683'>"
            + _esc(("{:.3f}".format(val)) if modo == "puntos" else _abrev(val))
            + "</text>"
        )
    # eje X
    partes.append(f"<line x1='{m_izq}' y1='{base_y:.1f}' x2='{m_izq + area_w}' "
                  f"y2='{base_y:.1f}' stroke='#9aa6b2' stroke-width='1'/>")

    # serie principal: barras (por defecto) o puntos unidos por linea
    if modo == "puntos":
        pts = []
        for i, v in enumerate(valores):
            if v is None:
                continue
            val = max(float(v), 0)
            h = area_h * (val / techo) if techo else 0
            x = m_izq + paso * (i + 0.5)
            y = base_y - h
            pts.append((x, y, val, i))
        if len(pts) >= 2:
            d_poly = " ".join(f"{x:.1f},{y:.1f}" for x, y, _, _ in pts)
            partes.append(
                f"<polyline points='{d_poly}' fill='none' stroke='#F0A020' stroke-width='2.4' "
                "stroke-linejoin='round' stroke-linecap='round'/>"
            )
        for x, y, val, i in pts:
            partes.append(
                f"<circle cx='{x:.1f}' cy='{y:.1f}' r='3.4' fill='#F0A020' "
                "stroke='#ffffff' stroke-width='1.2'>"
                f"<title>{_esc(p.get('titulo'))}: {val:.4f} {_esc(p.get('unidad') or '')} "
                f"(x={_esc(etiquetas[i] if i < len(etiquetas) else i+1)})</title></circle>"
            )
    else:
        for i, v in enumerate(valores):
            val = 0.0 if v is None else float(v)
            h = area_h * (max(val, 0) / techo) if techo else 0
            x = m_izq + paso * i + (paso - ancho_barra) / 2
            y = base_y - h
            partes.append(
                f"<rect x='{x:.1f}' y='{y:.1f}' width='{ancho_barra:.1f}' "
                f"height='{max(h, 0):.1f}' rx='3' fill='#3B5BA5'>"
                f"<title>{_esc(p.get('titulo'))}: {_abrev(val)} {_esc(p.get('unidad') or '')} "
                f"(x={_esc(etiquetas[i] if i < len(etiquetas) else i+1)})</title></rect>"
            )

    # eje X: etiquetas
    cada = 1
    if n > 16:
        cada = 2
    if n > 16 and etiquetas and any(len(str(e)) > 3 for e in etiquetas):
        cada = 2
    for i, etq in enumerate(etiquetas):
        if i % cada != 0 and i != n - 1:
            continue
        cx = m_izq + paso * (i + 0.5)
        partes.append(
            f"<text x='{cx:.1f}' y='{base_y + 16:.1f}' text-anchor='middle' "
            f"font-size='9.5' fill='#6b7683'>{_esc(etq)}</text>"
        )
    partes.append(
        f"<text x='{m_izq + area_w/2:.1f}' y='{alto - 6:.1f}' text-anchor='middle' "
        f"font-size='10' fill='#9aa4b0'>{_esc(p.get('unidad') or '')}</text>"
    )

    # linea opcional (segundo eje, valores monetarios)
    if con_linea:
        vv = [v for v in vals_lin if v is not None]
        tope_lin = (max(vv) if vv else 1) * 1.12 or 1
        for i in range(5):
            gy = m_sup + area_h * i / 4
            val = tope_lin * (4 - i) / 4
            partes.append(
                f"<text x='{m_izq + area_w + 8}' y='{gy + 3.5:.1f}' text-anchor='start' "
                f"font-size='10' fill='#b07a20'>{val:.3f}</text>"
            )
        puntos = []
        for i, v in enumerate(vals_lin):
            if v is None:
                continue
            y = m_sup + area_h - area_h * (v / tope_lin)
            x = m_izq + paso * (i + 0.5)
            puntos.append((x, y))
        if len(puntos) >= 2:
            d = " ".join(f"{x:.1f},{y:.1f}" for x, y in puntos)
            partes.append(
                f"<polyline points='{d}' fill='none' stroke='#F0A020' stroke-width='2.2' "
                "stroke-linejoin='round' stroke-linecap='round'/>"
            )
        for x, y in puntos:
            partes.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='2.6' fill='#F0A020'/>")
        partes.append(
            f"<text x='{m_izq + area_w + 8}' y='{m_sup - 4:.1f}' text-anchor='start' "
            f"font-size='9.5' fill='#b07a20'>{_esc(p.get('unidad_derecha') or '')}</text>"
        )

    partes.append("</svg>")
    return "".join(partes)


def _leyenda_svg(p: dict) -> str:
    azul = "#315C8A"
    ambar = "#F0A020"
    if (p.get("modo") or "").lower() == "puntos":
        nombre = ((p.get("series") or [{}])[0].get("nombre")) or "Costo promedio"
        return (
            "<div style='display:flex;gap:22px;flex-wrap:wrap;font-size:9.5pt;"
            "margin:2mm 0 3mm'>"
            "<span style='display:inline-flex;align-items:center;gap:6px;color:#4a5561'>"
            f"<i style='width:16px;height:0;border-top:2.4px solid {ambar};display:inline-block'></i> "
            + _esc(nombre) + "</span></div>"
        )
    unidad = _esc(p.get("unidad") or "")
    items = [
        f"<span style='display:inline-flex;align-items:center;gap:6px;"
        f"color:#4a5561'><i style='width:12px;height:12px;border-radius:3px;"
        f"background:{azul};display:inline-block'></i> Consumo ({unidad})</span>"
    ]
    if p.get("linea"):
        items.append(
            f"<span style='display:inline-flex;align-items:center;gap:6px;color:#4a5561'>"
            f"<i style='width:16px;height:0;border-top:2.4px solid {ambar};"
            f"display:inline-block'></i> {_esc(p['linea'].get('nombre') or 'Costo')}</span>"
        )
    return ("<div style='display:flex;gap:22px;flex-wrap:wrap;font-size:9.5pt;"
            "margin:2mm 0 3mm'>" + "".join(items) + "</div>")


def _fmt2(v) -> str:
    return "{:,.2f}".format(float(v or 0))


def _fmt3(v) -> str:
    return "{:,.3f}".format(float(v or 0))


def _fecha(dt) -> str:
    if not dt:
        return "&nbsp;"
    if hasattr(dt, "strftime"):
        return dt.strftime("%d/%m/%Y")
    return _esc(dt)


_CSS = """
  :root { --ink:#202a35; --muted:#5d6875; --line:#aab4c0; --soft:#edf2f8; --blue:#315c8a; --accent:#d84a43; }
  * { box-sizing:border-box; }
  html { background:#e9edf2; }
  body { margin:0; color:var(--ink); font-family:Arial,Helvetica,sans-serif; font-size:10pt; line-height:1.35; }
  .toolbar { max-width:210mm; margin:16px auto; padding:12px 16px; background:#fff; border:1px solid #d3dbe4;
             border-radius:8px; display:flex; gap:12px; align-items:center; justify-content:space-between; }
  .toolbar button { border:0; border-radius:5px; padding:10px 16px; color:#fff; background:var(--blue); font-weight:700; cursor:pointer; }
  .toolbar .hint { color:var(--muted); font-size:9pt; }
  .invoice { width:210mm; min-height:297mm; margin:0 auto 20px; padding:12mm 12mm 15mm; background:#fff; box-shadow:0 2px 14px #00000016; }
  .page-break { page-break-before:always; break-before:page; }
  .top-rule { height:3px; margin-bottom:7mm; background:linear-gradient(90deg,#e54b48 0 50%,#5267df 50% 100%); }
  .company-header { display:grid; grid-template-columns:1fr 1.4fr; gap:10mm; align-items:start; margin-bottom:7mm; }
  .brand { display:flex; gap:8px; align-items:center; font-size:22pt; font-weight:800; letter-spacing:.4px; color:#343b43; }
  .brand-mark { width:27px; height:27px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center;
                background:#d9dee4; color:#626b75; font-size:12pt; border:1px solid #b9c0c8; }
  .company-info { text-align:right; overflow-wrap:anywhere; }
  .company-info .company-name { color:var(--blue); font-family:Georgia,"Times New Roman",serif; font-size:17pt; line-height:1.15; }
  .company-info .small { font-size:8.5pt; }
  .invoice-month { display:flex; justify-content:flex-end; align-items:baseline; gap:10px; margin:4mm 0 3mm; font-size:15pt; }
  .invoice-month .year { color:#a83232; }
  .info-grid { display:grid; grid-template-columns:1fr 1fr; gap:3mm; margin-bottom:3mm; }
  .info-panel { border:1px solid #26313d; min-width:0; }
  .panel-title { padding:5px 8px; background:#dce5f1; border-bottom:1px solid #26313d; text-align:center; font-weight:700; font-size:9pt; }
  .info-panel dl { margin:0; padding:7px 8px; display:grid; grid-template-columns:28% 72%; gap:4px 6px; font-size:8.5pt; }
  .info-panel dt { color:#3f4954; text-transform:uppercase; font-size:7.7pt; overflow-wrap:anywhere; word-break:break-word; }
  .info-panel dd { margin:0; overflow-wrap:anywhere; word-break:break-word; white-space:normal; }
  .section-heading { margin:5mm 0 2mm; color:var(--blue); font-size:11pt; font-weight:700; }
  table { width:100%; border-collapse:collapse; table-layout:fixed; font-size:9pt; }
  col.c-consumption { width:18%; } col.c-quantity { width:10%; } col.c-unit { width:8%; }
  col.c-description { width:44%; } col.c-total { width:20%; }
  thead { display:table-header-group; } tfoot { display:table-row-group; }
  th { background:#dce5f1; border:1px solid #26313d; padding:7px 6px; text-align:left; vertical-align:bottom;
        font-size:8.5pt; white-space:normal; overflow-wrap:anywhere; word-break:break-word; }
  td { border:1px solid #26313d; padding:7px 6px; vertical-align:top;
        overflow-wrap:anywhere; word-break:break-word; white-space:normal; }
  tbody tr { break-inside:avoid; page-break-inside:avoid; }
  .num { text-align:right; white-space:nowrap; font-variant-numeric:tabular-nums; }
  .category-row td { background:#f5f7fa; color:#394b60; font-weight:700; border-top:1px solid #26313d; }
  .th-consumos .th-unit { display:block; font-weight:400; font-size:7.5pt; color:#5d6875; }
  .consumos { overflow-wrap:normal; word-break:normal; }
  .consumos .hline { display:flex; justify-content:space-between; gap:8px; white-space:nowrap; padding:1px 0; color:#3f4954; }
  .consumos .hline span { white-space:nowrap; }
  .consumos .hline + .hline { margin-top:2px; }
  .consumos .hline:first-child { color:var(--ink); font-weight:700; padding-bottom:4px; margin-bottom:2px; border-bottom:1px dashed #b6c0cb; }
  .consumos .mwh { font-variant-numeric:tabular-nums; }
  .subtotal-row td { border-top:1px solid #c7ced6; }
  .subtotal-row .description { text-align:right; font-weight:700; }
  .grand-total td { border-top:2px solid #26313d; background:#edf2f8; font-size:11pt; font-weight:800; }
  .grand-total .description { text-align:right; }
  .notes { margin-top:7mm; color:var(--muted); font-size:8pt; }
  .footer { margin-top:10mm; padding-top:3mm; border-top:1px solid #c7ced6; color:var(--muted); font-size:8pt; display:flex; justify-content:space-between; gap:8px; }
  .chart-title { color:var(--blue); font-size:13pt; font-weight:700; margin:2mm 0 1mm; }
  .chart-sub { color:var(--muted); font-size:9pt; margin-bottom:2mm; }
  @page { size:A4; margin:10mm 12mm 12mm; }
  @media print {
    html,body { background:#fff; } body { font-size:9pt; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
    .toolbar { display:none !important; }
    .invoice { width:auto; min-height:0; margin:0; padding:0; box-shadow:none; border:0; }
    .top-rule { margin-top:0; }
    .company-header,.info-grid,.invoice-month { break-inside:avoid; page-break-inside:avoid; }
    table { break-inside:auto; page-break-inside:auto; }
    tr { break-inside:avoid; page-break-inside:avoid; }
    .grand-total,.subtotal-row,.notes,.footer { break-inside:avoid; page-break-inside:avoid; }
  }
"""


def _pagina_grafica_html(datos: dict, g: dict) -> str:
    """Pagina (page-break) con una grafica de consumo."""
    cl = datos.get("cliente") or {}
    periodo = datos.get("periodo") or ""
    nombre = g.get("cliente") or cl.get("nombre") or ""
    titulo = g.get("titulo") or "Consumo"
    unidad = g.get("unidad") or "kWh"
    rango = g.get("rango") or periodo_largo(periodo)
    out = [
        '  <main class="invoice page-break">',
        '    <div class="top-rule"></div>',
        '    <div class="company-header">',
        '      <div><div class="brand"><span class="brand-mark">&#9670;</span><span>Consumo</span></div></div>',
        '      <div class="company-info">',
        '        <div class="company-name">' + _esc(nombre) + '</div>',
        '        <div class="small">' + _esc(titulo) + ' &middot; ' + _esc(rango) + '</div>',
        '      </div>',
        '    </div>',
        '    <div class="chart-title">' + _esc(titulo) + ' (' + _esc(unidad) + ')</div>',
        '    <div class="chart-sub">' + _esc(g.get("subtitulo") or "") + '</div>',
        '    ' + _leyenda_svg(g),
        '    ' + _svg_grafica(g),
        '    <div class="notes">',
        '      Datos reales del per\u00edodo ' + _esc(periodo_largo(periodo)) + '.',
        '      El consumo (kWh) y, cuando aplica, el costo promedio por kWh se toman de los',
        '      reportes oficiales del CND para el cliente ' + _esc(g.get("codigo") or cl.get("codigo") or "") + '.',
        '    </div>',
        '    <footer class="footer">',
        '      <span>Factura ' + _esc(datos.get("numero") or "") + '</span>',
        '      <span>CEK</span>',
        '    </footer>',
        '  </main>',
    ]
    return "\n".join(out)


def render_html(datos: dict) -> str:
    """HTML completo de la factura: pagina 1 (factura) + una pagina por grafica.

    Conserva el diseno original (CSS, cabecera, tablas, totales). Solo se
    grafican los valores recibidos en ``datos``.
    """
    d = datos
    em = d.get("emisor") or {}
    cl = d.get("cliente") or {}
    numero = d.get("numero") or ""
    periodo = d.get("periodo") or ""
    moneda = d.get("moneda") or "B/."
    lineas = list(d.get("lineas") or [])
    historico = list(d.get("historico") or [])
    n = len(lineas)

    graficas_lista = d.get("graficas")
    if not isinstance(graficas_lista, list) or not graficas_lista:
        graficas_lista = [d.get("grafica") or {}]

    # Columna "Consumos": historial de mediciones (primera fila abarca con rowspan).
    if historico:
        inner = "".join(
            "<div class='hline'><span>" + _esc(h.get("etiqueta") or "") + "</span>"
            "<span class='mwh'>" + _fmt3(h.get("mwh")) + "</span></div>"
            for h in historico
        )
        celda_primera = "<td class='consumos' rowspan='" + str(max(n, 1)) + "'>" + inner + "</td>"
    else:
        celda_primera = "<td></td>"

    filas = []
    for i, ln in enumerate(lineas):
        desc = _esc(ln.get("descripcion") or "")
        monto = ln.get("monto")
        if i == 0:
            lead = celda_primera
        else:
            lead = "" if historico else "<td></td>"
        if monto is None:
            filas.append(
                "<tr class='category-row'>" + lead
                + "<td></td><td></td><td class='description'>" + desc + "</td><td class='num'></td></tr>"
            )
            continue
        cant = _fmt3(ln.get("cantidad")) if (i == 0 and ln.get("cantidad") is not None) else ""
        unidad = _esc(ln.get("unidad") or "") if i == 0 else ""
        filas.append(
            "<tr>" + lead
            + "<td class='num'>" + cant + "</td><td>" + unidad + "</td>"
            + "<td class='description'>" + desc + "</td>"
            + "<td class='num amount'>" + _fmt2(monto) + "</td></tr>"
        )

    pct = "{:g}".format(float(d.get("itbms_pct") or 0))
    filas.append("<tr class='subtotal-row'><td colspan='3'></td><td class='description'>Subtotal</td><td class='num'>" + _fmt2(d.get("subtotal")) + "</td></tr>")
    filas.append("<tr class='subtotal-row'><td colspan='3'></td><td class='description'>ITBMS " + pct + "%</td><td class='num'>" + _fmt2(d.get("itbms")) + "</td></tr>")
    filas.append("<tr class='grand-total'><td colspan='3'></td><td class='description'>TOTAL</td><td class='num amount'>" + _fmt2(d.get("total")) + "</td></tr>")

    obs = d.get("observaciones") or "Sin observaciones"

    p = []
    p.append("<!DOCTYPE html>")
    p.append('<html lang="es">')
    p.append("<head>")
    p.append('<meta charset="utf-8">')
    p.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
    p.append("<title>Factura " + _esc(numero) + " - " + _esc(em.get("nombre") or "") + "</title>")
    p.append("<style>")
    p.append(_CSS)
    p.append("</style>")
    p.append("</head>")
    p.append("<body>")
    p.append('  <div class="toolbar">')
    p.append('    <div><strong>Factura ' + _esc(numero) + "</strong>")
    p.append('      <div class="hint">Use \u00abImprimir / Guardar como PDF\u00bb para generar el documento.</div></div>')
    p.append('    <button type="button" onclick="window.print()">Imprimir / Guardar como PDF</button>')
    p.append("  </div>")
    p.append("")
    p.append('  <main class="invoice">')
    p.append('    <div class="top-rule"></div>')
    p.append('    <header class="company-header">')
    p.append('      <div><div class="brand"><span class="brand-mark">&#9670;</span><span>' + _esc(em.get("nombre") or "") + "</span></div></div>")
    p.append('      <div class="company-info">')
    p.append('        <div class="company-name">' + _esc(em.get("razon_social") or "") + "</div>")
    p.append('        <div class="small">RUC: ' + (_esc(em.get("ruc")) if em.get("ruc") else "&nbsp;") + "</div>")
    p.append('        <div class="small">' + (_esc(em.get("direccion")) if em.get("direccion") else "&nbsp;") + "</div>")
    p.append('        <div class="small">Tel\u00e9fono: ' + (_esc(em.get("telefono")) if em.get("telefono") else "&nbsp;") + "</div>")
    p.append("      </div>")
    p.append("    </header>")
    p.append("")
    p.append('    <div class="invoice-month"><span>' + _esc(nombre_mes(periodo)) + '</span><span class="year">' + _esc(anio(periodo)) + "</span></div>")
    p.append("")
    p.append('    <section class="info-grid">')
    p.append('      <div class="info-panel">')
    p.append('        <div class="panel-title">Datos del Cliente</div>')
    p.append("        <dl>")
    p.append("          <dt>Nombre</dt><dd>" + _esc(cl.get("nombre") or "") + "</dd>")
    p.append("          <dt>C\u00f3digo</dt><dd>" + _esc(cl.get("codigo") or "") + "</dd>")
    p.append("          <dt>RUC</dt><dd>" + (_esc(cl.get("ruc")) if cl.get("ruc") else "&nbsp;") + "</dd>")
    p.append("          <dt>Tel\u00e9fono</dt><dd>" + (_esc(cl.get("telefono")) if cl.get("telefono") else "&nbsp;") + "</dd>")
    p.append("          <dt>Direcci\u00f3n</dt><dd>" + (_esc(cl.get("direccion")) if cl.get("direccion") else "&nbsp;") + "</dd>")
    p.append("          <dt>Atenci\u00f3n</dt><dd>" + (_esc(cl.get("contacto")) if cl.get("contacto") else "&nbsp;") + "</dd>")
    p.append("        </dl>")
    p.append("      </div>")
    p.append('      <div class="info-panel">')
    p.append('        <div class="panel-title">Datos de la Factura</div>')
    p.append("        <dl>")
    p.append("          <dt>N.\u00ba</dt><dd>" + _esc(numero) + "</dd>")
    p.append("          <dt>Fecha de emisi\u00f3n</dt><dd>" + _fecha(d.get("fecha_emision")) + "</dd>")
    p.append("          <dt>Per\u00edodo</dt><dd>" + _esc(periodo_largo(periodo)) + "</dd>")
    p.append("          <dt>D\u00edas de lectura</dt><dd>" + _esc(d.get("dias_lectura") if d.get("dias_lectura") is not None else "") + "</dd>")
    p.append("          <dt>Vencimiento</dt><dd>" + _fecha(d.get("fecha_vencimiento")) + "</dd>")
    p.append("          <dt>Tarifa</dt><dd>" + _esc(d.get("tarifa") or "") + "</dd>")
    p.append("          <dt>Precio</dt><dd>" + "{:.4f}".format(float(d.get("precio_kwh") or 0)) + " " + _esc(moneda) + "/kWh</dd>")
    p.append("        </dl>")
    p.append("      </div>")
    p.append("    </section>")
    p.append("")
    p.append('    <div class="section-heading">Detalle de consumo y cargos</div>')
    p.append('    <table aria-label="Detalle de consumo y cargos">')
    p.append('      <colgroup><col class="c-consumption"><col class="c-quantity"><col class="c-unit"><col class="c-description"><col class="c-total"></colgroup>')
    p.append('      <thead><tr><th class="th-consumos">Consumos<span class="th-unit">MWh</span></th><th class="num">Cantidad</th><th>Unidad</th><th>Descripci\u00f3n</th><th class="num">Total (B/.)</th></tr></thead>')
    p.append("      <tbody>")
    p.append("".join(filas))
    p.append("      </tbody>")
    p.append("    </table>")
    p.append("")
    p.append('    <div class="notes">')
    p.append("      Observaciones: " + _esc(obs) + ".")
    p.append("      <br>Estado: " + _esc(d.get("estado") or "") + " \u00b7 Consumo registrado: " + _fmt3(d.get("consumo_mwh")) + " MWh.")
    p.append("    </div>")
    p.append('    <footer class="footer">')
    p.append("      <span>" + _esc(em.get("nombre") or "") + "</span>")
    p.append("      <span>Documento generado autom\u00e1ticamente por CEK</span>")
    p.append("    </footer>")
    p.append("  </main>")

    for g in graficas_lista:
        if isinstance(g, dict):
            p.append("")
            p.append(_pagina_grafica_html(d, g))

    p.append("</body>")
    p.append("</html>")
    return "\n".join(p)
