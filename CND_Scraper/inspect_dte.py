# -*- coding: utf-8 -*-
"""Inspecciona los archivos DTE Tabular para ver la relacion agente <-> cliente."""
import sys
from pathlib import Path

sys.stdout.reconfigure(errors="replace")
ROOT = Path(__file__).resolve().parent

for carpeta in sorted((ROOT / "raw" / "BRILLOSOL" / "CND_DTE_TABULAR").glob("*")):
    print("=" * 70)
    print("CARPETA:", carpeta.relative_to(ROOT))
    for f in sorted(carpeta.glob("*.txt")):
        print("\n--- ", f.name)
        for enc in ("utf-8", "latin-1"):
            try:
                lineas = f.read_text(encoding=enc).splitlines()
                break
            except Exception:
                lineas = []
        print(f"    lineas: {len(lineas)}")
        for i, ln in enumerate(lineas[:8]):
            print(f"    {i:>2}: {ln[:140]}")
        if len(lineas) > 8:
            print("     ...")
            for i, ln in enumerate(lineas[-2:], start=len(lineas) - 2):
                print(f"    {i:>2}: {ln[:140]}")
