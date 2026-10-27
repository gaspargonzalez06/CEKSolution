# -*- coding: utf-8 -*-
"""Prueba del puente de automatizacion y estado actual."""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.stdout.reconfigure(errors="replace")
BASE = "http://127.0.0.1:8000"


def esperar(seg=40):
    for _ in range(seg):
        try:
            urllib.request.urlopen(BASE + "/", timeout=2)
            return True
        except Exception:
            time.sleep(1)
    return False


def req(method, path, token=None, data=None, form=False):
    headers = {}
    body = None
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r) as resp:
            txt = resp.read().decode()
            return resp.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


assert esperar(), "API no responde"
st, tok = req("POST", "/auth/login", data={"username": "admin", "password": "admin123"}, form=True)
token = tok["access_token"]
print(f"login -> {st}\n")

st, agentes = req("GET", "/agentes", token)
print(f"agentes ({st}):")
for a in agentes:
    print(f"   id={a['id']} {a['codigo']} cred={'si' if a['credencial'] else 'no'} gen={a['generador']}")

st, plan = req("GET", "/automatizacion/plan/1", token)
print(f"\nplan automatizacion (agente 1) -> {st}")
print("  ", json.dumps(plan, ensure_ascii=False))

st, plan404 = req("GET", "/automatizacion/plan/999", token)
print(f"plan agente inexistente -> {st} (esperado 404)")

st, dash = req("GET", "/dashboard/resumen", token)
print(f"\ndashboard -> {st}  entidades={dash['entidades']}  mercado={[(m['periodo'], float(m['consumo'])) for m in dash['mercado']]}")
