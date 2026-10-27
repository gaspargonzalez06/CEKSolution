# -*- coding: utf-8 -*-
"""Reportes Comerciales (riel de los SPs del sistema viejo).

Reimplementa sobre MariaDB la logica de 4 procedimientos almacenados de la
base vieja (SQL Server / CEK):

  usp_reporte_comercial(@cGenerador, @cPeriodo)          -> reporte_comercial
  usp_reporte_comercial_DTER(@cGenerador, @nAnnio, @nMes) -> reporte_comercial_dter
  usp_reporte_ley15(@cGenerador, @nAnnio, @nMes)          -> reporte_ley15
  usp_detalle_facturacion_cobros(@cGenerador, @nAnnio, @nMes) -> detalle_cobros

Fuente de datos nueva:
  - dte, dter                (crudos del CND, ya importados)
  - homologacion             (transaccion -> agrupacion, se inserto igual que la vieja)
  - facturas + factura_detalle  (facturado con la app nueva)
  - facturas_historicas      (facturado del sistema viejo)
  - agentes.ley15            (factor del subsidio por distribuidor: EDEMET 0.60, ENSA 0.42)
  - ajustes_valores          (valores de ajustes del mercado; hoy solo el de 2022)

Se resuelve el Tipo 3 del Comercial a partir de las lineas de la factura nueva
(factura_detalle): "Energia en contratos", el bloque "Costo de Mercado de X"
(excluyendo la linea "DTER de X", que el viejo no incluia en Facturas.Costo),
"Descuento por pronto pago" y los otros cargos. Si el periodo no tiene facturas
nuevas, se cae a facturas_historicas con los mismos campos del viejo.
"""

from math import floor

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.models import (
    Agente,
    AjusteValor,
    Cliente,
    Contrato,
    Dte,
    Dter,
    Factura,
    FacturaDetalle,
    FacturaHistorica,
    Homologacion,
)

# ------------------------------------------------------------------ utils ---


def mes_abrev(mes: int) -> str:
    return (
        "Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic".split()[int(mes) - 1]
    )


def periodo_largo(periodo: str) -> str:
    annio = int(periodo[:4])
    mes = int(periodo[4:6])
    return f"{mes_abrev(mes)} {annio}"


def _nombre_agente(db: Session, codigo: str | None) -> str:
    if not codigo:
        return ""
    a = db.query(Agente).filter(Agente.codigo == codigo.strip().upper()).first()
    return (a.nombre or codigo) if a else codigo


def _sumar(rows: list[dict], *campos: str) -> dict:
    out = {c: 0.0 for c in campos}
    for r in rows:
        for c in campos:
            v = r.get(c) or 0
            if c in ("cantidad",) and r.get("atributo") == "Debito":
                pass
            out[c] += float(v or 0)
    return out


# ------------------------------------------------------ reporte_comercial ---


def reporte_comercial(db: Session, generador: str, periodo: str) -> dict:
    """SP usp_reporte_comercial: DTE homologado (Tipo 1/2) + facturacion (Tipo 3)."""
    generador = (generador or "").strip().upper()
    annio, mes = int(periodo[:4]), int(periodo[4:6])

    lineas: list[dict] = []

    q = (
        db.query(
            Dte.cliente.label("cliente"),
            Homologacion.agrupacion.label("agrupacion"),
            Dte.tipo.label("tipo"),
            Dte.atributo.label("atributo"),
            func.sum(Dte.cantidad).label("cantidad"),
            func.sum(Dte.valor).label("valor"),
        )
        .join(Homologacion, Homologacion.transaccion == Dte.transaccion)
        .filter(Dte.generador == generador, Dte.periodo == periodo)
        .group_by(Dte.cliente, Homologacion.agrupacion, Dte.tipo, Dte.atributo)
    )

    # Alias de clientes: en Python, para no chocar collation entre tablas (R5).
    alias_map = {
        c.codigo: (c.alias, c.nombre)
        for c in db.query(Cliente.codigo, Cliente.alias, Cliente.nombre).all()
    }

    agg: dict[tuple, dict] = {}
    for r in q.all():
        kode = (r.cliente or "").strip()
        alias_c, nombre_c = alias_map.get(kode, (None, None))
        tipo = "Tipo 1" if alias_c is None else "Tipo 2"
        alias = nombre_c if alias_c is not None else None
        sub = 1 if (r.tipo or "").strip() == "Regular" else (2 if (r.tipo or "").strip() == "Ajuste" else 3)
        key = (tipo, kode, sub, (r.agrupacion or "").strip(), (r.atributo or "").strip())
        a = agg.setdefault(key, {"cantidad": 0.0, "valor": 0.0})
        a["cantidad"] += float(r.cantidad or 0)
        a["valor"] += float(r.valor or 0)

    for (tipo, cliente, sub, agrupacion, atributo), a in sorted(
        agg.items(), key=lambda x: (x[0][0], x[0][1], x[0][2], x[0][3], x[0][4])
    ):
        lineas.append(
            {
                "tipo": tipo,
                "sub": sub,
                "generador": generador,
                "cliente": cliente,
                "alias": alias,
                "agrupacion": agrupacion,
                "atributo": atributo,
                "cantidad": round(a["cantidad"], 3),
                "valor": round(a["valor"], 2),
            }
        )

    # ---- Tipo 3: la facturacion del periodo --------------------------------
    lineas.extend(_tipo3_nueva(db, generador, annio, mes) or _tipo3_historica(db, generador, annio, mes))

    # Orden final como el SP: Tipo, Cliente, Sub, Agrupacion DESC, Atributo.
    # Agrupacion DESC: en el bloque del mercado, Debito (Compra) queda arriba.
    lineas.sort(
        key=lambda r: (
            r["tipo"],
            r.get("cliente") or "",
            r["sub"],
            r["agrupacion"] or "",
            r.get("atributo") or "",
        ),
        reverse=False,
    )
    #DESC solo en agrupacion: reordeno agrupando estables (sort estable)
    lineas.sort(key=lambda r: (r["tipo"], r.get("cliente") or "", r["sub"]))
    lineas.sort(key=lambda r: r.get("agrupacion") or "", reverse=True)
    lineas.sort(key=lambda r: r.get("atributo") or "")

    creditos = round(sum(l["valor"] for l in lineas if l["atributo"] == "Credito"), 2)
    debitos = round(sum(l["valor"] for l in lineas if l["atributo"] == "Debito"), 2)

    # Precio promedio de venta en el Mercado Ocasional (de la agrupacion Regular)
    venta = [l for l in lineas if l["agrupacion"] == "Energía en Mercado Ocasional" and l["atributo"] == "Credito" and l["sub"] == 1]
    if venta:
        cant = sum(v["cantidad"] for v in venta)
        val = sum(v["valor"] for v in venta)
        promedio = round(val / cant, 2) if cant else 0.0
    else:
        promedio = None

    return {
        "titulo": "REPORTE COMERCIAL",
        "generador": generador,
        "nombre": _nombre_agente(db, generador),
        "periodo": periodo,
        "mes": periodo_largo(periodo),
        "lineas": lineas,
        "subtotal_debito": debitos,
        "subtotal_credito": creditos,
        "total_neto": round(creditos - debitos, 2),
        "precio_promedio_venta": promedio,
    }


def _tipo3_nueva(db: Session, generador: str, annio: int, mes: int) -> list[dict] | None:
    facturas = (
        db.query(Factura)
        .options(joinedload(Factura.detalles))
        .join(Agente, Agente.id == Factura.id_agente)
        .filter(
            Agente.codigo == generador,
            Factura.periodo == f"{annio}{mes:02d}",
            Factura.estado != "anulada",
        )
        .all()
    )
    if not facturas:
        return None

    lineas: list[dict] = []

    def _fila(cliente, alias_c, agrupacion, atributo, cantidad, valor):
        lineas.append(
            {
                "tipo": "Tipo 3",
                "sub": 1,
                "generador": generador,
                "cliente": (cliente.codigo if cliente is not None else "") or (cliente and cliente.nombre) or "",
                "alias": alias_c,
                "agrupacion": agrupacion,
                "atributo": atributo,
                "cantidad": round(cantidad or 0, 3),
                "valor": round(valor or 0, 2),
            }
        )

    for f in facturas:
        cliente = f.cliente
        alias_c = (cliente.alias if cliente else None)
        nombre_c = (cliente.nombre if cliente else None)
        contrato_txt = (f.contrato.contrato if f.contrato else None) or ""
        agrup_factura = " ".join(x for x in [contrato_txt, alias_c] if x).strip()
        if not agrup_factura:
            agrup_factura = (alias_c or nombre_c or "")

        # 1) energia facturada (contratos)
        for d in f.detalles:
            if d.descripcion == "Energía en contratos" and d.es_total:
                _fila(cliente, alias_c, agrup_factura, "Credito", float(d.cantidad or 0), float(d.monto or 0))
                break

        # 2) costos de mercado mayorista (bloque "Costo de Mercado de X").
        #    Excluye la linea "DTER de X" (el viejo no la tenia en Facturas.Costo).
        costo = 0.0
        for d in f.detalles:
            if d.descripcion and d.descripcion.startswith("Costo de Mercado de"):
                continue
            if d.descripcion and d.descripcion.startswith("DTER de"):
                continue
            if d.monto is None:
                continue  # encabezados de bloque
            if d.descripcion == "Energía en contratos":
                continue
            if d.descripcion == "Descuento por pronto pago":
                _fila(cliente, alias_c, "Descuento por pronto pago", "Credito", 0.0, -abs(float(d.monto or 0)))
                continue
            if d.descripcion in ("Subtotal", "ITBMS", "TOTAL", "Total"):
                continue
            # Los cargos de CND y los otros cargos entran a "Costos Mercado Mayorista";
            # nombres propios (texto libre) quedan como en el viejo "*<texto>".
            mt = float(d.monto or 0)
            if d.descripcion in (
                "Energía en Mercado Ocasional",
                "Energía en Pérdidas de transmisión",
                "Extra costo por generación obligada",
                "Servicio Auxiliar de seguimiento de la demanda",
                "Servicios Auxiliares",
            ):
                costo += mt
                continue
            atributo = "Credito" if mt > 0 else "Debito"
            _fila(cliente, alias_c, "*" + d.descripcion.strip(), atributo, 0.0, mt)

        _fila(cliente, alias_c, "Costos Mercado Mayorista", "Credito", 0.0, costo)

    return lineas


def _tipo3_historica(db: Session, generador: str, annio: int, mes: int) -> list[dict]:
    filas = (
        db.query(FacturaHistorica)
        .filter(
            func.trim(FacturaHistorica.generador) == generador,
            FacturaHistorica.annio == annio,
            FacturaHistorica.mes == mes,
        )
        .all()
    )
    lineas: list[dict] = []
    for f in filas:
        cliente = (f.cliente or "").strip()
        info = db.query(Cliente).filter(func.trim(Cliente.codigo) == cliente).first()
        alias_c = (info.alias if info else None)
        nombre_c = (info.nombre if info else None) or cliente
        contrato_txt = (f.contrato or "").strip()
        agrup_factura = " ".join(x for x in [contrato_txt, alias_c] if x).strip() or nombre_c

        def fila(_agrupacion, _atributo, _cantidad, _valor, _alias=alias_c, _cliente=cliente):
            lineas.append(
                {
                    "tipo": "Tipo 3",
                    "sub": 1,
                    "generador": generador,
                    "cliente": _cliente,
                    "alias": _alias,
                    "agrupacion": _agrupacion,
                    "atributo": _atributo,
                    "cantidad": round(_cantidad or 0, 3),
                    "valor": round(_valor or 0, 2),
                }
            )

        fila(agrup_factura, "Credito", f.consumo, f.valor)
        fila("Costos Mercado Mayorista", "Credito", 0.0, f.costo)
        if f.descuento and float(f.descuento) > 0:
            fila(agrup_factura, "Credito", 0.0, float(f.descuento) * -1)
        if f.montootroscargos and float(f.montootroscargos) != 0:
            txt = ((f.textootroscargos or "").strip() or "Otros cargos")
            atributo = "Credito" if float(f.montootroscargos) > 0 else "Debito"
            fila("*" + txt, atributo, 0.0, float(f.montootroscargos))
    return lineas


# ------------------------------------------------- reporte_comercial_DTER ---


def reporte_comercial_dter(db: Session, generador: str, annio: int, mes: int) -> dict:
    """SP usp_reporte_comercial_DTER (DTER homologado por agregacion)."""
    generador = (generador or "").strip().upper()
    q = (
        db.query(
            Homologacion.agrupacion.label("agrupacion"),
            Dter.generador.label("generador"),
            Dter.cliente.label("cliente"),
            Dter.atributo.label("atributo"),
            func.sum(Dter.valor).label("valor"),
        )
        .join(Homologacion, Homologacion.transaccion == Dter.transaccion)
        .filter(Dter.generador == generador, Dter.annio == annio, Dter.mes == mes)
        .group_by(Homologacion.agrupacion, Dter.generador, Dter.cliente, Dter.atributo)
    )
    lineas = []
    for r in q.all():
        lineas.append(
            {
                "tipo": 0 if r.cliente == generador else 1,
                "agrupacion": (r.agrupacion or "").strip(),
                "generador": (r.generador or "").strip(),
                "agente": _nombre_agente(db, r.generador),
                "cliente": (r.cliente or "").strip(),
                "atributo": r.atributo,
                "valor": round(float(r.valor or 0), 2),
            }
        )
    # Orden del SP: Tipo asc, Nombre asc, Cliente desc
    lineas.sort(key=lambda x: (x["tipo"], x["agente"], x["cliente"]), reverse=False)
    lineas.sort(key=lambda x: x["cliente"], reverse=True)
    lineas.sort(key=lambda x: (x["tipo"], x["agente"]))

    creditos = round(sum(l["valor"] for l in lineas if l["atributo"] == "Credito"), 2)
    debitos = round(sum(l["valor"] for l in lineas if l["atributo"] == "Debito"), 2)
    return {
        "titulo": "REPORTE COMERCIAL DTER",
        "generador": generador,
        "nombre": _nombre_agente(db, generador),
        "periodo": f"{annio}{mes:02d}",
        "mes": f"{mes_abrev(mes)} {annio}",
        "lineas": lineas,
        "subtotal_debito": debitos,
        "subtotal_credito": creditos,
        "total_neto": round(creditos - debitos, 2),
    }


# -------------------------------------------------------- reporte_ley15 ----


def reporte_ley15(db: Session, generador: str, annio: int, mes: int, solo_con_factor: bool = True) -> dict:
    """SP usp_reporte_ley15: facturas de clientes de distribuidores con factor Ley 15.

    Importe = Valor * ley15 / 100 (viejo: EDEMET 0.60 -> 73.92 de 12,320.20).
    """
    generador = (generador or "").strip().upper()
    periodo = f"{annio}{mes:02d}"
    filas: list[tuple] = []

    # Facturas nuevas de la app
    q_new = (
        db.query(Factura)
        .join(Agente, Agente.id == Factura.id_agente)
        .filter(Agente.codigo == generador, Factura.periodo == periodo, Factura.estado != "anulada")
    )


    if db.query(q_new.subquery()).count() > 0:
        for f in q_new.all():
            c = f.cliente
            d = c.distribuidor if c else None
            filas.append(
                {
                    "contrato": (f.contrato.contrato if f.contrato else "") or "",
                    "cliente": (c.alias if c and c.alias else (c.nombre if c else "")),
                    "distribuidor": (d.alias if d and d.alias else (d.nombre if d else "")),
                    "nis": (c.nis if c else ""),
                    "ley15": float(d.ley15 or 0) if d else 0.0,
                    "valor": round(float(f.subtotal or 0), 2),
                }
            )
    else:
        hist = (
            db.query(FacturaHistorica)
            .filter(
                func.trim(FacturaHistorica.generador) == generador,
                FacturaHistorica.annio == annio,
                FacturaHistorica.mes == mes,
            )
            .all()
        )
        for f in hist:
            c = (
                db.query(Cliente)
                .filter(func.trim(Cliente.codigo) == (f.cliente or "").strip())
                .first()
            )
            d = c.distribuidor if c else None
            filas.append(
                {
                    "contrato": (f.contrato or "").strip(),
                    "cliente": (c.alias if c and c.alias else (c.nombre if c else "")) or f.cliente,
                    "distribuidor": (d.alias if d and d.alias else (d.nombre if d else "")) if d else "",
                    "nis": (c.nis if c else ""),
                    "ley15": float(d.ley15 or 0) if d else 0.0,
                    "valor": round(float(f.valor or 0), 2),
                }
            )

    if solo_con_factor:
        filas = [x for x in filas if x["ley15"] and float(x["ley15"]) > 0]

    lineas = []
    for x in filas:
        factor = float(x["ley15"] or 0)
        lineas.append(
            {
                "contrato": x["contrato"],
                "cliente": x["cliente"],
                "distribuidor": x["distribuidor"],
                "nis": x["nis"],
                "ley15": factor,
                "valor": x["valor"],
                "importe": round(x["valor"] * factor / 100.0, 2),
            }
        )
    lineas.sort(key=lambda r: (r["distribuidor"], r["cliente"]))

    total_importe = round(sum(r["importe"] for r in lineas), 2)
    return {
        "titulo": "REPORTE SUBSIDIO LEY 15",
        "generador": generador,
        "nombre": _nombre_agente(db, generador),
        "periodo": periodo,
        "mes": f"{mes_abrev(mes)} {annio}",
        "lineas": lineas,
        "total_importe": total_importe,
    }


# ------------------------------------------------- detalle_facturacion_cobros


def detalle_cobros(db: Session, generador: str, annio: int, mes: int) -> dict:
    """SP usp_detalle_facturacion_cobros: DTE agrupado ROLLUP (Agente, Transaccion)."""
    generador = (generador or "").strip().upper()
    rows = (
        db.query(
            Dte.codigo_agente.label("agente"),
            Dte.transaccion.label("transaccion"),
            Dte.atributo.label("atributo"),
            Dte.cantidad.label("cantidad"),
            Dte.valor.label("valor"),
        )
        .filter(Dte.generador == generador, Dte.annio == annio, Dte.mes == mes)
        .all()
    )

    agg: dict[tuple[str | None, str | None], dict] = {}
    for r in rows:
        key = ((r.agente or "").strip() if r.agente else None, (r.transaccion or "").strip() if r.transaccion else None)
        a = agg.setdefault(key, {"cantidad": 0.0, "creditos": 0.0, "debitos": 0.0})
        a["cantidad"] += float(r.cantidad or 0)
        if (r.atributo or "").strip() == "Credito":
            a["creditos"] += float(r.valor or 0)
        elif (r.atributo or "").strip() == "Debito":
            a["debitos"] += float(r.valor or 0)

    lineas = [
        {
            "agente": None,
            "transaccion": None,
            "cantidad": round(sum(v["cantidad"] for v in agg.values()), 3),
            "creditos": round(sum(v["creditos"] for v in agg.values()), 2),
            "debitos": round(sum(v["debitos"] for v in agg.values()), 2),
        }
    ]
    for agente in sorted({k[0] for k in agg if k[0] is not None}):
        grupo = [a for k, a in agg.items() if k[0] == agente]
        lineas.append(
            {
                "agente": agente,
                "transaccion": None,
                "cantidad": round(sum(g["cantidad"] for g in grupo), 3),
                "creditos": round(sum(g["creditos"] for g in grupo), 2),
                "debitos": round(sum(g["debitos"] for g in grupo), 2),
            }
        )
        for tr in sorted({k[1] for k in agg if k[0] == agente and k[1] is not None}):
            a = agg[(agente, tr)]
            lineas.append(
                {
                    "agente": agente,
                    "transaccion": tr,
                    "cantidad": round(a["cantidad"], 3),
                    "creditos": round(a["creditos"], 2),
                    "debitos": round(a["debitos"], 2),
                }
            )

    total = lineas[0]
    return {
        "titulo": "DETALLES DE FACTURACIÓN Y COBROS",
        "generador": generador,
        "nombre": _nombre_agente(db, generador),
        "periodo": f"{annio}{mes:02d}",
        "mes": f"{mes_abrev(mes)} {annio}",
        "lineas": lineas,
        "total_creditos": total["creditos"],
        "total_debitos": total["debitos"],
        "total_cantidad": total["cantidad"],
    }


# ------------------------------------------------------------- HTML nova ---


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
  .top-rule { height:3px; margin-bottom:7mm; background:linear-gradient(90deg,#e54b48 0 50%,#5267df 50% 100%); }
  .report-head { text-align:center; margin:2mm 0 5mm; }
  .report-head .empresa { color:var(--blue); font-family:Georgia,"Times New Roman",serif; font-size:17pt; line-height:1.15; }
  .report-head .nombre { font-size:15pt; font-weight:800; letter-spacing:.3px; }
  .report-head .periodo { font-size:12pt; color:var(--muted); }
  table { width:100%; border-collapse:collapse; table-layout:fixed; font-size:9pt; margin-top:4mm; }
  thead { display:table-header-group; }
  th { background:#dce5f1; border:1px solid #26313d; padding:6px 6px; text-align:center; font-size:8.5pt;
       overflow-wrap:anywhere; word-break:break-word; white-space:normal; }
  td { border:1px solid #26313d; padding:6px 6px; vertical-align:top;
       overflow-wrap:anywhere; word-break:break-word; white-space:normal; }
  tbody tr { break-inside:avoid; page-break-inside:avoid; }
  .num { text-align:right; white-space:nowrap; font-variant-numeric:tabular-nums; }
  subtotalaux {}
  tr.subtot td { background:#f5f7fa; font-weight:700; }
  tr.total td { border-top:2px solid #26313d; background:#edf2f8; font-size:11pt; font-weight:800; text-align:right; }
  tr.total td.num { text-align:right; }
  .nota { margin-top:5mm; color:var(--muted); font-size:8pt; }
  .destacado { margin-top:5mm; padding:7px 10px; border:1px solid var(--blue); background:#fff; text-align:center; font-size:11pt; }
  .footer { margin-top:10mm; padding-top:3mm; border-top:1px solid #c7ced6; color:var(--muted); font-size:8pt; display:flex; justify-content:space-between; gap:8px; }
  @page { size:A4; margin:10mm 12mm 12mm; }
  @media print {
    html,body { background:#fff; } body { font-size:9pt; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
    .toolbar { display:none !important; }
    .invoice { width:auto; min-height:0; margin:0; padding:0; box-shadow:none; border:0; }
    .top-rule { margin-top:0; }
    .report-head { break-inside:avoid; page-break-inside:avoid; }
    table { break-inside:auto; page-break-inside:auto; }
    tr { break-inside:avoid; page-break-inside:avoid; }
    tr.total, tr.subtot, .destacado, .nota, .footer { break-inside:avoid; page-break-inside:avoid; }
  }
""".strip()


def _fmt(n: float | None, dec: int = 2) -> str:
    if n is None:
        return ""
    return f"{float(n):,.{dec}f}"


def render_html(datos: dict) -> str:
    """HTML imprimible generico para cualquiera de los 4 reportes."""
    titulo = datos.get("titulo", "Reporte")
    nombre = datos.get("nombre") or datos.get("generador") or ""
    mes = datos.get("mes") or ""
    lineas: list[dict] = datos.get("lineas", [])

    if titulo.upper().startswith("REPORTE COMERCIAL") and not titulo.upper().endswith("DTER"):
        cabezas = ["CANTIDAD", "UNIDAD", "PRECIOS", "DESCRIPCIÓN", "DÉBITO", "CRÉDITO"]
        filas_html = []
        for l in lineas:
            es_ajuste = l.get("sub") in (2, 3)
            filas_html.append(
                "<tr>"
                f"<td class='num'>{_fmt(l['cantidad'],3) if l['cantidad'] else ''}</td>"
                "<td class='num'>MWh</td>"
                "<td></td>"
                f"<td>{l['agrupacion'] or ''}{' (ajuste)' if es_ajuste else ''}</td>"
                f"<td class='num'>{_fmt(l['valor']) if l['atributo']=='Debito' else ''}</td>"
                f"<td class='num'>{_fmt(l['valor']) if l['atributo']=='Credito' else ''}</td>"
                "</tr>"
            )
        filas_html.append(
            f"<tr class='subtot'><td colspan=4></td><td class='num'>{_fmt(datos.get('subtotal_debito'))}</td>"
            f"<td class='num'>{_fmt(datos.get('subtotal_credito'))}</td></tr>"
        )
        filas_html.append(
            f"<tr class='total'><td colspan=4 style='text-align:right'>TOTAL NETO</td>"
            f"<td colspan=2 class='num'>{_fmt(datos.get('total_neto'))}</td></tr>"
        )
        extra = ""
        p = datos.get("precio_promedio_venta")
        if p is not None:
            extra += f"<div class='destacado'>Precio Promedio de Venta Mercado Ocasional: <b>{_fmt(p)}</b> &nbsp;/&nbsp; {_fmt(-p)} $/MWh</div>"

    elif titulo.upper().endswith("DTER"):
        cabezas = ["AGRUPACIÓN", "AGENTE", "CLIENTE", "ATRIBUTO", "VALOR"]
        filas_html = [
            "<tr>"
            f"<td>{l['agrupacion']}</td><td>{l['agente']}</td><td>{l['cliente']}</td>"
            f"<td>{l['atributo']}</td><td class='num'>{_fmt(l['valor'])}</td></tr>"
            for l in lineas
        ]
        filas_html.append(
            f"<tr class='subtot'><td colspan=3></td><td>Subtotal Débito</td><td class='num'>{_fmt(datos.get('subtotal_debito'))}</td></tr>"
        )
        filas_html.append(
            f"<tr class='subtot'><td colspan=3></td><td>Subtotal Crédito</td><td class='num'>{_fmt(datos.get('subtotal_credito'))}</td></tr>"
        )
        filas_html.append(
            f"<tr class='total'><td colspan=3></td><td>TOTAL NETO</td><td class='num'>{_fmt(datos.get('total_neto'))}</td></tr>"
        )
        extra = ""

    elif "LEY 15" in titulo.upper():
        cabezas = ["DISTRIBUIDOR", "CONTRATO", "CLIENTE", "NIS", "FACTOR", "VALOR", "IMPORTE"]
        filas_html = [
            "<tr>"
            f"<td>{l['distribuidor']}</td><td>{l['contrato']}</td><td>{l['cliente']}</td>"
            f"<td class='num'>{l['nis']}</td><td class='num'>{_fmt(l['ley15'])}</td>"
            f"<td class='num'>{_fmt(l['valor'])}</td><td class='num'>{_fmt(l['importe'])}</td></tr>"
            for l in lineas
        ]
        filas_html.append(
            f"<tr class='total'><td colspan=6 style='text-align:right'>TOTAL IMPORTE</td><td class='num'>{_fmt(datos.get('total_importe'))}</td></tr>"
        )
        extra = ""

    else:  # Detalles de Facturación y Cobros
        cabezas = ["AGENTE", "DESCRIPCIÓN", "CANTIDAD", "CRÉDITOS", "DÉBITOS"]
        filas_html = []
        for l in lineas:
            ag = l.get("agente") or ""
            tr = l.get("transaccion")
            filas_html.append(
                "<tr class='%s'>"
                f"<td>{'' if tr else ag}</td>"
                f"<td>{tr or 'TOTAL'}</td>"
                f"<td class='num'>{_fmt(l['cantidad'],3)}</td>"
                f"<td class='num'>{_fmt(l['creditos'])}</td>"
                f"<td class='num'>{_fmt(l['debitos'])}</td>"
                "</tr>" % ("subtot" if not tr else "")
            )
        filas_html.append(
            f"<tr class='total'><td colspan=2 style='text-align:right'>TOTALES</td>"
            f"<td class='num'>{_fmt(datos.get('total_cantidad'),3)}</td>"
            f"<td class='num'>{_fmt(datos.get('total_creditos'))}</td>"
            f"<td class='num'>{_fmt(datos.get('total_debitos'))}</td></tr>"
        )
        extra = ""

    thead = "<thead><tr>" + "".join(f"<th>{c}</th>" for c in cabezas) + "</tr></thead>"
    filas = "".join(filas_html)

    return f"""<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>{titulo} - {nombre}</title>
<style>{_CSS}</style></head><body>
<div class="toolbar">
  <span class="hint">{titulo} · {nombre} · {mes}</span>
  <button onclick="window.print()">Imprimir</button>
</div>
<main class="invoice">
<div class="top-rule"></div>
<div class="report-head">
  <div class="empresa">{nombre}</div>
  <div class="nombre">{titulo}</div>
  <div class="periodo">{mes}</div>
</div>
<table>{thead}<tbody>{filas}</tbody></table>
{extra}
<div class="footer"><span>Generado por CEK</span><span>Reporte comercial · {mes}</span></div>
</main></body></html>"""
