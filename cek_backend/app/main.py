# -*- coding: utf-8 -*-
"""CEK API - punto de entrada."""
import logging
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pathlib import Path

from app.core.bootstrap import init_db
from app.core.config import settings
from app.services.resumen import refrescar_si_vacio
from app.routers import (
    agentes,
    ajustes,
    analisis,
    auth,
    automatizacion,
    clientes,
    contratos,
    dashboard,
    distribuidores,
    facturas,
    facturas_historicas,
    precios,
    proceso,
    reclamaciones,
    usuarios,
)

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("cek")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    # Genera las tablas resumen del mercado si faltan (en segundo plano, no bloquea).
    threading.Thread(target=_resumen_seguro, daemon=True).start()
    log.info("CEK API lista.")
    yield


def _resumen_seguro():
    try:
        refrescar_si_vacio()
    except Exception as exc:  # pragma: no cover - solo informativo
        log.warning("No se pudieron preparar las tablas resumen: %s", exc)


app = FastAPI(title=settings.app_name, version=settings.app_version, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (auth, usuarios, agentes, distribuidores, clientes, contratos, precios, reclamaciones, ajustes, facturas, facturas_historicas, dashboard, analisis, automatizacion, proceso):
    app.include_router(r.router)


@app.get("/api", tags=["Sistema"])
def api_root():
    return {"app": settings.app_name, "version": settings.app_version, "docs": "/docs"}

@app.get("/health", tags=["Sistema"])
def health():
    return {"status": "ok"}

# Servir el build de Flutter (web) en la raiz. Se monta AL FINAL para que las
# rutas de la API (/auth, /facturas, ...) tengan prioridad sobre los archivos
# estaticos.
STATIC_DIR = Path(__file__).resolve().parent.parent / "static" / "web"
if STATIC_DIR.exists():
    app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")
