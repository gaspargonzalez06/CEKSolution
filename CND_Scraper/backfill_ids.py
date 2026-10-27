#!/usr/bin/env python3
"""Backfill reporte_id en raw_data/scraping_log usando el catalogo mas reciente."""
import asyncio, glob, json, sys
import aiomysql, yaml
from pathlib import Path
for s in (sys.stdout, sys.stderr):
    try: s.reconfigure(errors="replace")
    except Exception: pass

ROOT = Path(__file__).resolve().parent
CFG = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))
DB = CFG["database"]


async def main():
    cats = sorted(glob.glob(str(ROOT / "catalog_*.json")))
    catalog = json.load(open(cats[-1], encoding="utf-8"))
    path2id = {}
    for it in catalog:
        p = (it.get("adjunto") or {}).get("path")
        if p:
            path2id[p] = it["id"]
    print(f"catalogo: {cats[-1]} ({len(path2id)} paths)")

    conn = await aiomysql.connect(host=DB["host"], port=int(DB["port"]),
                                  user=DB["username"], password=DB["password"],
                                  db=DB["database"], charset="utf8mb4", autocommit=True)
    n = 0
    async with conn.cursor() as cur:
        await cur.execute("SELECT id, archivo_origen, archivo_hash FROM raw_data WHERE reporte_id IS NULL")
        rows = await cur.fetchall()
        for rid, origen, h in rows:
            cat_id = path2id.get(origen)
            if cat_id:
                await cur.execute("UPDATE raw_data SET reporte_id=%s WHERE id=%s", (cat_id, rid))
                await cur.execute("UPDATE scraping_log SET reporte_id=%s WHERE archivo_hash=%s",
                                  (cat_id, h))
                n += 1
    async with conn.cursor() as cur:
        await cur.execute("SELECT COUNT(*) FROM raw_data WHERE reporte_id IS NOT NULL")
        tot = (await cur.fetchone())[0]
    conn.close()
    print(f"backfill: {n} filas actualizadas | reporte_id no nulos: {tot}")


asyncio.run(main())
