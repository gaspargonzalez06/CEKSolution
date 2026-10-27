# -*- coding: utf-8 -*-
"""Descarga un adjunto del portal CND por id usando la misma tecnica de
cnd_sync (login + request del contexto, sin recorrido de catalogo).

Uso:
    python download_adjunto.py --user OROSOL --password X \\
        --id 4025822 --tipo CND_DTER_OFICIAL --periodo 202607 \\
        --out "CND_DTER_OFICIAL\\202607\\0726_DTER_Oficial_OROSOL.xlsx"
"""
import argparse
import sys
from pathlib import Path

import asyncio

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE))

from cnd_scraper.login import CNDLogin  # noqa: E402
from playwright.async_api import async_playwright  # noqa: E402

PORTAL = "https://sitioprivado.cnd.com.pa"

ROOT = BASE
RAW = ROOT / "raw"


async def fetch_with_retry(ctx, url, retries=5, timeout=120000):
    last = None
    for i in range(1, retries + 1):
        try:
            return await ctx.request.get(url, timeout=timeout)
        except Exception as exc:
            last = exc
            print(f"  (reintento {i}/{retries}: {str(exc)[:70]})")
            await asyncio.sleep(2 * i)
    print(f"  [WARN] fallo: {last}")
    return None


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--id", type=int, required=True)
    ap.add_argument("--tipo", required=True, help="ej. CND_DTER_OFICIAL")
    ap.add_argument("--periodo", required=True, help="AAAAMM")
    ap.add_argument("--nombre", required=True, help="nombre de archivo destino")
    args = ap.parse_args()

    agente = args.user.strip().upper()
    dest = RAW / agente / args.tipo / args.periodo
    dest.mkdir(parents=True, exist_ok=True)
    ruta = dest / f"{args.id}_{args.nombre}"

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True)
        ctx = await browser.new_context(
            accept_downloads=True,
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
            ),
        )
        page = await ctx.new_page()
        login = CNDLogin(page)
        await login.login(args.user, args.password)

        url = f"{PORTAL}/Informe/Download/{args.id}"
        resp = await fetch_with_retry(ctx, url, retries=5, timeout=120000)
        if resp is None:
            print(f"[ERROR] sin respuesta para {url}")
            await browser.close()
            sys.exit(2)
        body = await resp.body()
        if resp.status != 200 or not body:
            print(f"[ERROR] HTTP {resp.status} / {len(body)} bytes para id {args.id}")
            await browser.close()
            sys.exit(2)
        ruta.write_bytes(body)
        print(f"OK  {ruta}  ({len(body):,} bytes)")
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
