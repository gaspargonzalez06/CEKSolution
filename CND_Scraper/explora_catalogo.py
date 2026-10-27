# -*- coding: utf-8 -*-
"""Resume el catalogo del portal y la carpeta raw para planificar la extraccion."""
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(errors="replace")
ROOT = Path(__file__).resolve().parent
catalogs = sorted(ROOT.glob("catalog_*.json"))
print("Catalogos guardados:", [c.name for c in catalogs][-5:])
cat = json.loads(catalogs[-1].read_text(encoding="utf-8"))
print("Total reportes en catalogo:", len(cat), "\n")

por_tipo = defaultdict(Counter)
por_periodo = defaultdict(set)
for it in cat:
    tipo = (it.get("tipo") or {}).get("name", "?")
    path = (it.get("adjunto") or {}).get("path", "") or ""
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else "?"
    por_tipo[tipo][ext] += 1
    anio = it.get("anio")
    mes = (it.get("mes") or {}).get("numero")
    por_periodo[tipo].add((anio, mes))

print("== TIPOS DE REPORTE (extension: cantidad) ==")
for tipo, exts in sorted(por_tipo.items()):
    total = sum(exts.values())
    print(f"\n  {tipo}  ({total})")
    print("     ", dict(exts))
    periodos = sorted({f"{a}-{m:02d}" for (a, m) in por_periodo[tipo] if a and m})
    print("      periodos:", ", ".join(periodos) if periodos else "-")

print("\n== ARCHIVOS RAW DESCARGADOS ==")
raw = ROOT / "raw"
if raw.exists():
    ext_c = Counter()
    for f in raw.rglob("*"):
        if f.is_file():
            ext_c[f.suffix.lower()] += 1
    print("  por extension:", dict(ext_c))
    for tipo_dir in sorted({p.parent for p in raw.rglob("*") if p.is_file()}):
        n = len(list(tipo_dir.glob("*")))
        print(f"   {tipo_dir.relative_to(raw)}  ({n} archivos)")
else:
    print("  (no existe raw/)")
