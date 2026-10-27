# -*- coding: utf-8 -*-
"""Actualiza nombres/RUC/NIS de clientes desde el export del sistema viejo
(contratos_antiguos.tsv) y completa los datos de contacto conocidos.
"""
import csv
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import text  # noqa: E402

from app.core.database import engine  # noqa: E402

TSV = Path(__file__).resolve().parent.parent / "CND_Flow_Explorer" / "contratos_antiguos.tsv"

# datos de contacto que el sistema viejo mostraba y que no vienen en el tsv
EXTRA = {
    "GCP0721": {"direccion": "Punta Pacífica, Multiplaza Pacific Panamá",
                "telefono": "6616-7755", "contacto": "Rafael Samudio Castillo"},
}

mapa = {}
with TSV.open(encoding="utf-8-sig", newline="") as fh:
    for r in csv.DictReader(fh, delimiter="\t"):
        cod = (r.get("cliente_codigo") or "").strip()
        nom = (r.get("cliente_nombre") or "").strip()
        if cod and nom and cod not in mapa:
            mapa[cod] = {"nombre": nom, "ruc": (r.get("cliente_ruc") or "").strip(),
                         "nis": (r.get("cliente_nis") or "").strip()}

with engine.begin() as cn:
    for id_, cod, nom in cn.execute(text("SELECT id, codigo, nombre FROM clientes")).all():
        d = mapa.get(cod)
        if not d:
            print("sin match tsv:", cod, nom)
            continue
        sets = ["nombre=:n"]
        p = {"n": d["nombre"], "id": id_}
        if d["ruc"]:
            sets.append("ruc=:r"); p["r"] = d["ruc"]
        if d["nis"]:
            sets.append("nis=:ni"); p["ni"] = d["nis"]
        for k, v in EXTRA.get(cod, {}).items():
            sets.append(f"{k}=:{k}"); p[k] = v
        cn.execute(text("UPDATE clientes SET " + ",".join(sets) + " WHERE id=:id"), p)
        print("%-10s -> %s" % (cod, d["nombre"]))

print("[ok] clientes actualizados")
