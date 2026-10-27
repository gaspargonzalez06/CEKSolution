# -*- coding: utf-8 -*-
"""Arranque de la base de datos: crea tablas y el usuario admin inicial."""
import logging

from sqlalchemy import inspect, text

from app.core.config import settings
from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app.models import Agente, Usuario  # noqa: F401 (registra los modelos)

log = logging.getLogger("cek.bootstrap")


def _preparar_tabla_agentes():
    """La tabla 'agentes' ya existia (esquema viejo, vacia). Si le faltan columnas
    nuevas, y esta vacia, la recreamos para que coincida con el modelo."""
    inspector = inspect(engine)
    if "agentes" not in inspector.get_table_names():
        return
    columnas = {c["name"] for c in inspector.get_columns("agentes")}
    if "codigo_cnd" in columnas:
        return
    with engine.begin() as conn:
        total = conn.execute(text("SELECT COUNT(*) FROM agentes")).scalar()
        if total:
            raise RuntimeError(
                "La tabla 'agentes' no coincide con el modelo y tiene datos. "
                "Migre manualmente (ALTER TABLE) antes de continuar."
            )
        conn.execute(text("DROP TABLE agentes"))
    log.info("Tabla 'agentes' vacia del esquema viejo: recreada con el modelo nuevo.")


def _sincronizar_universo():
    """Asegura que los 14 agentes del universo queden marcados como gestionados.

    Es idempotente y NO borra marcas manuales: solo enciende los codigos del
    universo (por si se agregan/quitan credenciales). Asi, si el usuario marca
    un agente nuevo desde la app, se conserva. Agrega la columna si la tabla
    venia de un esquema anterior sin ella.
    """
    from app.core.universo import UNIVERSO_CODIGOS

    inspector = inspect(engine)
    if "agentes" not in inspector.get_table_names():
        return
    columnas = {c["name"] for c in inspector.get_columns("agentes")}
    with engine.begin() as conn:
        if "gestionado" not in columnas:
            conn.execute(
                text("ALTER TABLE agentes ADD COLUMN gestionado TINYINT(1) NOT NULL DEFAULT 0")
            )
            log.info("Columna 'gestionado' agregada a agentes.")
        for codigo in sorted(UNIVERSO_CODIGOS):
            conn.execute(
                text("UPDATE agentes SET gestionado = 1 WHERE UPPER(codigo) = :c"),
                {"c": codigo},
            )
    log.info("Universo de agentes gestionados sincronizado (%d).", len(UNIVERSO_CODIGOS))


def _migrar_columnas():
    """Agrega columnas nuevas a tablas que ya existian (create_all no las agrega)."""
    inspector = inspect(engine)
    tablas = set(inspector.get_table_names())
    if "contratos" in tablas:
        cols = {c["name"] for c in inspector.get_columns("contratos")}
        if "id_antiguo" not in cols:
            with engine.begin() as conn:
                conn.execute(text("ALTER TABLE contratos ADD COLUMN id_antiguo INT NULL"))
            log.info("Columna 'id_antiguo' agregada a contratos.")
    if "facturas" in tablas:
        cols = {c["name"] for c in inspector.get_columns("facturas")}
        if "graficas" not in cols:
            with engine.begin() as conn:
                conn.execute(text("ALTER TABLE facturas ADD COLUMN graficas VARCHAR(60) NULL"))
            log.info("Columna 'graficas' agregada a facturas.")


def init_db():
    _preparar_tabla_agentes()
    Base.metadata.create_all(bind=engine)
    _migrar_columnas()
    _sincronizar_universo()
    _crear_admin()


def _crear_admin():
    db = SessionLocal()
    try:
        existe = db.query(Usuario).filter(Usuario.usuario == settings.admin_user).first()
        if not existe:
            db.add(
                Usuario(
                    usuario=settings.admin_user,
                    nombre="Administrador",
                    rol="admin",
                    activo=True,
                    password_hash=hash_password(settings.admin_password),
                )
            )
            db.commit()
            log.info("Usuario admin '%s' creado.", settings.admin_user)
    finally:
        db.close()
