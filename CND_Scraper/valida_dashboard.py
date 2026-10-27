# -*- coding: utf-8 -*-
"""Valida el dashboard con Playwright: errores de consola + screenshot."""
import sys, os
from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(errors="replace")
BASE = os.path.dirname(os.path.abspath(__file__))
URL = "file:///" + os.path.join(BASE, "dashboard.html").replace("\\", "/")

errors, logs = [], []
with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    pg = b.new_page(viewport={"width": 1440, "height": 1000})
    pg.on("console", lambda m: logs.append((m.type, m.text)))
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(URL, wait_until="load")
    pg.wait_for_timeout(2800)
    charts = pg.evaluate("Object.keys(Chart.instances||{}).length")
    canv = pg.evaluate("[...document.querySelectorAll('canvas')].filter(c=>c.width>0).length")
    pg.screenshot(path=os.path.join(BASE, "dashboard_preview.png"), full_page=True)
    b.close()

print("pageerrors:", errors or "ninguno")
print("console errors/warnings:", [l for l in logs if l[0] in ("error", "warning")] or "ninguno")
print("charts instanciados:", charts, "| canvas con contenido:", canv)
print("screenshot: dashboard_preview.png")
