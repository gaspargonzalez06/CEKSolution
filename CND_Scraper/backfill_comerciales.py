# -*- coding: utf-8 -*-
"""Backfill comercial: baja DTE Tabular + DTER Oficial de todos los agentes
gestionados para N meses hacia atras, secuencial (el que ya estaba en raw
se salta solo). Solo descarga RAW; la importacion a la BD corre aparte con
los importadores.

Uso:  python backfill_comerciales.py --hasta-mes 202609 --meses 21
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BASE = Path(__file__).resolve().parent
BACKEND = BASE.parent / "cek_backend"
os.chdir(BACKEND)  # para que config.py encuentre el .env
sys.path.insert(0, str(BACKEND))

from app.core.database import SessionLocal  # noqa: E402
from app.models import Agente, AgenteCredencial  # noqa: E402
from app.services.crypto import descifrar  # noqa: E402

PYTHON = sys.executable  # mismo python que corre este script


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hasta-mes", default="")
    ap.add_argument("--meses", type=int, default=21)
    ap.add_argument("--agente", default="", help="solo un agente (codigo)")
    args = ap.parse_args()

    with SessionLocal() as db:
        rows = (
            db.query(Agente, AgenteCredencial)
            .join(AgenteCredencial, AgenteCredencial.id_agente == Agente.id)
            .filter(Agente.gestionado.is_(True), Agente.activo.is_(True))
            .order_by(Agente.codigo)
            .all()
        )

    agentes = []
    for ag, cred in rows:
        pw = descifrar(cred.password_portal_enc)
        if not cred.usuario_portal or not pw:
            print(f"[SKIP] {ag.codigo}: sin credencial utilizable")
            continue
        agentes.append((ag.codigo, cred.usuario_portal, pw))

    if args.agente:
        agentes = [a for a in agentes if a[0].strip().upper() == args.agente.strip().upper()]

    print(f"[BACKFILL] {len(agentes)} agentes x {args.meses} meses (hasta {args.hasta_mes or 'hoy'})")
    t0 = time.time()
    for i, (codigo, usuario, pw) in enumerate(agentes, 1):
        print(f"\n{'=' * 64}\n[{i}/{len(agentes)}] {codigo}  ({time.time() - t0:.0f}s)")
        cmd = [
            PYTHON,
            str(BASE / "cnd_sync.py"),
            "--user", usuario,
            "--password", pw,
            "--perfil", "facturacion",
            "--tipos", "dte tabular,dter oficial",
            "--meses", str(args.meses),
        ]
        if args.hasta_mes:
            cmd += ["--hasta-mes", args.hasta_mes]
        try:
            r = subprocess.run(cmd, cwd=str(BASE))
            estado = "OK" if r.returncode == 0 else f"exit={r.returncode}"
        except Exception as exc:
            estado = f"ERROR {exc}"
        print(f"[{i}/{len(agentes)}] {codigo}: {estado}  ({time.time() - t0:.0f}s)")

    print(f"\n[FIN] {time.time() - t0:.0f}s total")


if __name__ == "__main__":
    main()
