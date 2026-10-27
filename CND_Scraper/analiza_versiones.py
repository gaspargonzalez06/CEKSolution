# -*- coding: utf-8 -*-
"""Resumen del catalogo: versiones por tipo/periodo y rango de fechas publicado."""
import json, glob, os, sys
from collections import defaultdict
sys.stdout.reconfigure(errors="replace")

cat = json.load(open(sorted(glob.glob(os.path.join(os.path.dirname(__file__), "catalog_*.json")))[-1], encoding="utf-8"))

print(f"Total items en catalogo: {len(cat)}")
def pub(it):
    return str(it.get("fechaPublicaFull") or "")
pubs = [pub(it) for it in cat if pub(it)]
print(f"Rango de publicacion: {min(pubs)[:10]} .. {max(pubs)[:10]}\n")

# Agrupar 'Preliminar Sustentos' y 'DTE Sustentos' por periodo
for want in ["Preliminar Sustentos", "DTE Sustentos"]:
    print(f"=== {want} ===")
    per = defaultdict(list)
    for it in cat:
        t = (it.get("tipo") or {}).get("name", "")
        if t != want:
            continue
        per[(it.get("anio"), (it.get("mes") or {}).get("numero"))].append(it)
    for k in sorted(per, key=lambda x: (x[0] or 0, x[1] or 0)):
        items = sorted(per[k], key=lambda it: pub(it))
        print(f"  {k[0]}-{int(k[1]):02d}: {len(items)} versiones  "
              f"[{pub(items[0])[:10]} .. {pub(items[-1])[:10]}]")
    print()

# Tipos mas frecuentes (para contexto)
tipos = defaultdict(int)
for it in cat:
    tipos[(it.get("tipo") or {}).get("name", "")] += 1
print("=== Top tipos de informe (todo el catalogo) ===")
for t, c in sorted(tipos.items(), key=lambda x: -x[1])[:20]:
    print(f"  {c:>4}  {t}")
