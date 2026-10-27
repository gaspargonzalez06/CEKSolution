# -*- coding: utf-8 -*-
"""Endpoints de analisis: graficas del mercado (sustentos CND)."""
import calendar
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core import acceso
from app.core.database import engine, get_db
from app.core.deps import get_current_user
from app.models import Agente, Cliente, Contrato, Factura, Medicion, Precio, Usuario
from app.services import analisis as svc
from app.services import consumo as consumo_svc
from app.services import resumen as resumen_svc

log = logging.getLogger("cek.analisis")

router = APIRouter(prefix="/analisis", tags=["Análisis"])


@router.get("/sustentos")
def sustentos(
    periodo: str | None = None,
    agente: str | None = None,
    version: int | None = None,
    db: Session = Depends(get_db),
    _: Usuario = Depends(get_current_user),
):
    """Evolucion, proyeccion, pintado por version, ajustes, perfil horario y BRILLOSOL.

    Filtrable por periodo (`AAAAMM`), agente (codigo del CND) y version.
    """
    try:
        return svc.construir(db, periodo=periodo, agente=agente, version=version)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.post("/refrescar")
def refrescar(_: Usuario = Depends(get_current_user)):
    """Recalcula las tablas resumen (util tras cargar nuevos sustentos a mano)."""
    try:
        with engine.begin() as conn:
            resumen_svc.refrescar(conn)
    except Exception as exc:  # pragma: no cover - informativo
        log.exception("No se pudieron recalcular las tablas resumen")
        raise HTTPException(status_code=500, detail=f"No se pudo recalcular: {exc}")
    return {"ok": True}


@router.get("/clientes")
def clientes_por_agente(
    periodo: str | None = None,
    id_agente: int | None = None,
    id_cliente: int | None = None,
    limite: int = 13,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Consumo mensual de los clientes de un agente (o de todos) hasta `periodo`.

    Base del analisis en pantalla: se elige agente + mes y se grafica el consumo
    de TODOS sus clientes a la vez (misma fuente que la factura: `mediciones`),
    con la factura del periodo si ya existe.

    Jerarquia completa: "Todos" -> agente -> cliente. Si se indica `id_cliente`
    el analisis se acota a ese cliente (los totales del encabezado tambien).
    """
    per = (periodo or "").strip()
    if len(per) != 6 or not per.isdigit():
        # Sin período explícito: usar el último mes con consumo real, no el mes
        # calendario (que suele estar vacío y hacía parecer que no había datos).
        ultimo = (
            db.query(func.max(Medicion.periodo))
            .filter(Medicion.consumo > 0)
            .scalar()
        )
        if ultimo:
            per = str(ultimo)
        else:
            hoy = datetime.utcnow()
            per = f"{hoy.year}{hoy.month:02d}"

    permitidos = acceso.clientes_permitidos(db, usuario)
    if permitidos is not None and not permitidos:
        return {"periodo": per, "id_agente": id_agente, "id_cliente": id_cliente,
                "n_clientes": 0, "n_facturas": 0, "total_mwh": 0.0,
                "total_facturado": 0.0, "clientes": []}

    q = db.query(Contrato)
    if id_agente is not None:
        q = q.filter(Contrato.id_agente == id_agente)
    por_cliente: dict[int, int | None] = {}
    contratos_por_cliente: dict[int, Contrato] = {}
    for c in q.order_by(Contrato.id.desc()).all():
        if c.id_cliente not in por_cliente:
            por_cliente[c.id_cliente] = c.id_agente
            contratos_por_cliente[c.id_cliente] = c

    if id_cliente is not None:
        # Un cliente concreto manda: se analiza solo ese cliente aunque su
        # contrato no pertenezca al agente filtrado (o no tenga contrato).
        por_cliente = {id_cliente: por_cliente.get(id_cliente)}

    agentes_map = {a.id: a for a in db.query(Agente).all()}
    try:
        dias_mes = calendar.monthrange(int(per[:4]), int(per[4:6]))[1]
    except (ValueError, IndexError):
        dias_mes = 30

    clientes_out: list[dict] = []
    total_mwh = 0.0
    total_facturado = 0.0
    total_proyectado = 0.0
    n_facturas = 0
    for cid, id_ag in por_cliente.items():
        if permitidos is not None and cid not in permitidos:
            continue
        cl = db.get(Cliente, cid)
        if not cl or not cl.codigo:
            continue
        serie = consumo_svc.consumo_mensual_mediciones(
            db, cl.codigo, cl.id, hasta=per, limite=limite)
        del_periodo = next((s["mwh"] for s in serie if s["periodo"] == per), None)
        anteriores = [s for s in serie if s["periodo"] < per]
        previo = anteriores[-1]["mwh"] if anteriores else None
        variacion = None
        if previo and float(previo) > 0 and del_periodo is not None:
            variacion = round(
                (float(del_periodo) - float(previo)) / float(previo) * 100, 2)

        # Proyección del mes con datos diarios reales (si existen).
        proyeccion = None
        diario = consumo_svc.consumo_diario(db, cliente=cl.codigo, periodo=per)
        if diario:
            dias = len({d["fecha"] for d in diario if d.get("kwh") is not None})
            total_kwh = sum(float(d.get("kwh") or 0) for d in diario)
            if dias > 0:
                proyeccion = round(total_kwh * dias_mes / dias / 1000.0, 3)

        fac = (
            db.query(Factura)
            .filter(Factura.id_cliente == cl.id, Factura.periodo == per,
                    Factura.estado != "anulada")
            .order_by(Factura.id.desc())
            .first()
        )
        facs = (
            db.query(Factura)
            .filter(Factura.id_cliente == cl.id, Factura.estado != "anulada")
            .order_by(Factura.periodo.desc())
            .limit(6)
            .all()
        )
        contrato = contratos_por_cliente.get(cl.id)
        tarifa = None
        if contrato:
            precio = (
                db.query(Precio)
                .filter(Precio.id_contrato == contrato.id)
                .order_by(Precio.inicia.desc())
                .first()
            )
            tarifa = precio.tarifa if precio else None
        ag = agentes_map.get(id_ag or 0)
        consumo = float(del_periodo or 0.0)
        total_mwh += consumo
        if proyeccion:
            total_proyectado += proyeccion
        if fac:
            n_facturas += 1
            total_facturado += float(fac.total or 0)
        clientes_out.append({
            "id_cliente": cl.id,
            "codigo": cl.codigo,
            "nombre": cl.nombre or cl.codigo,
            "id_agente": id_ag,
            "agente_codigo": ag.codigo if ag else None,
            "agente_nombre": ag.nombre if ag else None,
            "contrato": contrato.contrato if contrato else None,
            "tarifa": tarifa,
            "periodo": per,
            "consumo_mwh": round(consumo, 6),
            "proyeccion_mwh": proyeccion,
            "variacion_pct": variacion,
            "serie": [
                {"periodo": s["periodo"], "etiqueta": s["etiqueta"],
                 "mwh": s["mwh"], "kwh": s["kwh"]}
                for s in serie
            ],
            "factura": (
                {"id": fac.id, "numero": fac.numero,
                 "total": float(fac.total or 0), "estado": fac.estado}
                if fac else None
            ),
            "facturas": [
                {"id": f.id, "numero": f.numero, "periodo": f.periodo,
                 "total": float(f.total or 0), "estado": f.estado}
                for f in facs
            ],
        })

    clientes_out.sort(key=lambda c: c["consumo_mwh"], reverse=True)
    return {
        "periodo": per,
        "id_agente": id_agente,
        "id_cliente": id_cliente,
        "n_clientes": len(clientes_out),
        "n_facturas": n_facturas,
        "total_mwh": round(total_mwh, 6),
        "total_proyectado_mwh": round(total_proyectado, 6),
        "total_facturado": round(total_facturado, 2),
        "clientes": clientes_out,
    }
