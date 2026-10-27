# -*- coding: utf-8 -*-
"""Puente entre el backend y la automatizacion (scraper Playwright).

El scraper vive en CND_Scraper/cnd_sync.py. Aqui se construye y (opcionalmente)
se lanza el comando usando las credenciales guardadas del agente.
"""
import os
import subprocess
from datetime import datetime
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Agente
from app.services.crypto import descifrar

# Carpeta del scraper (hermana de cek_backend, salvo que se configure otra)
BASE_DIR = Path(__file__).resolve().parents[3]
SCRAPER_DIR = Path(settings.scraper_dir) if settings.scraper_dir else BASE_DIR / "CND_Scraper"
SCRAPER = SCRAPER_DIR / "cnd_sync.py"
PYTHON = settings.scraper_python


def comando_sync(agente: Agente, ext: str | None = None) -> list[str] | None:
    """Arma la lista de argumentos del scraper para un agente."""
    cred = agente.credencial
    if not cred or not cred.activo:
        return None
    usuario = cred.usuario_portal
    password = descifrar(cred.password_portal_enc)
    if not usuario or not password:
        return None

    cmd = [PYTHON, str(SCRAPER), "--user", usuario, "--password", password]
    if ext:
        cmd += ["--ext", ext]
    return cmd


def plan_sync(agente: Agente, ext: str | None = None) -> dict:
    """Describe que se ejecutaria (sin ejecutarlo). Util para probar/ver."""
    cmd = comando_sync(agente, ext)
    return {
        "agente": agente.codigo,
        "configurado": cmd is not None,
        "python": PYTHON,
        "scraper": str(SCRAPER),
        "existe_scraper": SCRAPER.exists(),
        "argumentos": ["--user", "<usuario>", "--password", "****"] + (["--ext", ext] if ext else []),
    }


def lanzar_sync(agente: Agente, ext: str | None = None) -> dict:
    """Lanza el scraper en segundo plano con las credenciales del agente."""
    cmd = comando_sync(agente, ext)
    if cmd is None:
        return {"ok": False, "detalle": "El agente no tiene credenciales activas"}
    if not SCRAPER.exists():
        return {"ok": False, "detalle": f"No se encontro el scraper en {SCRAPER}"}

    log_dir = SCRAPER_DIR / "logs"
    log_dir.mkdir(exist_ok=True)
    log = log_dir / f"sync_{agente.codigo}_{datetime.now():%Y%m%d_%H%M%S}.log"

    with open(log, "w", encoding="utf-8") as fh:
        proc = subprocess.Popen(
            cmd,
            cwd=str(SCRAPER_DIR),
            stdout=fh,
            stderr=subprocess.STDOUT,
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        )
    if agente.credencial:
        agente.credencial.ultimo_login = datetime.utcnow()
    return {"ok": True, "pid": proc.pid, "log": str(log)}


def marcar_login(db: Session, agente: Agente) -> None:
    if agente.credencial:
        agente.credencial.ultimo_login = datetime.utcnow()
        db.commit()
