# -*- coding: utf-8 -*-
"""Prueba end-to-end de la API: login, dashboard, generar factura y ver HTML."""
import json
import sys
import urllib.parse
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:8000"


def req(metodo, path, token=None, body=None, raw=False):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    r = urllib.request.Request(url, data=data, headers=headers, method=metodo)
    with urllib.request.urlopen(r) as resp:
        txt = resp.read().decode("utf-8")
        return txt if raw else json.loads(txt)


# login
form = urllib.parse.urlencode({"username": "admin", "password": "admin123"}).encode()
r = urllib.request.Request(BASE + "/auth/login", data=form,
                           headers={"Content-Type": "application/x-www-form-urlencoded"})
with urllib.request.urlopen(r) as resp:
    token = json.loads(resp.read())["access_token"]
print("login OK")

dash = req("GET", "/dashboard/resumen", token)
print("entidades:", dash["entidades"])
print("facturacion:", dash["facturacion"])
print("subsistemas:", len(dash.get("subsistemas", [])), "mercado:", len(dash["mercado"]))

clientes = req("GET", "/clientes", token)
print("clientes:", [(c["id"], c["codigo"]) for c in clientes])

cli = next(c for c in clientes if c["codigo"] == "GCP0719")
fac = req("POST", "/facturas/generar", token, {
    "id_cliente": cli["id"],
    "periodo": "202609",
    "precio_kwh": 0.0775,
    "consumo_mwh": 2304.009,
    "itbms_pct": 0.0,
    "observaciones": "Prueba de factura generada desde los DTE.",
})
print("factura:", fac["numero"], "subtotal", fac["subtotal"], "total", fac["total"])
for d in fac["detalles"]:
    print("   -", d["descripcion"], d["cantidad"], d["unidad"], d["monto"], "total" if d["es_total"] else "")

html = req("GET", f"/facturas/{fac['id']}/html", raw=True)
print("HTML bytes:", len(html), "tiene svg:", "<svg" in html, "tiene page-break:", "page-break" in html)
with open("factura_prueba.html", "w", encoding="utf-8") as fh:
    fh.write(html)
print("Guardado en cek_backend/factura_prueba.html")

serie = req("GET", f"/facturas/{fac['id']}/consumo", token)
print("serie consumo:", serie)
