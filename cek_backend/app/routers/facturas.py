# -*- coding: utf-8 -*-
"""Facturas: generacion mensual por cliente + vista HTML imprimible."""
from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core import acceso
from app.core.database import get_db
from app.core.deps import get_current_user, require_roles
from app.models import Agente, Cliente, Contrato, Factura, FacturaDetalle, Precio, Usuario
from app.schemas import FacturaGenerar, FacturaGenerarLote, FacturaOut, FacturaUpdate
from app.services import consumo as svc_consumo
from app.services import estado as svc_estado
from app.services import facturas as svc

router = APIRouter(prefix="/facturas", tags=["Facturas"])

MES_CORTO = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
admin = require_roles("admin", "operador")


def _precio_vigente(db: Session, id_contrato: int | None, periodo: str) -> tuple[float | None, str | None]:
    """Tarifa/precio vigente del contrato (delegado al servicio compartido)."""
    return svc.precio_vigente(db, id_contrato, periodo)


def _siguiente_numero(db: Session, periodo: str) -> str:
    n = db.query(func.count(Factura.id)).filter(Factura.periodo == periodo).scalar() or 0
    while True:
        n += 1
        numero = f"FAC-{periodo}-{n:04d}"
        if not db.query(Factura.id).filter(Factura.numero == numero).first():
            return numero


def _out(f: Factura) -> dict:
    return {
        "id": f.id,
        "numero": f.numero,
        "id_agente": f.id_agente,
        "id_cliente": f.id_cliente,
        "id_contrato": f.id_contrato,
        "periodo": f.periodo,
        "tarifa": f.tarifa,
        "moneda": f.moneda,
        "precio_kwh": float(f.precio_kwh) if f.precio_kwh is not None else None,
        "consumo_mwh": float(f.consumo_mwh) if f.consumo_mwh is not None else None,
        "dias_lectura": f.dias_lectura,
        "subtotal": float(f.subtotal or 0),
        "itbms_pct": float(f.itbms_pct or 0),
        "itbms": float(f.itbms or 0),
        "total": float(f.total or 0),
        "estado": f.estado,
        "fecha_emision": f.fecha_emision,
        "fecha_vencimiento": f.fecha_vencimiento,
        "observaciones": f.observaciones,
        "graficas": f.graficas,
        "creado": f.creado,
        "cliente_nombre": f.cliente.nombre if f.cliente else None,
        "agente_nombre": f.agente.nombre if f.agente else None,
        "detalles": [
            {
                "id": d.id,
                "orden": d.orden,
                "categoria": d.categoria,
                "descripcion": d.descripcion,
                "consumo": d.consumo,
                "cantidad": float(d.cantidad) if d.cantidad is not None else None,
                "unidad": d.unidad,
                "monto": float(d.monto) if d.monto is not None else None,
                "es_total": d.es_total,
            }
            for d in f.detalles
        ],
    }


def _serie_consumo(db: Session, id_cliente: int) -> list[dict]:
    """Serie de consumo (MWh) del cliente, mes a mes.

    Fuente oficial: la tabla `mediciones` (equivale a fn_historialconsumo del
    sistema viejo). Se completa con las facturas historicas para los meses sin
    medicion cargada. La medicion manda cuando existe para el mismo periodo.
    """
    por_periodo: dict[str, float] = {}
    cl = db.get(Cliente, id_cliente)
    if cl and cl.codigo:
        for per, mwh in svc.historial_mediciones(db, cl.codigo).items():
            por_periodo[per] = mwh
    filas = (
        db.query(Factura.periodo, Factura.consumo_mwh)
        .filter(Factura.id_cliente == id_cliente, Factura.estado != "anulada")
        .order_by(Factura.periodo)
        .all()
    )
    for periodo, mwh in filas:
        if periodo not in por_periodo:
            por_periodo[periodo] = float(mwh) if mwh else 0.0
    serie = []
    for periodo in sorted(por_periodo):
        try:
            etiqueta = f"{MES_CORTO[int(periodo[4:6])]} {periodo[2:4]}"
        except (ValueError, IndexError):
            etiqueta = periodo
        serie.append({"periodo": periodo, "etiqueta": etiqueta, "mwh": round(por_periodo[periodo], 6)})
    return serie


def _historico_cliente(db: Session, id_cliente: int, periodo: str, limite: int = 4) -> list[dict]:
    """Ultimos meses de consumo (MWh) del cliente para la columna "Consumos".

    Datos reales: tabla `mediciones` (fn_historialconsumo) + facturas historicas.
    Solo meses hasta el periodo facturado (Fecha <= @Corte). Etiqueta "Jul-2026".
    """
    por_periodo = {s["periodo"]: float(s["mwh"]) for s in _serie_consumo(db, id_cliente)}
    if periodo:
        # fn_historialconsumo: Fecha <= @Corte (no muestra meses posteriores)
        por_periodo = {p: v for p, v in por_periodo.items() if p <= periodo}
    out: list[dict] = []
    for per in sorted(por_periodo, reverse=True)[:limite]:
        try:
            etiqueta = f"{MES_CORTO[int(per[4:6])]}-{per[:4]}"
        except (ValueError, IndexError):
            etiqueta = per
        out.append({"etiqueta": etiqueta, "mwh": svc.truncar(por_periodo[per], 3)})
    return out


def _payload_grafica(db: Session, f: Factura, tipo: str = "diario") -> dict:
    """Datos reales para la grafica de consumo (sin inventar valores).

    tipo: 'diario' | 'historico' | 'costo'
    """
    tipo = (tipo or "diario").strip().lower()
    if tipo not in ("diario", "historico", "costo"):
        tipo = "diario"
    cl = f.cliente
    nombre = cl.nombre if cl else ""
    codigo = (cl.codigo if cl else "") or ""
    per = f.periodo
    rango = f"{svc_consumo.nombre_mes(per)} {per[:4]}".strip() or per

    base = {"cliente": nombre, "codigo": codigo, "periodo": per, "rango": rango}

    if tipo == "diario":
        datos = svc_consumo.consumo_diario(db, cliente=codigo, periodo=per)
        if datos:
            return {
                **base,
                "tipo": "diario",
                "titulo": "Consumo diario",
                "subtitulo": f"{nombre} · {rango}",
                "unidad": "kWh",
                "unidad_derecha": None,
                "eje_x": [str(d["dia"]) for d in datos],
                "series": [{"nombre": "Consumo (kWh)", "valores": [d["kwh"] for d in datos]}],
                "linea": None,
            }
        datos = svc_consumo.consumo_diario(db, agente=codigo, periodo=per)
        if datos:
            return {
                **base,
                "tipo": "diario",
                "titulo": "Consumo diario",
                "subtitulo": f"{nombre} · {rango}",
                "unidad": "kWh",
                "unidad_derecha": None,
                "eje_x": [str(d["dia"]) for d in datos],
                "series": [{"nombre": "Consumo (kWh)", "valores": [d["kwh"] for d in datos]}],
                "linea": None,
            }
        tipo = "historico"

    datos = svc_consumo.consumo_mensual_mediciones(db, codigo, f.id_cliente, hasta=per)
    etiquetas = [d["etiqueta"] for d in datos]
    valores = [d["kwh"] for d in datos]

    if tipo == "costo":
        # según especificación: puntos de "Promedio CMS" ($) por días del mes facturado
        diario = svc_consumo.consumo_diario(db, cliente=codigo, periodo=per)
        if not diario:
            diario = svc_consumo.consumo_diario(db, agente=codigo, periodo=per)
        cms = [d.get("cms_prom") for d in diario] if diario else []
        # La vista diaria de "puntos" solo se usa si hay al menos un CMS real.
        # Si no hay CMS (la liquidacion del mes aun no ha salido) se muestra el
        # consumo diario del propio mes facturado; nunca meses anteriores.
        if diario and any(v is not None for v in cms):
            # El CMS de la liquidacion CND viene en B/./MWh; se expresa en
            # B/./kWh (dividido por 1000) para igualar la unidad de la factura.
            valores = [
                (float(v) / 1000.0) if v is not None else None
                for v in cms
            ]
            return {
                **base,
                "tipo": "costo",
                "modo": "puntos",
                "titulo": "Generación y costo promedio",
                "subtitulo": f"{nombre} · Promedio CMS (B/./kWh)",
                "unidad": "B/./kWh",
                "unidad_derecha": None,
                "eje_x": [str(d["dia"]) for d in diario],
                "series": [{"nombre": "Promedio CMS (B/./kWh)", "valores": valores}],
                "linea": None,
            }
        # Sin CMS del mes facturado (la liquidacion CND aun no ha salido; suele
        # publicarse ~el dia 6 del mes siguiente): se muestran las graficas
        # diarias del mes en curso mientras se genera la factura, NUNCA meses
        # anteriores.
        if diario:
            return {
                **base,
                "tipo": "costo",
                "modo": "puntos",
                "titulo": "Generación y costo promedio",
                "subtitulo": f"{nombre} · consumo diario (CMS pendiente)",
                "unidad": "kWh",
                "unidad_derecha": None,
                "eje_x": [str(d["dia"]) for d in diario],
                "series": [{
                    "nombre": "Consumo (kWh)",
                    "valores": [d["kwh"] for d in diario],
                }],
                "linea": None,
            }
        # Ultimo recurso (sin dato diario ni CMS): consumo mensual del cliente.
        return {
            **base,
            "tipo": "costo",
            "titulo": "Generación y costo promedio",
            "subtitulo": f"{nombre} · consumo mensual y costo promedio",
            "unidad": "kWh",
            "unidad_derecha": "B/./kWh",
            "eje_x": etiquetas,
            "series": [{"nombre": "Consumo (kWh)", "valores": valores}],
            "linea": {
                "nombre": "Costo promedio (B/./kWh)",
                "valores": [d.get("costo_kwh") for d in datos],
            },
        }

    return {
        **base,
        "tipo": "historico",
        "titulo": "Historial de consumo",
        "subtitulo": f"{nombre} · consumo mensual",
        "unidad": "kWh",
        "unidad_derecha": None,
        "eje_x": etiquetas,
        "series": [{"nombre": "Consumo (kWh)", "valores": valores}],
        "linea": None,
    }


@router.get("", response_model=list[FacturaOut])
def listar(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
    id_cliente: int | None = None,
    id_agente: int | None = None,
    periodo: str | None = None,
    estado: str | None = None,
):
    q = db.query(Factura)
    permitidos = acceso.clientes_permitidos(db, usuario)
    if permitidos is not None:
        q = q.filter(Factura.id_cliente.in_(permitidos))
    if id_cliente is not None:
        q = q.filter(Factura.id_cliente == id_cliente)
    if id_agente is not None:
        q = q.filter(Factura.id_agente == id_agente)
    if periodo:
        q = q.filter(Factura.periodo == periodo)
    if estado:
        q = q.filter(Factura.estado == estado)
    return [_out(f) for f in q.order_by(Factura.periodo.desc(), Factura.id.desc()).all()]


@router.get("/estado")
def estado_periodo(
    periodo: str,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Preparacion de la facturacion de un periodo (AAAAMM).

    Indica, por agente, cuantos de sus clientes ya tienen la liquidacion del
    mes (medicion y/o cargos DTE) y cuantos siguen pendientes, para saber
    cuando ya se puede emitir la factura.  Ej: "de 15 agentes, 12 listos".
    """
    if len(periodo) != 6 or not periodo.isdigit():
        raise HTTPException(400, "El periodo debe ser AAAAMM")
    permitidos = acceso.clientes_permitidos(db, usuario)
    ags = acceso.agentes_permitidos(db, usuario)
    # Un usuario con clientes sueltos (sin agentes asignados) debe ver los
    # agentes de esos clientes: se deja el filtro de agentes en None y los
    # clientes quedan acotados por `permitidos`.
    if ags is not None and not ags:
        ags = None
    return svc_estado.estado_periodo(
        db, periodo, id_agentes=ags, clientes_permitidos=permitidos
    )


@router.post("/generar", response_model=FacturaOut, status_code=201)
def generar(data: FacturaGenerar, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    cliente = db.get(Cliente, data.id_cliente)
    if not cliente:
        raise HTTPException(404, "Cliente no encontrado")
    if len(data.periodo) != 6 or not data.periodo.isdigit():
        raise HTTPException(400, "El periodo debe ser AAAAMM")

    if data.id_contrato:
        contrato = db.get(Contrato, data.id_contrato)
    else:
        q_contratos = db.query(Contrato).filter(Contrato.id_cliente == cliente.id)
        # Si se indico el agente emisor, preferir su contrato con el cliente.
        contrato = None
        if data.id_agente:
            contrato = (
                q_contratos.filter(Contrato.id_agente == data.id_agente)
                .order_by(Contrato.id)
                .first()
            )
        contrato = contrato or q_contratos.order_by(Contrato.id).first()
    id_agente = data.id_agente or (contrato.id_agente if contrato else None)
    if not id_agente:
        raise HTTPException(400, "Indique el agente emisor (o cree un contrato para el cliente)")
    agente = db.get(Agente, id_agente)
    if not agente:
        raise HTTPException(404, "Agente no encontrado")

    # Precio/tarifa: lo indicado manda; si no, el vigente del contrato (tabla Precios)
    precio_vig, tarifa_vig = _precio_vigente(db, contrato.id if contrato else None, data.periodo)
    precio_kwh = data.precio_kwh if data.precio_kwh is not None else (
        precio_vig if precio_vig is not None else 0.0775)
    tarifa = data.tarifa or tarifa_vig or "1"

    consumo = data.consumo_mwh
    if consumo is None:
        # 1) tabla `mediciones` (fuente oficial del consumo medido) para el periodo
        med = svc.consumo_desde_mediciones(db, cliente.codigo, data.periodo)
        if med is None:
            # 1b) fn_historialconsumo: si el mes aun no tiene medicion cargada,
            #     se toma la medicion mas reciente hasta el corte (Fecha <= @Corte)
            hist = svc.historial_mediciones(db, cliente.codigo, hasta=data.periodo, limite=1)
            med = next(iter(hist.values()), None) if hist else None
        if med is not None:
            consumo = med
        else:
            # 2) heredar el ultimo consumo facturado al cliente, si existe
            ult = (
                db.query(Factura.consumo_mwh)
                .filter(Factura.id_cliente == cliente.id, Factura.consumo_mwh.isnot(None))
                .order_by(Factura.periodo.desc())
                .first()
            )
            consumo = float(ult[0]) if ult and ult[0] is not None else 0.0

    cargos: dict = {}
    dter_monto = data.dter_monto
    dter_periodo = data.dter_periodo
    if data.incluir_dte:
        # 1) tabla `dte` (equivalente a fn_costos / fn_CostoMercado del sistema viejo)
        cargos = svc.cargos_desde_dte(db, cliente.codigo, data.periodo)
        # 2) respaldo: si la tabla esta vacia, leer el crudo DTE Tabular en disco
        if not cargos:
            cargos = svc.cargar_cargos_dte(cliente.codigo, data.periodo)
        # DTER del mes anterior (fn_DTER_Mes) si no lo indicaron a mano
        if dter_monto is None:
            dp = dter_periodo or svc.periodo_anterior(data.periodo)
            monto_dter = svc.dter_desde_tabla(db, cliente.codigo, dp)
            if abs(monto_dter) > 0.004:
                dter_monto, dter_periodo = monto_dter, dp
    lineas = svc.lineas_factura(
        cargos, float(consumo), float(precio_kwh), data.incluir_dte,
        periodo=data.periodo, dter_monto=dter_monto, dter_periodo=dter_periodo,
        descuento=data.descuento,
        otros_cargos=[c.model_dump() for c in (data.otros_cargos or [])],
    )
    subtotal, itbms, total = svc.totales(lineas, float(data.itbms_pct))

    emision = datetime.utcnow()
    vencimiento = emision + timedelta(days=30)
    factura = Factura(
        numero=_siguiente_numero(db, data.periodo),
        id_agente=id_agente,
        id_cliente=cliente.id,
        id_contrato=contrato.id if contrato else None,
        periodo=data.periodo,
        tarifa=tarifa,
        moneda="B/.",
        precio_kwh=precio_kwh,
        consumo_mwh=consumo,
        dias_lectura=data.dias_lectura,
        subtotal=subtotal,
        itbms_pct=data.itbms_pct,
        itbms=itbms,
        total=total,
        estado="emitida",
        fecha_emision=emision,
        fecha_vencimiento=vencimiento,
        observaciones=data.observaciones,
        graficas=(data.graficas if data.graficas else "diario"),
    )
    db.add(factura)
    db.flush()
    for ln in lineas:
        db.add(FacturaDetalle(id_factura=factura.id, **ln))
    db.commit()
    db.refresh(factura)
    return _out(factura)


@router.post("/generar-lote")
def generar_lote(
    data: FacturaGenerarLote,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin),
):
    """Emite la factura del periodo para los clientes de un agente.

    Usa exactamente la misma logica que /generar (precio del contrato, consumo de
    `mediciones`, cargos del DTE, numeracion, etc.). Se le pasa el agente y se
    facturan sus clientes (todos, o el subconjunto indicado en `id_clientes`).
    Devuelve las facturas creadas y, por separado, las omitidas (ya existian)
    y los errores, para poder mostrarlos en pantalla.
    """
    if len(data.periodo) != 6 or not data.periodo.isdigit():
        raise HTTPException(400, "El periodo debe ser AAAAMM")

    creadas: list[dict] = []
    omitidas: list[dict] = []
    errores: list[dict] = []

    # Universo de clientes: los del agente indicado.
    if data.id_agente is not None:
        if not db.get(Agente, data.id_agente):
            raise HTTPException(404, "Agente no encontrado")
        universo = {c.id: c for c in svc.clientes_del_agente(db, data.id_agente)}
        if data.id_clientes:
            # Subconjunto: solo se facturan los que realmente pertenecen al agente.
            for cid in data.id_clientes:
                if cid not in universo:
                    errores.append({"id_cliente": cid, "cliente": f"Cliente {cid}",
                                    "motivo": "No pertenece al agente seleccionado"})
            ids = [cid for cid in data.id_clientes if cid in universo]
        else:
            ids = list(universo)
    else:
        # Compatibilidad: lista explicita de clientes (sin filtro de agente).
        universo = {}
        ids = list(data.id_clientes)

    if not ids:
        raise HTTPException(400, "El agente no tiene clientes para facturar")

    for cid in ids:
        cl = universo.get(cid) or db.get(Cliente, cid)
        nombre = cl.nombre if cl else f"Cliente {cid}"
        if data.omitir_existentes:
            existente = (
                db.query(Factura)
                .filter(Factura.id_cliente == cid,
                        Factura.periodo == data.periodo,
                        Factura.estado != "anulada")
                .order_by(Factura.id)
                .first()
            )
            if existente:
                omitidas.append({"id_cliente": cid, "cliente": nombre,
                                 "motivo": f"Ya existe {existente.numero}"})
                continue
        try:
            factura = generar(
                FacturaGenerar(
                    id_cliente=cid,
                    periodo=data.periodo,
                    id_agente=data.id_agente,
                    incluir_dte=data.incluir_dte,
                    itbms_pct=data.itbms_pct,
                    dias_lectura=data.dias_lectura,
                    graficas=data.graficas or "diario",
                ),
                db,
                usuario,
            )
            creadas.append(factura)
        except HTTPException as exc:
            db.rollback()
            errores.append({"id_cliente": cid, "cliente": nombre, "motivo": str(exc.detail)})
        except Exception as exc:  # noqa: BLE001 - se informa por cliente, no se aborta el lote
            db.rollback()
            errores.append({"id_cliente": cid, "cliente": nombre, "motivo": str(exc)})

    return {"periodo": data.periodo, "agente": data.id_agente, "creadas": creadas,
            "omitidas": omitidas, "errores": errores}


@router.get("/{id}", response_model=FacturaOut)
def obtener(id: int, db: Session = Depends(get_db), usuario: Usuario = Depends(get_current_user)):
    f = db.get(Factura, id)
    if not f:
        raise HTTPException(404, "Factura no encontrada")
    if not acceso.puede_ver_cliente(db, usuario, f.id_cliente):
        raise HTTPException(403, "Sin acceso a esta factura")
    return _out(f)


@router.put("/{id}", response_model=FacturaOut)
def actualizar(id: int, data: FacturaUpdate, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    f = db.get(Factura, id)
    if not f:
        raise HTTPException(404, "Factura no encontrada")
    campos = data.model_dump(exclude_unset=True)
    if "estado" in campos and campos["estado"] not in ("borrador", "emitida", "pagada", "anulada"):
        raise HTTPException(400, "Estado inválido")
    recalc = any(k in campos for k in ("precio_kwh", "consumo_mwh", "itbms_pct"))
    for campo, valor in campos.items():
        setattr(f, campo, valor)
    if recalc:
        # recalcular solo la primera linea (energia en contratos)
        if f.detalles:
            f.detalles[0].monto = round(float(f.consumo_mwh or 0) * 1000 * float(f.precio_kwh or 0), 2)
        subtotal, itbms, total = svc.totales(
            [{"monto": float(d.monto) if d.monto is not None else None, "es_total": d.es_total} for d in f.detalles],
            float(f.itbms_pct or 0),
        )
        f.subtotal, f.itbms, f.total = subtotal, itbms, total
    db.commit()
    db.refresh(f)
    return _out(f)


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), _: Usuario = Depends(admin)):
    f = db.get(Factura, id)
    if not f:
        raise HTTPException(404, "Factura no encontrada")
    db.delete(f)
    db.commit()


@router.get("/{id}/consumo")
def consumo(id: int, tipo: str = "diario", db: Session = Depends(get_db),
            usuario: Usuario = Depends(get_current_user)):
    """Serie de consumo del cliente para la grafica.

    tipo = 'diario' (barras por dia) | 'historico' (barras por mes) |
           'costo' (barras kWh + linea del costo promedio B/./kWh).
    """
    f = db.get(Factura, id)
    if not f:
        raise HTTPException(404, "Factura no encontrada")
    if not acceso.puede_ver_cliente(db, usuario, f.id_cliente):
        raise HTTPException(403, "Sin acceso a esta factura")
    return _payload_grafica(db, f, tipo)


@router.get("/{id}/html", response_class=HTMLResponse)
def ver_html(id: int, grafica: str | None = None, graficas: str | None = None, db: Session = Depends(get_db)):
    """HTML imprimible de la factura (pagina 1) + grafica de consumo (pagina 2).

    Parametro `grafica`: diario | historico | costo.
    Sin token para poder abrirla directamente en el navegador (pestana nueva).
    """
    f = db.get(Factura, id)
    if not f:
        raise HTTPException(404, "Factura no encontrada")
    cl = f.cliente
    ag = f.agente
    # Determinar que graficas imprimir: param explicito > el guardado en la factura > diario
    if graficas:
        tipos = [t.strip() for t in graficas.split(",") if t.strip()]
    elif grafica:
        tipos = [grafica]
    else:
        tipos = [t.strip() for t in (f.graficas or "diario").split(",") if t.strip()]
    if not tipos:
        tipos = ["diario"]
    payloads = [_payload_grafica(db, f, t) for t in tipos]
    datos = {
        "numero": f.numero,
        "periodo": f.periodo,
        "moneda": f.moneda,
        "tarifa": f.tarifa,
        "precio_kwh": float(f.precio_kwh or 0),
        "consumo_mwh": float(f.consumo_mwh or 0),
        "dias_lectura": f.dias_lectura,
        "fecha_emision": f.fecha_emision,
        "fecha_vencimiento": f.fecha_vencimiento,
        "subtotal": float(f.subtotal or 0),
        "itbms_pct": float(f.itbms_pct or 0),
        "itbms": float(f.itbms or 0),
        "total": float(f.total or 0),
        "observaciones": f.observaciones,
        "estado": f.estado,
        "emisor": {
            "nombre": ag.codigo if ag else "",
            "razon_social": ag.nombre if ag else "",
            "ruc": ag.ruc if ag else None,
            "direccion": ag.direccion if ag else None,
            "telefono": ag.telefono if ag else None,
        },
        "cliente": {
            "nombre": cl.nombre if cl else "",
            "codigo": cl.codigo if cl else "",
            "ruc": cl.ruc if cl else None,
            "direccion": cl.direccion if cl else None,
            "telefono": cl.telefono if cl else None,
            "contacto": cl.contacto if cl else None,
            "nis": cl.nis if cl else None,
        },
        "lineas": [
            {
                "descripcion": d.descripcion,
                "consumo": d.consumo,
                "cantidad": float(d.cantidad) if d.cantidad is not None else None,
                "unidad": d.unidad,
                "monto": float(d.monto) if d.monto is not None else None,
                "es_total": d.es_total,
            }
            for d in f.detalles
        ],
        "serie": _serie_consumo(db, f.id_cliente),
        "historico": _historico_cliente(db, f.id_cliente, f.periodo),
        "grafica": payloads[0],
        "graficas": payloads,
    }
    return HTMLResponse(svc.render_html(datos))
