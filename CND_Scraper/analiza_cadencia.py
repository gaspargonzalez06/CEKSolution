# -*- coding: utf-8 -*-
"""Cruza los reporte_totales descargados con su fecha de publicacion del catalogo."""
import json, glob, os, sys
sys.stdout.reconfigure(errors="replace")

cat = json.load(open(sorted(glob.glob(os.path.join(os.path.dirname(__file__), "catalog_*.json")))[-1], encoding="utf-8"))
byid = {str(it["id"]): it for it in cat}

ids = ["4125972", "4129525", "4132937", "4136154", "4143560", "4143030",
       "4140416", "4145237", "4153162", "4157312", "4160450", "4165180", "4167493"]

print(f"{'id':>8}  {'tipo':28}  {'publicado':19}  adjunto")
for i in ids:
    it = byid.get(i)
    if not it:
        print(f"{i:>8}  (no en catalogo)")
        continue
    tipo = (it.get("tipo") or {}).get("name", "")
    adj = os.path.basename((it.get("adjunto") or {}).get("path", ""))
    print(f"{i:>8}  {tipo[:28]:28}  {str(it.get('fechaPublicaFull'))[:19]:19}  {adj}")
