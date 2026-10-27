# -*- coding: utf-8 -*-
"""Configuracion central leida desde variables de entorno / archivo .env."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "CEK API"
    app_version: str = "0.1.0"

    # Base de datos
    db_host: str = "127.0.0.1"
    db_port: int = 3306
    db_user: str = "root"
    db_password: str = ""
    db_name: str = "cek"

    # Seguridad
    jwt_secret: str = "cambia-esto"
    jwt_alg: str = "HS256"
    jwt_minutes: int = 480
    fernet_key: str = ""

    # Admin inicial
    admin_user: str = "admin"
    admin_password: str = "admin123"

    cors_origins: str = "*"

    # Automatizacion (scraper CND)
    scraper_dir: str = ""          # vacio = ../CND_Scraper
    scraper_python: str = "python"  # interprete con Playwright/pandas instalados

    @property
    def database_url(self) -> str:
        return (
            f"mysql+pymysql://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}?charset=utf8mb4"
        )

    @property
    def cors_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
