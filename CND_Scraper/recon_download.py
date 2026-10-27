#!/usr/bin/env python3
"""Prueba el endpoint /Informe/Download/{id} de 3 formas distintas."""
import asyncio, sys
from playwright.async_api import async_playwright
for s in (sys.stdout, sys.stderr):
    try: s.reconfigure(errors="replace")
    except Exception: pass

USER, PWD = "BRILLOSOL", "bF50koniaR0="
TEST = [(4167493, "csv"), (4152040, "txt")]


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(headless=True)
        ctx = await b.new_context(viewport={"width": 1366, "height": 900}, accept_downloads=True)
        page = await ctx.new_page()
        await page.goto("https://sitiopublico.cnd.com.pa/privado/", wait_until="domcontentloaded")
        await asyncio.sleep(3)
        await page.fill("#modlgn-username", USER)
        await page.fill("#modlgn-passwd", PWD)
        await page.click('button.login-button[type="submit"]')
        await page.wait_for_load_state("networkidle")
        await asyncio.sleep(5)
        # navegar a la pagina de informes para "calentar" la sesion
        await page.goto("https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND",
                        wait_until="networkidle")
        await asyncio.sleep(4)
        print("login+nav ok")

        for rid, kind in TEST:
            url = f"https://sitioprivado.cnd.com.pa/Informe/Download/{rid}"
            print(f"\n=== {kind} id={rid} ===")
            # forma 1: APIRequestContext
            try:
                r = await ctx.request.get(url, timeout=25000)
                body = await r.body()
                print(f"  [api] status={r.status} ctype={r.headers.get('content-type')} "
                      f"cd={r.headers.get('content-disposition')} len={len(body)}")
            except Exception as e:
                print(f"  [api] ERROR {str(e)[:120]}")

            # forma 2: page.goto + expect_download
            try:
                async with page.expect_download(timeout=25000) as dl:
                    await page.goto(url)
                d = await dl.value
                path = await d.path()
                import os
                sz = os.path.getsize(path) if path else 0
                print(f"  [goto+download] suggested={d.suggested_filename} size={sz}")
            except Exception as e:
                print(f"  [goto+download] ERROR {str(e)[:120]}")

            # forma 3: fetch dentro de la pagina
            try:
                res = await page.evaluate(
                    """async (u) => { const r = await fetch(u); const t = await r.text();
                       return {status:r.status, len:t.length, head:t.slice(0,120)}; }""", url)
                print(f"  [js fetch] {res}")
            except Exception as e:
                print(f"  [js fetch] ERROR {str(e)[:120]}")

        await b.close()


asyncio.run(main())
