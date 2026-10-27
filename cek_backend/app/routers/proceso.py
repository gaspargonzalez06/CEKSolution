# -*- coding: utf-8 -*-
"""Proceso masivo: credenciales de los 14 agentes + descarga/importacion CND."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_roles
from app.models import Usuario
from app.services import proceso

router = APIRouter(prefix="/proceso", tags=["Proceso masivo"])
solo_admin = require_roles("admin")
operacion = require_roles("admin", "operador")


@router.get("/credenciales")
def credenciales(db: Session = Depends(get_db), _: Usuario = Depends(solo_admin)):
    """Estado de credenciales de los 14 agentes gestionados (sin contrasenas)."""
    return proceso.credenciales_estado(db)


@router.post("/credenciales")
def guardar_credenciales(
    payload: dict,
    db: Session = Depends(get_db),
    _: Usuario = Depends(solo_admin),
):
    """Carga credenciales en lote.

    Body:
      {"filas": [{"codigo": "CSOLAR", "usuario": "CSOLAR", "password": "..."}]}
      o bien
      {"texto": "CSOLAR,CSOLAR,clave\\nDECASOLAR,DECASOLAR,clave2"}
    """
    filas = payload.get("filas") or []
    if not filas and payload.get("texto"):
        filas = proceso.parsear_texto(payload["texto"])
    if not filas:
        raise HTTPException(400, "No se recibieron credenciales (filas o texto)")
    return proceso.guardar_credenciales(db, filas)


@router.get("/periodos")
def periodos(db: Session = Depends(get_db), _: Usuario = Depends(operacion)):
    return {"periodos": proceso.periodos_disponibles(db)}


@router.get("/plan")
def plan(db: Session = Depends(get_db), _: Usuario = Depends(operacion)):
    """Diagnostico: ruta del scraper, interpretes y agentes configurados."""
    estado = proceso.credenciales_estado(db)
    return {
        "scraper": str(proceso.SCRAPER),
        "existe_scraper": proceso.SCRAPER.exists(),
        "python_scraper": proceso.PYTHON_SCRAPER,
        "python_backend": proceso.PYTHON_BACKEND,
        "total": estado["total"],
        "configurados": estado["configurados"],
        "pendientes": estado["pendientes"],
        "agentes": estado["agentes"],
    }


@router.post("/ejecutar")
def ejecutar(
    payload: dict,
    db: Session = Depends(get_db),
    _: Usuario = Depends(operacion),
):
    """Lanza el proceso en segundo plano y devuelve el id de la corrida.

    Body: {"periodo": "202609", "codigos": ["BRILLOSOL", ...], "meses": 2,
           "modo": "completo" | "descarga" | "importar",
           "perfil": "esencial" | "facturacion" | "sustentos" | "todo"}
    """
    try:
        return proceso.lanzar_lote(
            db,
            periodo=(payload.get("periodo") or "").strip() or None,
            codigos=payload.get("codigos"),
            meses=int(payload.get("meses") or 2),
            modo=(payload.get("modo") or "completo").strip(),
            perfil=(payload.get("perfil") or "esencial").strip(),
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    except RuntimeError as exc:
        raise HTTPException(409, str(exc))


@router.get("/ejecuciones")
def ejecuciones(
    limite: int = 10,
    db: Session = Depends(get_db),
    _: Usuario = Depends(operacion),
):
    return proceso.ultimas(db, max(1, min(limite, 50)))


@router.get("/ejecuciones/{run_id}")
def ejecucion(
    run_id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(operacion),
):
    run = proceso.estado_ejecucion(db, run_id)
    if run is None:
        raise HTTPException(404, "Ejecucion no encontrada")
    return run
