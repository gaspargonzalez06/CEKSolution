#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
backfill_regular.py - Baja del portal CND los reportes REGULARES (sin sufijo _AjN)
que faltan en disco, usando el catalogo ya descargado.

Motivo: el scraper (cnd_sync.py) al re-ejecutarse sobre un mes ya ajustado baja
solo la version vigente (_Aj1) y deja fuera la version Regular original, que es la
que usaba el sistema viejo para la factura (Tipo='Regular').

Uso:
    python backfill_regular.py --periodo 202607 --tipo "DTE Tabular"
    python backfill_regular.py --periodo 202607 --tipo "DTE Tabular" --incluir-ajustes
"""
import argparse
import asyncio
import glob
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

from playwright.async_api import async_playwright

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = Path(r"C:\Users\ggonzalez\Downloads\AnalisisDescarga\CND_Scraper")
RAW = ROOT / "raw" / "BRILLOSOL"
PORTAL_LOGIN = "https://sitiopublico.cnd.com.pa/privado/"
PORTAL_PRIV = "https://sitioprivado.cnd.com.pa"
USER, PWD = "BRILLOSOL", "bF50koniaR0="


def fname_from_path(p: str) -> str:
    return (p or "").replace("\\", "/").split("/")[-1]


def load_catalog() -> list:
    files = sorted(glob.glob(str(ROOT / "catalog_*.json")))
    if not files:
        raise SystemExit("No hay catalog_*.json")
    return json.load(open(files[-1], encoding="utf-8")), files[-1]


def periodo_of(it) -> str:
    a = it.get("anio") or 0
    m = ((it.get("mes") or {}).get("numero")) or 0
    return f"{a:04d}{m:02d}"


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodo", default="202607", help="AAAAMM")
    ap.add_argument("--tipo", default="DTE Tabular",
                    help="nombre exacto del tipo, o varios separados por coma")
    ap.add_argument("--solo-per-cliente", action="store_true",
                    help="omitir reportes del generador (BRILLOSOL) y system-wide")
    ap.add_argument("--ids", default="", help="lista de id(s) exactos separados por coma")
    ap.add_argument("--incluir-ajustes", action="store_true")
    ap.add_argument("--headful", action="store_true")
    args = ap.parse_args()

    tipos = {t.strip() for t in args.tipo.split(",") if t.strip()}
    ids = {int(x) for x in args.ids.split(",") if x.strip()}

    catalog, catfile = load_catalog()
    print(f"catalogo: {os.path.basename(catfile)} ({len(catalog)} entradas)")

    # seleccionar los reportes del periodo/tipo
    picks = []
    for it in catalog:
        if ids:
            if it.get("id") not in ids:
                continue
            per = periodo_of(it) or args.periodo
        else:
            if ((it.get("tipo") or {}).get("name")) not in tipos:
                continue
            if periodo_of(it) != args.periodo:
                continue
            per = args.periodo
        path = ((it.get("adjunto") or {}).get("path")) or ""
        nombre = fname_from_path(path)
        es_aj = "_Aj" in nombre
        if es_aj and not args.incluir_ajustes:
            continue
        if args.solo_per_cliente and not re.search(r"_gcp\d{4}_", nombre, re.I):
            continue
        tipo_dir = ((it.get("tipo") or {}).get("directory")) or list(tipos)[0]
        dest_dir = RAW / tipo_dir / per
        dest = dest_dir / f"{it['id']}_{nombre}"
        picks.append((it["id"], nombre, dest, es_aj))

    picks.sort(key=lambda x: x[1])
    print(f"\n[{', '.join(sorted(tipos))} {args.periodo}] {len(picks)} archivo(s) en catalogo:")
    faltan = []
    for rid, nombre, dest, es_aj in picks:
        existe = dest.exists()
        print(f"   {'OK ' if existe else 'FALTA'}  id={rid:<8} {nombre}")
        if not existe:
            faltan.append((rid, nombre, dest))

    if not faltan:
        print("\nNada que descargar: todos los archivos ya estan en disco.")
        return

    print(f"\n[DESCARGA] {len(faltan)} archivo(s) faltante(s). Login en el portal...")
    p = await async_playwright().start()
    browser = await p.chromium.launch(headless=not args.headful)
    ctx = await browser.new_context(viewport={"width": 1366, "height": 900}, accept_downloads=True)
    page = await ctx.new_page()
    await page.goto(PORTAL_LOGIN, wait_until="domcontentloaded")
    await asyncio.sleep(3)
    await page.fill("#modlgn-username", USER)
    await page.fill("#modlgn-passwd", PWD)
    await page.click('button.login-button[type="submit"]')
    await page.wait_for_load_state("networkidle")
    await asyncio.sleep(5)
    if await page.query_selector("#modlgn-username"):
        raise SystemExit("Login fallo")
    # calentar sesion en la pagina de informes
    await page.goto(f"{PORTAL_PRIV}/Informe/IndexOperativosComercialesCND", wait_until="networkidle")
    await asyncio.sleep(3)
    print("[LOGIN] OK\n")

    ok = err = 0
    for i, (rid, nombre, dest) in enumerate(faltan, 1):
        url = f"{PORTAL_PRIV}/Informe/Download/{rid}"
        print(f"  [{i}/{len(faltan)}] {nombre}")
        try:
            resp = await ctx.request.get(url, timeout=120000)
            body = await resp.body()
            if resp.status != 200 or not body:
                raise RuntimeError(f"HTTP {resp.status} / {len(body)} bytes")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
            head = body[:200].decode("utf-8-sig", errors="replace").replace("\n", " ").replace("\r", " ")
            print(f"        OK {len(body):,} bytes -> {dest}")
            print(f"        head: {head[:150]}")
            ok += 1
        except Exception as e:
            print(f"        ERROR: {e}")
            err += 1

    await ctx.close()
    await browser.close()
    await p.stop()
    print(f"\nRESULTADO: {ok} descargado(s), {err} error(es) [{datetime.now():%H:%M:%S}]")


if __name__ == "__main__":
    asyncio.run(main())
