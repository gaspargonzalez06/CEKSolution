# -*- coding: utf-8 -*-
"""Proceso masivo: descarga del CND para los 14 agentes + importacion + resumen.

Flujo (lo que hace el boton "Ejecutar" de la app):

    1. Por cada agente gestionado con credenciales:
         scraper  ->  CND_Scraper/cnd_sync.py --user ... --password ...
         (guarda los crudos en CND_Scraper/raw/<AGENTE>/... y en raw_data)
    2. Importa a MariaDB (una sola vez, al final):
         importar_mediciones.py, importar_dte.py, importar_dter.py,
         importar_mediciones_diarias.py
    3. Recalcula las tablas resumen del mercado (sustento_*_resumen).

El avance se guarda en `proceso_ejecuciones.detalle` (JSON) para que la app lo
pueda consultar mientras corre. No se solapan dos corridas.
"""
from __future__ import annotations

import json
import subprocess
import sys
import threading
import traceback
from datetime import datetime
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal, engine
from app.core.universo import UNIVERSO_CODIGOS
from app.models import Agente, AgenteCredencial, ProcesoEjecucion
from app.services import resumen as resumen_svc
from app.services.crypto import cifrar, descifrar
from app.services.facturas import clientes_del_agente

# --------------------------------------------------------------------------- #
# Rutas / interpretes
# --------------------------------------------------------------------------- #
BASE_DIR = Path(__file__).resolve().parents[3]          # AnalisisDescarga
BACKEND_DIR = Path(__file__).resolve().parents[2]       # cek_backend
SCRAPER_DIR = Path(settings.scraper_dir) if settings.scraper_dir else BASE_DIR / "CND_Scraper"
SCRAPER = SCRAPER_DIR / "cnd_sync.py"
PYTHON_SCRAPER = settings.scraper_python or "python"
PYTHON_BACKEND = sys.executable

IMPORTADORES = (
    ("mediciones", "importar_mediciones.py"),
    ("dte", "importar_dte.py"),
    ("dter", "importar_dter.py"),
    ("diarias", "importar_mediciones_diarias.py"),
)
# Carga los reporte_totales (sustentos) a sustento_horario. Vive en CND_Scraper
# porque usa pymysql + el config.yaml del scraper.
SUSTENTO_SCRIPT = "extraer_sustento.py"

# Perfiles de descarga (secciones definidas en CND_Scraper/cnd_sync.py).
_PERFIL_ALIAS = {
    "esencial": ["facturacion", "sustento_unificado"],
    "facturacion": ["facturacion"],
    "sustentos": ["sustento_unificado"],
    "todo": ["todo"],
}

# Una sola corrida a la vez (el scraper abre navegador y escribe en la BD).
_LOCK = threading.Lock()
_TIEMPO_AGENTE = 60 * 45      # 45 min por agente
_TIEMPO_IMPORT = 60 * 20      # 20 min por importador


# --------------------------------------------------------------------------- #
# Utilidades
# --------------------------------------------------------------------------- #
def _ejecutar(cmd: list[str], cwd: Path, timeout: int) -> dict:
    """Corre un comando y devuelve un resumen (nunca lanza por error del hijo)."""
    try:
        p = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        salida = ((p.stdout or "") + "\n" + (p.stderr or "")).strip()
        return {"ok": p.returncode == 0, "codigo": p.returncode, "salida": salida[-4000:]}
    except subprocess.TimeoutExpired:
        return {"ok": False, "codigo": -1, "salida": f"Tiempo agotado ({timeout}s)"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "codigo": -2, "salida": f"{type(exc).__name__}: {exc}"}


def _json(txt: str | None, defecto):
    if not txt:
        return defecto
    try:
        return json.loads(txt)
    except Exception:
        return defecto


def _progreso(run: ProcesoEjecucion, detalle: list[dict]) -> dict:
    """Avance real de la corrida: pasos hechos / total, porcentaje y etapa.

    Se calcula con el mismo `detalle` que ve la app, de modo que el porcentaje
    y el contador "X de Y" siempre coinciden.
    """
    agentes = _json(run.agentes, []) or []
    modo = (run.modo or "completo").strip()
    n_agentes = len(agentes)
    n_import = len(IMPORTADORES) + 1  # importadores + resumen
    plan = next((d for d in detalle if d.get("codigo") == "__plan__"), None)
    if plan and plan.get("import_esperados"):
        n_import = int(plan["import_esperados"])

    total = 0
    if modo in ("completo", "descarga"):
        total += n_agentes
    if modo in ("completo", "importar"):
        total += n_import

    terminales_agente = {"ok", "error", "sin_credencial", "no_encontrado"}
    hechos = 0
    etapa = "preparando"
    for d in detalle:
        codigo = str(d.get("codigo") or "")
        if codigo.startswith("import:"):
            if d.get("import") in ("ok", "error"):
                hechos += 1
                etapa = "transformar"
        elif codigo == "resumen":
            if d.get("import") in ("ok", "error"):
                hechos += 1
                etapa = "consolidar"
        else:
            if d.get("descarga") in terminales_agente:
                hechos += 1
                etapa = "descargar"
            elif d.get("descarga") == "corriendo":
                etapa = "descargar"

    if run.estado and run.estado != "corriendo":
        etapa = "finalizado"
        porcentaje = 100.0 if run.estado in ("ok", "parcial") else 0.0
    else:
        porcentaje = round(hechos * 100 / total, 1) if total else 0.0

    # Estimacion de tiempo restante (solo si ya hay al menos un paso hecho).
    transcurridos = None
    restantes = None
    try:
        fin = run.fin or datetime.utcnow()
        if run.inicio:
            transcurridos = max(0, int((fin - run.inicio).total_seconds()))
            if 0 < hechos < total and transcurridos > 0:
                restantes = int(transcurridos / hechos * (total - hechos))
    except Exception:
        pass

    return {
        "paso": hechos,
        "total": total,
        "porcentaje": porcentaje,
        "etapa": etapa,
        "segundos_transcurridos": transcurridos,
        "segundos_restantes": restantes,
    }


def _serializar(run: ProcesoEjecucion) -> dict:
    detalle = _json(run.detalle, [])
    return {
        "id": run.id,
        "periodo": run.periodo,
        "modo": run.modo,
        "estado": run.estado,
        "mensaje": run.mensaje,
        "agentes": _json(run.agentes, []),
        "detalle": detalle,
        "progreso": _progreso(run, detalle),
        "inicio": run.inicio.isoformat() if run.inicio else None,
        "fin": run.fin.isoformat() if run.fin else None,
    }


def _guardar(db: Session, run: ProcesoEjecucion, detalle: list) -> None:
    run.detalle = json.dumps(detalle, ensure_ascii=False)
    db.commit()


def perfil_efectivo(perfil: str | None, periodo: str | None, meses: int = 1) -> list[str]:
    """Secciones de descarga que se le piden al scraper.

    - `esencial` = facturacion + sustentos unificados (solo los tipos que usa la app).
    - Si el rango pedido incluye el mes en curso (o no se especifica periodo), se
      agregan los parciales de sustentos: aun no existe el unificado de ese mes.
    """
    clave = (perfil or "esencial").strip().lower()
    secs = list(_PERFIL_ALIAS.get(clave, [s.strip() for s in clave.split(",") if s.strip()]))
    ahora = datetime.now().strftime("%Y%m")
    rango = meses_hasta(periodo, meses) if periodo else []
    if "todo" not in secs and (not periodo or ahora in rango):
        if "sustento_parcial" not in secs:
            secs.append("sustento_parcial")
    return secs


def _incluye_sustentos(secs: list[str]) -> bool:
    return "todo" in secs or any(s.startswith("sustento") for s in secs)


def comando_agente(
    agente: Agente,
    periodo: str | None,
    meses: int,
    perfil: str | None = None,
) -> list[str] | None:
    """Arma el comando del scraper para un agente (None si no esta configurado)."""
    cred = agente.credencial
    if not cred or not cred.activo:
        return None
    usuario = (cred.usuario_portal or "").strip()
    password = descifrar(cred.password_portal_enc)
    if not usuario or not password:
        return None

    cmd = [PYTHON_SCRAPER, str(SCRAPER), "--user", usuario, "--password", password]
    n_meses = max(1, int(meses or 1))
    if periodo:
        # El scraper consulta mes a mes: ancla en el periodo pedido y retrocede N.
        cmd += ["--hasta-mes", periodo, "--meses", str(n_meses)]
    elif n_meses > 0:
        cmd += ["--meses", str(n_meses)]
    cmd += ["--perfil", ",".join(perfil_efectivo(perfil, periodo, n_meses))]
    return cmd


def meses_hasta(periodo: str, meses: int) -> list[str]:
    """Lista de periodos AAAAAM desde `periodo` hacia atras (incluido)."""
    if not periodo or len(periodo) != 6 or not periodo.isdigit():
        return []
    y, m = int(periodo[:4]), int(periodo[4:])
    salida: list[str] = []
    for _ in range(max(1, int(meses or 1))):
        salida.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            m, y = 12, y - 1
    return salida


# --------------------------------------------------------------------------- #
# Credenciales
# --------------------------------------------------------------------------- #
def _agentes_por_codigo(db: Session) -> dict[str, Agente]:
    filas = db.query(Agente).all()
    return {(a.codigo or "").strip().upper(): a for a in filas}


def credenciales_estado(db: Session) -> dict:
    """Estado de credenciales de los 14 agentes (sin devolver contrasenas)."""
    agentes = (
        db.query(Agente)
        .filter(Agente.gestionado.is_(True))
        .order_by(Agente.codigo)
        .all()
    )
    filas = []
    for a in agentes:
        c = a.credencial
        tiene = bool(c and (c.usuario_portal or "").strip() and c.password_portal_enc)
        filas.append(
            {
                "id": a.id,
                "codigo": a.codigo,
                "nombre": a.nombre,
                "usuario": c.usuario_portal if c else None,
                "tiene_password": bool(c and c.password_portal_enc),
                "activo": bool(c and c.activo),
                "configurado": bool(tiene and c and c.activo),
                "ultimo_login": c.ultimo_login.isoformat() if c and c.ultimo_login else None,
                "clientes": len(clientes_del_agente(db, a.id)),
            }
        )
    return {
        "total": len(filas),
        "configurados": sum(1 for f in filas if f["configurado"]),
        "pendientes": sum(1 for f in filas if not f["configurado"]),
        "agentes": filas,
    }


def parsear_texto(texto: str) -> list[dict]:
    """Parsea lineas `CODIGO usuario password` (coma, punto y coma, tab o espacios).

    Tambien acepta solo `CODIGO` + `password` (el usuario por defecto es el codigo).
    Ignora lineas vacias y las que empiezan por #.
    """
    filas: list[dict] = []
    for linea in (texto or "").splitlines():
        linea = linea.strip().strip("\ufeff")
        if not linea or linea.startswith("#"):
            continue
        if "," in linea:
            partes = [p.strip() for p in linea.split(",")]
        elif ";" in linea:
            partes = [p.strip() for p in linea.split(";")]
        elif "\t" in linea:
            partes = [p.strip() for p in linea.split("\t")]
        else:
            partes = linea.split()
        partes = [p.strip().strip('"').strip("'") for p in partes if p.strip()]
        if len(partes) < 2:
            continue
        codigo = partes[0].upper()
        if len(partes) == 2:
            filas.append({"codigo": codigo, "usuario": codigo, "password": partes[1]})
        else:
            filas.append({"codigo": codigo, "usuario": partes[1], "password": partes[2]})
    return filas


def guardar_credenciales(db: Session, filas: list[dict]) -> dict:
    """Carga/actualiza credenciales en lote. Devuelve el resumen."""
    por_codigo = _agentes_por_codigo(db)
    ok, errores = 0, []
    for f in filas:
        codigo = (f.get("codigo") or "").strip().upper()
        if not codigo:
            continue
        agente = por_codigo.get(codigo)
        if agente is None:
            errores.append({"codigo": codigo, "error": "Agente no encontrado"})
            continue

        usuario = (f.get("usuario") or f.get("usuario_portal") or codigo).strip()
        password = f.get("password") or f.get("password_portal")
        if f.get("activo", True) and not password:
            errores.append({"codigo": codigo, "error": "Falta la contrasena"})
            continue

        cred = agente.credencial
        if cred is None:
            cred = AgenteCredencial(id_agente=agente.id)
            db.add(cred)
        cred.usuario_portal = usuario or codigo
        if password:
            cred.password_portal_enc = cifrar(password)
        cred.activo = bool(f.get("activo", True))

        # Solo se marca gestionado si pertenece al universo de CEK.
        if codigo in UNIVERSO_CODIGOS:
            agente.gestionado = True

        ok += 1

    db.commit()
    return {"ok": ok, "errores": errores, "total": len(filas)}


# --------------------------------------------------------------------------- #
# Ejecucion
# --------------------------------------------------------------------------- #
def _hay_corriendo(db: Session) -> ProcesoEjecucion | None:
    return (
        db.query(ProcesoEjecucion)
        .filter(ProcesoEjecucion.estado == "corriendo")
        .order_by(ProcesoEjecucion.id.desc())
        .first()
    )


def lanzar_lote(
    db: Session,
    *,
    periodo: str | None = None,
    codigos: list[str] | None = None,
    meses: int = 2,
    modo: str = "completo",
    perfil: str = "esencial",
) -> dict:
    """Registra la corrida y la ejecuta en segundo plano."""
    if modo not in ("completo", "descarga", "importar"):
        raise ValueError("modo debe ser completo, descarga o importar")
    if _LOCK.locked() or _hay_corriendo(db):
        raise RuntimeError("Ya hay un proceso en ejecucion. Espera a que termine.")

    gestionados = (
        db.query(Agente)
        .filter(Agente.gestionado.is_(True))
        .order_by(Agente.codigo)
        .all()
    )
    if codigos:
        pedidos = {c.strip().upper() for c in codigos if c and c.strip()}
        seleccion = [a for a in gestionados if (a.codigo or "").upper() in pedidos]
    else:
        seleccion = gestionados

    run = ProcesoEjecucion(
        periodo=periodo or None,
        modo=modo,
        estado="corriendo",
        agentes=json.dumps([a.codigo for a in seleccion], ensure_ascii=False),
        detalle="[]",
    )
    db.add(run)
    db.commit()
    db.refresh(run)

    threading.Thread(
        target=_trabajo,
        args=(run.id, periodo or None, [a.codigo for a in seleccion], meses, modo, perfil),
        daemon=True,
    ).start()
    return {"id": run.id, "estado": "corriendo", "agentes": len(seleccion)}


def _trabajo(run_id: int, periodo: str | None, codigos: list[str], meses: int,
             modo: str, perfil: str = "esencial") -> None:
    with _LOCK:
        db = SessionLocal()
        run = None
        try:
            run = db.get(ProcesoEjecucion, run_id)
            if run is None:
                return
            detalle: list[dict] = []
            secs = perfil_efectivo(perfil, periodo, meses)
            correr_sustentos = _incluye_sustentos(secs) and bool(periodo)

            # Plan de la corrida: fija el total de pasos para el % de avance.
            if modo in ("completo", "importar"):
                pasos_import = len(IMPORTADORES) + 1  # importadores + resumen
                if correr_sustentos:
                    pasos_import += 1
                detalle.append(
                    {
                        "codigo": "__plan__",
                        "import_esperados": pasos_import,
                        "perfil": ",".join(secs),
                    }
                )
                _guardar(db, run, detalle)

            # ---------- 1) Descarga por agente ----------
            if modo in ("completo", "descarga"):
                por_codigo = _agentes_por_codigo(db)
                for codigo in codigos:
                    agente = por_codigo.get(codigo.upper())
                    item = {
                        "codigo": codigo,
                        "nombre": agente.nombre if agente else None,
                        "descarga": "pendiente",
                        "import": "pendiente",
                        "salida": "",
                    }
                    detalle.append(item)
                    _guardar(db, run, detalle)

                    if agente is None:
                        item["descarga"] = "no_encontrado"
                        _guardar(db, run, detalle)
                        continue

                    cmd = comando_agente(agente, periodo, meses, perfil)
                    if cmd is None:
                        item["descarga"] = "sin_credencial"
                        _guardar(db, run, detalle)
                        continue

                    item["descarga"] = "corriendo"
                    _guardar(db, run, detalle)
                    r = _ejecutar(cmd, SCRAPER_DIR, _TIEMPO_AGENTE)
                    item["descarga"] = "ok" if r["ok"] else "error"
                    item["salida"] = r["salida"][-2000:]
                    if r["ok"]:
                        cred = agente.credencial
                        if cred is not None:
                            cred.ultimo_login = datetime.utcnow()
                    _guardar(db, run, detalle)

            # ---------- 2) Importacion ----------
            if modo in ("completo", "importar"):
                for paso, script in IMPORTADORES:
                    cmd = [PYTHON_BACKEND, str(BACKEND_DIR / script)]
                    if periodo:
                        cmd += ["--periodo", periodo]
                    r = _ejecutar(cmd, BACKEND_DIR, _TIEMPO_IMPORT)
                    detalle.append(
                        {
                            "codigo": f"import:{paso}",
                            "descarga": "omitido",
                            "import": "ok" if r["ok"] else "error",
                            "salida": r["salida"][-2000:],
                        }
                    )
                    _guardar(db, run, detalle)

                # Sustentos (reporte_totales -> sustento_horario). Unificado para
                # meses cerrados; incluye parciales si el periodo es el mes en curso.
                if correr_sustentos:
                    periodos_sustento = meses_hasta(periodo, meses)
                    cmd = [
                        PYTHON_SCRAPER,
                        str(SCRAPER_DIR / SUSTENTO_SCRIPT),
                        "--periodos", ",".join(periodos_sustento),
                        # Meses cerrados: basta el unificado. El mes en curso
                        # conserva todos sus parciales (ver solo_unificados()).
                        "--solo-unificado",
                    ]
                    r = _ejecutar(cmd, SCRAPER_DIR, _TIEMPO_IMPORT)
                    detalle.append(
                        {
                            "codigo": "import:sustentos",
                            "descarga": "omitido",
                            "import": "ok" if r["ok"] else "error",
                            "salida": r["salida"][-2000:],
                        }
                    )
                    _guardar(db, run, detalle)

            # ---------- 3) Resumen ----------
            if modo in ("completo", "importar"):
                try:
                    with engine.begin() as conn:
                        resumen_svc.refrescar(conn)
                    detalle.append(
                        {
                            "codigo": "resumen",
                            "descarga": "omitido",
                            "import": "ok",
                            "salida": "Tablas resumen recalculadas",
                        }
                    )
                except Exception as exc:  # noqa: BLE001
                    detalle.append(
                        {
                            "codigo": "resumen",
                            "descarga": "omitido",
                            "import": "error",
                            "salida": f"{type(exc).__name__}: {exc}",
                        }
                    )
                _guardar(db, run, detalle)

            fallos = [
                d for d in detalle
                if d.get("descarga") == "error" or d.get("import") == "error"
            ]
            run.estado = "ok" if not fallos else "parcial"
            if fallos:
                run.mensaje = f"{len(fallos)} paso(s) con error"
        except Exception:  # noqa: BLE001
            if run is not None:
                run.estado = "error"
                run.mensaje = traceback.format_exc()[-4000:]
        finally:
            if run is not None:
                run.fin = datetime.utcnow()
                db.commit()
            db.close()


def estado_ejecucion(db: Session, run_id: int) -> dict | None:
    run = db.get(ProcesoEjecucion, run_id)
    return _serializar(run) if run else None


def ultimas(db: Session, limite: int = 10) -> list[dict]:
    filas = (
        db.query(ProcesoEjecucion)
        .order_by(ProcesoEjecucion.id.desc())
        .limit(limite)
        .all()
    )
    return [_serializar(r) for r in filas]


def periodos_disponibles(db: Session) -> list[str]:
    """Periodos con datos (para el selector de la app), mas recientes primero."""
    from sqlalchemy import text

    vistos: set[str] = set()
    for sql in (
        "SELECT DISTINCT periodo FROM mediciones",
        "SELECT DISTINCT periodo FROM dte",
        "SELECT DISTINCT periodo FROM raw_data",
        "SELECT DISTINCT periodo FROM sustento_version_resumen",
    ):
        try:
            for (p,) in db.execute(text(sql)).fetchall():
                p = str(p or "").strip()
                if len(p) == 6 and p.isdigit() and 1 <= int(p[4:]) <= 12:
                    vistos.add(p)
        except Exception:
            continue
    return sorted(vistos, reverse=True)
