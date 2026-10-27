# -*- coding: utf-8 -*-
"""Genera UNA factura por (cliente, periodo) para cada mes con datos FINALES.

Reglas (segun lo pedido):
- Solo se factura un periodo si tiene sustentos FINALES (`CND_DTE_SUSTENTOS`,
  marcados `es_total=1` en `sustento_version_resumen`). Los reportes preliminares
  NO son facturas.
- Solo se factura un periodo si tiene el DTE tabular (cargos reales del cliente).
- El consumo del cliente sale de `sustento_horario` (version final) para el agente
  igual al codigo del cliente (los GCP son agentes de carga en el sustento).
- Una factura por (cliente, periodo); se re-crean (borra y genera) para corregir.

Uso:
    python seed_facturas.py                      # todos los periodos finales
    python seed_facturas.py --periodos 202609    # solo esos (coma)
    python seed_facturas.py --precio 0.0775 --itbms 0
    python seed_facturas.py --dry-run            # no escribe
    python seed_facturas.py --conservar          # no borra las existentes
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.core.database import SessionLocal  # noqa: E402
from app.models import Cliente  # noqa: E402
from app.services.facturas import RAW_DIR  # noqa: E402
from sqlalchemy import text  # noqa: E402

BASE = "http://127.0.0.1:8000"


def req(metodo, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=metodo)
    with urllib.request.urlopen(r) as resp:
        txt = resp.read().decode("utf-8")
        return json.loads(txt) if txt else None


def login() -> str:
    form = urllib.parse.urlencode({"username": "admin", "password": "admin123"}).encode()
    r = urllib.request.Request(BASE + "/auth/login", data=form,
                               headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(r) as resp:
        return json.loads(resp.read())["access_token"]


def periodos_finales(db) -> dict[str, int]:
    """{periodo: version_num} de los meses con sustentos FINALES (es_total=1)."""
    filas = db.execute(text(
        "SELECT periodo, MAX(version_num) FROM sustento_version_resumen "
        "WHERE es_total=1 GROUP BY periodo ORDER BY periodo"
    )).fetchall()
    return {p: v for p, v in filas}


def periodos_preliminares(db) -> set[str]:
    filas = db.execute(text(
        "SELECT DISTINCT periodo FROM sustento_version_resumen WHERE es_total=0"
    )).fetchall()
    return {p for (p,) in filas}


def tiene_dte_tabular(periodo: str) -> bool:
    for carpeta in RAW_DIR.rglob("CND_DTE_TABULAR"):
        sub = carpeta / periodo
        if sub.is_dir() and any(sub.glob("*.txt")):
            return True
    return False


def consumo_cliente(db, codigo: str, periodo: str, version: int) -> float:
    v = db.execute(text(
        "SELECT ROUND(SUM(consumo),3) FROM sustento_horario "
        "WHERE periodo=:p AND version_num=:v AND agente=:a"
    ), {"p": periodo, "v": version, "a": codigo}).scalar()
    return float(v or 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodos", default="", help="lista AAAAMM separada por coma (def: todos los finales)")
    ap.add_argument("--precio", type=float, default=0.0775, help="precio B/./kWh del contrato")
    ap.add_argument("--itbms", type=float, default=0.0)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--conservar", action="store_true", help="no borrar facturas existentes")
    args = ap.parse_args()

    db = SessionLocal()
    finales = periodos_finales(db)
    prelim = periodos_preliminares(db)
    filtro = {p.strip() for p in args.periodos.split(",") if p.strip()}
    if filtro:
        finales = {p: v for p, v in finales.items() if p in filtro}

    if not finales:
        print("No hay periodos con sustentos FINALES (CND_DTE_SUSTENTOS). Nada que facturar.")
        print("  (periodos con solo preliminares, NO facturables:", sorted(prelim), ")")
        return

    print("Periodos FINALES a facturar:", {p: f"v{v}" for p, v in finales.items()})
    solo_prelim = prelim - set(finales)
    if solo_prelim:
        print("Periodos ignorados (solo preliminares, NO son facturas):", sorted(solo_prelim))

    clientes = db.query(Cliente).filter(Cliente.activo == True).order_by(Cliente.codigo).all()  # noqa: E712
    token = None if args.dry_run else login()

    for periodo, version in sorted(finales.items()):
        print("\n=== Periodo %s (version final %s) ===" % (periodo, version))
        if not tiene_dte_tabular(periodo):
            print("  sin DTE tabular: se omite (no hay cargos reales del mes)")
            continue

        existentes = req("GET", f"/facturas?periodo={periodo}", token) if token else []
        if existentes and not args.conservar:
            print("  borrando %d factura(s) previa(s) del periodo" % len(existentes))
            if token:
                for f in existentes:
                    req("DELETE", f"/facturas/{f['id']}", token)
            existentes = []
        ya = {f["id_cliente"] for f in existentes}

        creadas = 0
        saltadas = 0
        for c in clientes:
            if c.id in ya:
                print("  %-9s ya tiene factura" % c.codigo)
                saltadas += 1
                continue
            consumo = consumo_cliente(db, c.codigo, periodo, version)
            if consumo <= 0:
                print("  %-9s sin consumo en el sustento final: se omite" % c.codigo)
                saltadas += 1
                continue
            if args.dry_run:
                print("  %-9s [dry] consumo=%.3f MWh precio=%.4f" % (c.codigo, consumo, args.precio))
                continue
            fac = req("POST", "/facturas/generar", token, {
                "id_cliente": c.id,
                "periodo": periodo,
                "precio_kwh": args.precio,
                "itbms_pct": args.itbms,
                "incluir_dte": True,
                "consumo_mwh": consumo,
            })
            print("  %-9s %s  consumo=%8.3f MWh  total=%12.2f" % (
                c.codigo, fac["numero"], fac["consumo_mwh"], fac["total"]))
            creadas += 1
        print("  -> creadas=%d, omitidas=%d" % (creadas, saltadas))

    db.close()


if __name__ == "__main__":
    main()
