# -*- coding: utf-8 -*-
"""Lector tolerante para los exportes de SQL Server (base vieja CEK).

Acepta archivos separados por tabulador (pegados en Excel/TSV) o por coma
(CSV de SSMS "Save Results As..."), con o sin comillas, y detecta el
separador automaticamente leyendo la primera linea.
"""
import csv
from pathlib import Path


def _detectar_delimitador(linea: str) -> str:
    if "\t" in linea:
        return "\t"
    if ";" in linea and linea.count(";") >= linea.count(","):
        return ";"
    return ","


def leer_tabla(ruta: Path) -> list[dict]:
    """Devuelve una lista de diccionarios (cabecera -> valor) ya limpios."""
    texto = ruta.read_text(encoding="utf-8-sig", errors="replace")
    lineas = [l for l in texto.splitlines() if l.strip()]
    if not lineas:
        return []
    delim = _detectar_delimitador(lineas[0])
    lector = csv.reader(lineas, delimiter=delim)
    cabecera = [c.strip().lstrip("\ufeff").strip('"').strip() for c in next(lector)]
    filas: list[dict] = []
    for partes in lector:
        partes = [(p or "").strip().strip('"').strip() for p in partes]
        partes += [""] * (len(cabecera) - len(partes))
        filas.append(dict(zip(cabecera, partes)))
    return filas
