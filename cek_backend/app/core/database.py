# -*- coding: utf-8 -*-
"""Motor y sesion de base de datos (MariaDB hoy, portable a SQL Server despues)."""
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_recycle=3600,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


class Base(DeclarativeBase):
    """Base declarativa de todos los modelos."""


def get_db():
    """Dependencia de FastAPI: entrega una sesion y la cierra al terminar."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
