# -*- coding: utf-8 -*-
"""Carga la tabla `mediciones` desde los crudos CND (Liquidacion oficial, hoja MEDICIONES).

Es la tabla que leia el sistema viejo para el CONSUMO del cliente
(funcion fn_historialconsumo): el consumo mensual medido, que alimenta la linea
"Energia en contratos" y el historico de Consumos de la factura.

Cada archivo per-cliente de la liquidacion trae, hora por hora, la columna
`consumo` (MWh, 6 decimales) del cliente. El consumo mensual es la suma de esa
columna. Se usa la version Regular (los archivos _AjN se ignoran, igual que
hacia el sistema viejo con Tipo='Regular').

Uso:
    python importar_mediciones.py                    # todos los periodos presentes
    python importar_mediciones.py --periodo 202607
    python importar_mediciones.py --listar
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import text  # noqa: E402

from app.core.database import engine  # noqa: E402

BASE = Path(__file__).resolve().parent.parent
RAW = BASE / "CND_Scraper" / "raw"

DDL = """
CREATE TABLE IF NOT EXISTS mediciones (
    id BIGINT NOT NULL AUTO_INCREMENT,
    annio INT DEFAULT NULL,
    mes INT DEFAULT NULL,
    generador VARCHAR(20) DEFAULT NULL,
    cliente VARCHAR(20) DEFAULT NULL,
    consumo DECIMAL(14,6) DEFAULT NULL,
    periodo CHAR(6) GENERATED ALWAYS AS (CONCAT(annio, LPAD(mes,2,'0'))) STORED,
    archivo_origen VARCHAR(255) DEFAULT NULL,
    fecha_carga DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_mediciones (cliente, generador, periodo),
    KEY idx_med_periodo (periodo),
    KEY idx_med_cliente (cliente)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"""

RE_CLIENTE = re.compile(r"_(gcp\d{4})_", re.I)


def archivos_liquidacion() -> list[tuple[str, str, str, Path]]:
    """(generador, periodo, cliente, archivo) de cada liquidacion per-cliente Regular."""
    out = []
    for carpeta in RAW.rglob("CND_DTE_LIQUIDACION"):
        generador = carpeta.parent.name
        for sub in sorted(p for p in carpeta.iterdir() if p.is_dir()):
            periodo = sub.name
            if not (periodo.isdigit() and len(periodo) == 6):
                continue
            for arch in sorted(sub.glob("*.xlsx")):
                if "_aj" in arch.name.lower():
                    continue
                m = RE_CLIENTE.search(arch.name)
                if not m:
                    continue
                out.append((generador, periodo, m.group(1).upper(), arch))
    return out


def leer_consumo(arch: Path) -> float | None:
    import openpyxl

    wb = openpyxl.load_workbook(arch, read_only=True, data_only=True)
    if "MEDICIONES" not in wb.sheetnames:
        wb.close()
        return None
    ws = wb["MEDICIONES"]
    filas = list(ws.iter_rows(values_only=True))
    wb.close()

    # localiza el header (fila con "Fecha") y la columna de consumo del cliente
    ini = col = None
    for i, fila in enumerate(filas):
        celdas = [str(c).strip().lower() if c is not None else "" for c in fila]
        if "fecha" in celdas and ("hora" in celdas or "consumo" in celdas):
            ini = i + 1
            if "consumo" in celdas:
                col = celdas.index("consumo")
            else:
                # columna con el nombre del cliente (p.ej. tova_chitre_a_e)
                for j, c in enumerate(celdas):
                    if c.endswith("_a_e"):
                        col = j
                        break
            break
    if ini is None or col is None:
        return None

    total = 0.0
    for fila in filas[ini:]:
        if col < len(fila) and isinstance(fila[col], (int, float)):
            total += float(fila[col])
    return round(total, 6)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodo")
    ap.add_argument("--listar", action="store_true")
    args = ap.parse_args()

    todos = archivos_liquidacion()
    if args.periodo:
        todos = [t for t in todos if t[1] == args.periodo]

    with engine.begin() as cn:
        if not args.listar:
            cn.execute(text(DDL))

        filas = []
        for generador, periodo, cliente, arch in sorted(todos, key=lambda t: (t[1], t[2])):
            consumo = leer_consumo(arch)
            if consumo is None:
                print(f"    {generador}/{periodo} {cliente}: {arch.name} (sin columna consumo)")
                continue
            print(f"    {generador}/{periodo} {cliente}: {consumo:.6f} MWh  ({arch.name})")
            filas.append({
                "annio": int(periodo[:4]), "mes": int(periodo[4:6]),
                "generador": generador, "cliente": cliente,
                "consumo": consumo, "archivo_origen": arch.name,
            })

        if filas and not args.listar:
            # idempotente por (generador, periodo)
            for periodo in {f"{f['annio']}{f['mes']:02d}" for f in filas}:
                cn.execute(text("DELETE FROM mediciones WHERE periodo=:p"), {"p": periodo})
            cn.execute(text(
                "INSERT INTO mediciones (annio, mes, generador, cliente, consumo, archivo_origen) "
                "VALUES (:annio,:mes,:generador,:cliente,:consumo,:archivo_origen)"
            ), filas)

        print(f"[ok] {len(filas)} consumos" + (" (listar)" if args.listar else ""))


if __name__ == "__main__":
    main()
