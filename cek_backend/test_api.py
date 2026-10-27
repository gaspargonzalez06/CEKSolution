# -*- coding: utf-8 -*-
"""Prueba end-to-end de la API (login -> crear agente con clave -> dashboard)."""
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


assert esperar(), "La API no respondio"
print("API arriba.\n")

# 1) Login admin
st, tok = req("POST", "/auth/login", data={"username": "admin", "password": "admin123"}, form=True)
assert st == 200, (st, tok)
token = tok["access_token"]
print(f"1) login admin           -> {st}  rol={tok['usuario']['rol']}")

# 2) /auth/me
st, me = req("GET", "/auth/me", token)
print(f"2) /auth/me              -> {st}  {me['usuario']}")

# 3) Crear agente CON credenciales
nuevo = {
    "nombre": "Generadora Brillo Solar, S.A.",
    "codigo": "BRILLOSOL",
    "codigo_cnd": "BRILLOSOL",
    "generador": True,
    "distribuidor": False,
    "credencial": {"usuario_portal": "BRILLOSOL", "password_portal": "bF50koniaR0=", "activo": True},
}
st, ag = req("POST", "/agentes", token, nuevo)
print(f"3) crear agente          -> {st}  {ag if st!=201 else ag['codigo']+' (id '+str(ag['id'])+')'}")
agente_id = ag["id"] if st == 201 else None

# 4) Ver credencial (no debe traer password)
if agente_id:
    st, cred = req("GET", f"/agentes/{agente_id}/credencial", token)
    print(f"4) ver credencial        -> {st}  usuario_portal={cred.get('usuario_portal')}  password_en_respuesta={'password' in (cred or {})}")

# 5) Crear usuario cliente
st, u = req("POST", "/usuarios", token, {"usuario": "cliente1", "nombre": "Cliente Demo", "rol": "cliente", "password": "cliente123"})
print(f"5) crear usuario cliente -> {st}  {u if st==201 else u}")

# 6) Login del cliente y chequeo de permisos (no debe poder crear agentes)
st2, tok2 = req("POST", "/auth/login", data={"username": "cliente1", "password": "cliente123"}, form=True)
st3, _ = req("POST", "/agentes", tok2["access_token"], {"codigo": "X1"})
print(f"6) cliente intenta crear -> {st3} (esperado 403)")

# 7) Listar agentes
st, lista = req("GET", "/agentes", token)
print(f"7) listar agentes        -> {st}  total={len(lista)}")

# 8) Dashboard
st, dash = req("GET", "/dashboard/resumen", token)
print(f"8) dashboard/resumen     -> {st}")
if st == 200:
    print("   entidades:", dash["entidades"])
    print("   reclamaciones:", dash["reclamaciones"]["total"])
    print("   mercado:", [(m['periodo'], float(m['consumo'])) for m in dash["mercado"]])
