#!/usr/bin/env python3
"""Captura la peticion real que hace la tabla Angular (params de paginacion)."""
import asyncio
from pathlib import Path
from playwright.async_api import async_playwright

USER, PWD = "BRILLOSOL", "bF50koniaR0="
await_urls = []


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(headless=True)
        ctx = await b.new_context(viewport={"width": 1366, "height": 900})
        page = await ctx.new_page()

        def on_req(req):
            u = req.url
            if "GetListOperativos" in u or "GetList" in u:
                await_urls.append((req.method, u, req.post_data))
                print("REQ", req.method, u)
                if req.post_data:
                    print("    POST:", req.post_data[:800])

        async def on_resp(resp):
            if "GetListOperativos" in resp.url:
                body = await resp.text()
                print(f"RESP {resp.status} len={len(body)} start={body[:160]!r}")

        page.on("request", on_req)
        page.on("response", lambda r: asyncio.create_task(on_resp(r)))

        await page.goto("https://sitiopublico.cnd.com.pa/privado/", wait_until="domcontentloaded")
        await asyncio.sleep(3)
        await page.fill("#modlgn-username", USER)
        await page.fill("#modlgn-passwd", PWD)
        await page.click('button.login-button[type="submit"]')
        await page.wait_for_load_state("networkidle")
        await asyncio.sleep(5)
        print("login ok")
        await page.goto("https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND",
                        wait_until="networkidle")
        await asyncio.sleep(6)
        # intentar paginar en la UI: buscar boton siguiente
        html = await page.content()
        Path("./recon/reports_page2.html").write_text(html, encoding="utf-8")
        print("nav ok, html saved")
        await asyncio.sleep(2)
        await b.close()


asyncio.run(main())
