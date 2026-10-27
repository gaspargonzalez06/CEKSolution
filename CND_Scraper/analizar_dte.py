# -*- coding: utf-8 -*-
"""Analiza los DTE tabulares: transacciones, contrapartes y agregados por GCP."""
import sys
from collections import defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent


def leer_texto(f: Path) -> str:
    """Los archivos son UTF-8; latin-1 como primera opcion corrompia los acentos."""
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return f.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return f.read_text(encoding="latin-1", errors="replace")

transacciones = defaultdict(float)   # nombre -> suma debito
contrapartes = set()
por_gcp = defaultdict(lambda: defaultdict(lambda: {"mwh": 0.0, "debito": 0.0, "credito": 0.0}))
archivos = 0
filas = 0

for carpeta in ROOT.rglob("CND_DTE_TABULAR"):
    if not carpeta.is_dir():
        continue
    for f in carpeta.rglob("*.txt"):
        archivos += 1
        try:
            texto = leer_texto(f)
        except Exception:
            continue
        lineas = texto.splitlines()
        if not lineas:
            continue
        for ln in lineas[1:]:
            if not ln.strip():
                continue
            p = ln.split("\t")
            if len(p) < 9:
                continue
            filas += 1
            agente = p[0].strip().strip('"')
            cod = p[1].strip().strip('"')
            trans = p[2].strip().strip('"')
            ag_bal = p[3].strip().strip('"')
            cod_bal = p[4].strip().strip('"')
            um = p[5].strip().strip('"')

            def num(x):
                x = x.strip().replace(",", "")
                try:
                    return float(x)
                except ValueError:
                    return 0.0

            cant, deb, cred = num(p[6]), num(p[7]), num(p[8])
            transacciones[trans] += deb
            if cod_bal:
                contrapartes.add(cod_bal)
            if cod.upper().startswith("GCP"):
                d = por_gcp[cod.upper()][trans]
                d["mwh"] += cant
                d["debito"] += deb
                d["credito"] += cred

print(f"Archivos: {archivos}  Filas: {filas}")
print("\n=== TRANSACCIONES (suma debito global) ===")
for t, v in sorted(transacciones.items(), key=lambda x: -x[1]):
    print(f"  {v:14,.2f}  {t}")
print(f"\n=== CONTRAPARTES ({len(contrapartes)}) ===")
print("  " + ", ".join(sorted(contrapartes)))
print("\n=== POR CLIENTE (GCP) ===")
for gcp in sorted(por_gcp):
    print(f"\n{gcp}:")
    tot_mwh = tot_d = tot_c = 0.0
    for t, d in sorted(por_gcp[gcp].items(), key=lambda x: -x[1]["debito"]):
        if d["debito"] or d["mwh"] or d["credito"]:
            print(f"   {t[:45]:45} MWh={d['mwh']:12,.3f} D={d['debito']:12,.2f} C={d['credito']:12,.2f}")
        tot_mwh += d["mwh"]; tot_d += d["debito"]; tot_c += d["credito"]
    print(f"   {'TOTAL':45} MWh={tot_mwh:12,.3f} D={tot_d:12,.2f} C={tot_c:12,.2f}")
