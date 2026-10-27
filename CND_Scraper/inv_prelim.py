# -*- coding: utf-8 -*-
import json, glob, os, sys
from collections import defaultdict
sys.stdout.reconfigure(errors="replace")

cat = json.load(open(sorted(glob.glob(os.path.join(os.path.dirname(__file__), "catalog_*.json")))[-1], encoding="utf-8"))

for per in [(2026, 10), (2026, 9)]:
    print(f"===== Preliminar Sustentos {per[0]}-{per[1]:02d} =====")
    items = [it for it in cat
             if (it.get("tipo") or {}).get("name") == "Preliminar Sustentos"
             and it.get("anio") == per[0] and (it.get("mes") or {}).get("numero") == per[1]]
    items.sort(key=lambda it: str(it.get("fechaPublicaFull")))
    print(f"  {len(items)} items")
    for it in items[:15]:
        adj = (it.get("adjunto") or {}).get("path", "")
        arch = it.get("archivos")
        ext = os.path.splitext(adj)[1]
        print(f"   {it['id']:>8}  {str(it.get('fechaPublicaFull'))[:19]:19}  ext={ext:6}  archivos={type(arch).__name__}  {os.path.basename(adj)}")
    if len(items) > 15:
        print(f"   ... y {len(items)-15} mas")
    print()
