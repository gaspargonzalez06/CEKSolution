#!/usr/bin/env python3
"""
RECON - solo descubre que tipos de archivo hay en el portal.
Headless (sin ventanas). No descarga nada, solo guarda HTML/JSON y lista links.
"""
import asyncio
import json
from pathlib import Path
from urllib.parse import urljoin
from playwright.async_api import async_playwright

USERNAME = "BRILLOSOL"
PASSWORD = "bF50koniaR0="
LOGIN_URL = "https://sitiopublico.cnd.com.pa/privado/"
REPORTS_URL = "https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND"
OUT = Path("./recon")
OUT.mkdir(parents=True, exist_ok=True)


async def main():
    print("=" * 60)
    print("RECON CND - headless")
    print("=" * 60)
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        ctx = await browser.new_context(viewport={"width": 1366, "height": 900}, accept_downloads=True)
        page = await ctx.new_page()
        page.set_default_timeout(60000)

        # LOGIN
        print("[1] Login...")
        await page.goto(LOGIN_URL, wait_until="domcontentloaded")
        await asyncio.sleep(3)
        await page.fill("#modlgn-username", USERNAME)
        await page.fill("#modlgn-passwd", PASSWORD)
        await page.click('button.login-button[type="submit"]')
        await page.wait_for_load_state("networkidle")
        await asyncio.sleep(5)
        still_login = await page.query_selector("#modlgn-username")
        print("    login OK" if not still_login else "    LOGIN FAIL")

        # REPORTS PAGE (dump once, no re-navigation afterwards)
        print("[2] Reports page...")
        await page.goto(REPORTS_URL, wait_until="networkidle")
        await asyncio.sleep(4)
        html = await page.content()
        (OUT / "reports_page.html").write_text(html, encoding="utf-8")
        print(f"    saved reports_page.html ({len(html)} chars)")

        # All anchors with href + text
        anchors = await page.eval_on_selector_all(
            "a",
            "els => els.map(e => ({href: e.getAttribute('href'), text: (e.innerText||'').trim()}))",
        )
        (OUT / "anchors.json").write_text(json.dumps(anchors, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"    total anchors: {len(anchors)}")

        dl = [a for a in anchors if a["href"] and "/Informe/Download/" in a["href"]]
        print(f"    download anchors: {len(dl)}")
        exts = {}
        for a in dl:
            e = Path(a["text"]).suffix.lower() or "(none)"
            exts[e] = exts.get(e, 0) + 1
        print(f"    extension breakdown (page 1): {exts}")
        for a in dl[:25]:
            print(f"      {a['text']}  ->  {a['href']}")

        # Try the JSON listing API for several pages / categories
        print("[3] JSON listing API...")
        base = "https://sitioprivado.cnd.com.pa"
        api_tpl = (base + "/Informe/GetListOperativosComerciales"
                   "?page={page}&tipo={tipo}&categoria={categoria}"
                   "&anio=null&mes=0&semana=0&publico=0")
        found = {}
        for tipo in (0, 1, 2):
            for pg in (1, 2, 3):
                url = api_tpl.format(page=pg, tipo=tipo, categoria=0)
                try:
                    resp = await ctx.request.get(url)
                    if resp.status != 200:
                        continue
                    data = await resp.json()
                    (OUT / f"api_t{tipo}_p{pg}.json").write_text(
                        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
                    # harvest any download urls found in the json
                    text = json.dumps(data)
                    import re
                    for m in re.findall(r"[^\"']*?[^\s\"']*?\.(?:xlsx|xls|csv|txt|zip)", text, re.I):
                        found[Path(m).suffix.lower()] = found.get(Path(m).suffix.lower(), 0) + 1
                    print(f"    tipo={tipo} page={pg} -> status {resp.status}")
                except Exception as e:
                    print(f"    tipo={tipo} page={pg} -> ERR {e}")
        print(f"[4] extensions seen in API JSON: {found}")

        await browser.close()
    print("\nDONE. Revisa ./recon/")


if __name__ == "__main__":
    asyncio.run(main())
