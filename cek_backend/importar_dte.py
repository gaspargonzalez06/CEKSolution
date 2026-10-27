# -*- coding: utf-8 -*-
"""Carga la tabla `dte` desde los crudos CND (DTE Tabular + Detalle de Pérdidas).

Esta tabla es EXACTAMENTE la que leia el sistema viejo para armar los cargos de
mercado de la factura:

    fn_costos(@cCliente, @cPeriodo)      -> los 4 cargos (Pérdidas, Extra costo,
                                             Serv Aux seguimiento, Serv Auxiliares)
    fn_CostoMercado(@cCliente, @cPeriodo)-> total del costo de mercado

Fuentes (igual que el sistema viejo):
  * DTE Tabular (balance de transacciones) -> Extra Costo, Serv Aux seguimiento y
    Servicios Auxiliares. Cada archivo per-cliente trae al CLIENTE en la columna
    AGENTE y a la contraparte en AGENTE_BALANCE. El neto de una transaccion =
    SUM(Debito) - SUM(Credito).
  * Detalle de Pérdidas de Transmision -> la linea "Energia en Perdidas de
    Transmision". El crudo es hora x acreedor; el sistema viejo guardaba un
    renglon POR ACREEDOR (cada uno redondeado a 2 decimales, columna numeric(9,2))
    y `fn_costos` los sumaba. Por eso la perdida de la factura NO es el neto del
    DTE Tabular: es la suma de los totales por acreedor, cada uno redondeado a
    centavos (redondeo half-up, como ROUND de SQL Server).
    Si no hay Detalle de Perdidas para el periodo se usa el neto del Tabular.

Reglas de importacion:
  * Una fila fisica puede traer DEBITO y/o CREDITO. Se guarda un renglon por
    cada valor distinto de cero, con Atributo = 'Debito' / 'Credito'.
  * Tipo = 'Regular' cuando el archivo no trae sufijo _AjN; 'Ajuste' cuando si
    (los ajustes se guardan aparte; los cargos usan Tipo='Regular').

Idempotente: antes de cargar borra lo existente de ese (generador, periodo).

Uso:
    python importar_dte.py                    # todos los periodos presentes
    python importar_dte.py --periodo 202606   # solo un periodo
    python importar_dte.py --listar           # solo muestra que haria
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import text  # noqa: E402

from app.core.database import engine  # noqa: E402

BASE = Path(__file__).resolve().parent.parent          # ...\AnalisisDescarga
RAW = BASE / "CND_Scraper" / "raw"

TX_PERDIDAS = "Energía en Pérdidas de Transmisión"
RE_CLIENTE = re.compile(r"_(gcp\d{4})_", re.I)


def a_num(s: str) -> float:
    s = (s or "").strip().strip('"').replace(",", "")
    try:
        return float(s)
    except ValueError:
        return 0.0


def r2(x: float) -> float:
    """Redondea a 2 decimales 'half-up' (como ROUND de SQL Server), no el de Python."""
    return float(Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def es_ajuste(nombre: str) -> bool:
    base = nombre.lower()
    return "_aj" in base


def key_file(nombre: str) -> str:
    return nombre.split("_", 1)[0]


def archivos_dte() -> list[tuple[str, str, Path]]:
    """Devuelve (generador, periodo, archivo) de cada .txt de DTE Tabular."""
    out: list[tuple[str, str, Path]] = []
    for carpeta in RAW.rglob("CND_DTE_TABULAR"):
        generador = carpeta.parent.name
        for sub in sorted(p for p in carpeta.iterdir() if p.is_dir()):
            periodo = sub.name
            if not (periodo.isdigit() and len(periodo) == 6):
                continue
            for arch in sorted(sub.glob("*.txt")):
                out.append((generador, periodo, arch))
    return out


def archivos_perdidas() -> list[tuple[str, str, str, Path]]:
    """(generador, periodo, cliente, archivo) de cada Detalle de Perdidas per-cliente Regular."""
    out: list[tuple[str, str, str, Path]] = []
    for carpeta in RAW.rglob("CND_DTE_DETALLE_PERDIDAS"):
        generador = carpeta.parent.name
        for sub in sorted(p for p in carpeta.iterdir() if p.is_dir()):
            periodo = sub.name
            if not (periodo.isdigit() and len(periodo) == 6):
                continue
            for arch in sorted(sub.glob("*.xlsx")):
                if es_ajuste(arch.name):
                    continue
                m = RE_CLIENTE.search(arch.name)
                if not m:
                    continue
                out.append((generador, periodo, m.group(1).upper(), arch))
    return out


def filas_de_archivo(arch: Path) -> list[list[str]]:
    """Lee el TSV crudo y devuelve las filas utiles (sin header)."""
    filas: list[list[str]] = []
    with arch.open(newline="", encoding="utf-8-sig", errors="replace") as fh:
        rd = csv.reader(fh, delimiter="\t")
        next(rd, None)  # header
        for row in rd:
            if len(row) >= 9 and row[1].strip().strip('"'):
                filas.append(row)
    return filas


def leer_perdidas(arch: Path, cliente: str) -> float | None:
    """Total de perdidas del cliente = suma de los totales POR ACREEDOR (cada uno a 2 dec.).

    Reproduce el valor que guardaba el sistema viejo en `dte` (un renglon por
    acreedor, numeric(9,2)) y que `fn_costos` luego sumaba.
    """
    import openpyxl

    wb = openpyxl.load_workbook(arch, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]
    filas = list(ws.iter_rows(values_only=True))
    wb.close()

    hidx = idx = None
    for i, fila in enumerate(filas[:8]):
        celdas = [str(c).strip() if c is not None else "" for c in fila]
        if "Monto" in celdas and "Acreedor" in celdas:
            hidx = i
            idx = {c: j for j, c in enumerate(celdas)}
            break
    if hidx is None:
        return None

    c_ac = idx["Acreedor"]
    c_val = idx.get("Valorizado")
    c_m = idx["Monto"]
    c_deu = idx.get("Deudor")

    por_ac: dict[str, float] = {}
    for fila in filas[hidx + 1:]:
        if fila is None or all(c is None for c in fila):
            continue
        if c_val is not None and c_val < len(fila):
            if str(fila[c_val]).strip().lower() not in ("sí", "si"):
                continue
        if c_deu is not None and c_deu < len(fila):
            deu = str(fila[c_deu] or "").strip()
            if deu and deu.upper() != cliente.upper():
                continue
        if c_m >= len(fila):
            continue
        try:
            m = float(fila[c_m] or 0)
        except (TypeError, ValueError):
            m = 0.0
        ac = str(fila[c_ac] or "").strip()
        por_ac[ac] = por_ac.get(ac, 0.0) + m

    return round(sum(r2(v) for v in por_ac.values()), 2)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodo", help="solo este periodo YYYYMM")
    ap.add_argument("--listar", action="store_true", help="no escribe, solo lista")
    args = ap.parse_args()

    todos = archivos_dte()
    if args.periodo:
        todos = [t for t in todos if t[1] == args.periodo]

    # perdidas: (generador, periodo) -> lista de (cliente, valor, archivo)
    perd_files = archivos_perdidas()
    if args.periodo:
        perd_files = [t for t in perd_files if t[1] == args.periodo]
    perd_por_gp: dict[tuple[str, str], list[tuple[str, float, str]]] = defaultdict(list)
    for gen, per, cli, arch in sorted(perd_files, key=lambda t: (t[1], t[2])):
        valor = leer_perdidas(arch, cli)
        if valor is None:
            print(f"    [!] {arch.name}: sin hoja de perdidas")
            continue
        perd_por_gp[(gen, per)].append((cli, valor, arch.name))

    # agrupa por (generador, periodo) para borrar+insertar de una vez
    grupos: dict[tuple[str, str], list[Path]] = defaultdict(list)
    for gen, per, arch in todos:
        grupos[(gen, per)].append(arch)

    print(f"[i] {len(todos)} archivos DTE en {len(grupos)} grupos (generador, periodo)")
    gran_total = 0

    with engine.begin() as cn:
        # la clave unica original no incluia `tipo`; se agrega para no chocar
        # Regular vs Ajuste con el mismo valor.
        idx = cn.execute(text(
            "SELECT COUNT(*) FROM information_schema.statistics "
            "WHERE table_schema=DATABASE() AND table_name='dte' "
            "AND index_name='uk_dte_upsert' AND column_name='tipo'"
        )).scalar()
        if not idx:
            if args.listar:
                print("[i] (listar) habria que recrear uk_dte_upsert para incluir `tipo`")
            else:
                print("[i] recreando uk_dte_upsert para incluir `tipo` ...")
                cn.execute(text("ALTER TABLE dte DROP INDEX uk_dte_upsert"))
                cn.execute(text(
                    "ALTER TABLE dte ADD UNIQUE KEY uk_dte_upsert "
                    "(cliente, generador, periodo, transaccion, tipo, atributo, hash_fila)"
                ))

        for (generador, periodo) in sorted(grupos):
            archivos = grupos[(generador, periodo)]
            perdidas = perd_por_gp.get((generador, periodo), [])
            # (cliente, transaccion, tipo, atributo) -> [valor, cantidad, u_m, key_file, archivo]
            agg: dict[tuple, list] = {}
            for arch in archivos:
                tipo = "Ajuste" if es_ajuste(arch.name) else "Regular"
                kf = key_file(arch.name)
                for row in filas_de_archivo(arch):
                    transaccion = row[2].strip().strip('"')
                    if transaccion == TX_PERDIDAS and perdidas:
                        # la perdida se toma del Detalle de Perdidas, no del Tabular
                        continue
                    cliente = row[1].strip().strip('"')
                    um = row[5].strip().strip('"')
                    cant = a_num(row[6])
                    deb = a_num(row[7])
                    cre = a_num(row[8])
                    for atributo, valor in (("Debito", deb), ("Credito", cre)):
                        if abs(valor) < 0.005:
                            continue
                        k = (cliente, transaccion, tipo, atributo)
                        slot = agg.setdefault(k, [0.0, 0.0, um, kf, arch.name])
                        slot[0] += valor
                        slot[1] += cant if atributo == "Debito" else 0.0

            if not args.listar:
                cn.execute(
                    text("DELETE FROM dte WHERE generador=:g AND periodo=:p"),
                    {"g": generador, "p": periodo},
                )

            valores = []
            for (cliente, transaccion, tipo, atributo), (valor, cant, um, kf, archivo) in agg.items():
                valores.append({
                    "key_file": kf,
                    "annio": int(periodo[:4]),
                    "mes": int(periodo[4:6]),
                    "generador": generador,
                    "cliente": cliente,
                    "codigo_agente": "",
                    "transaccion": transaccion,
                    "tipo": tipo,
                    "u_m": um,
                    "cantidad": round(cant, 6),
                    "atributo": atributo,
                    "valor": round(valor, 2),
                    "archivo_origen": archivo,
                })
            # una linea de perdidas por cliente (ya viene redondeada por acreedor)
            for cliente, valor, archivo in perdidas:
                if abs(valor) < 0.005:
                    continue
                valores.append({
                    "key_file": key_file(archivo),
                    "annio": int(periodo[:4]),
                    "mes": int(periodo[4:6]),
                    "generador": generador,
                    "cliente": cliente,
                    "codigo_agente": "",
                    "transaccion": TX_PERDIDAS,
                    "tipo": "Regular",
                    "u_m": "",
                    "cantidad": 0.0,
                    "atributo": "Debito",
                    "valor": valor,
                    "archivo_origen": archivo,
                })
            if valores and not args.listar:
                cn.execute(text(
                    "INSERT INTO dte (key_file, annio, mes, generador, cliente, codigo_agente, "
                    "transaccion, tipo, u_m, cantidad, atributo, valor, archivo_origen) "
                    "VALUES (:key_file,:annio,:mes,:generador,:cliente,:codigo_agente,"
                    ":transaccion,:tipo,:u_m,:cantidad,:atributo,:valor,:archivo_origen)"
                ), valores)
            gran_total += len(valores)
            etiqueta = f" + {len(perdidas)} perdidas" if perdidas else ""
            print(f"    {generador}/{periodo}: {len(archivos)} archivos -> {len(valores)} renglones{etiqueta}")

    print(f"[ok] {gran_total} renglones cargados" + (" (listar: nada escrito)" if args.listar else ""))


if __name__ == "__main__":
    main()
