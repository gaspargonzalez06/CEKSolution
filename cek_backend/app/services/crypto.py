# -*- coding: utf-8 -*-
"""Cifrado simetrico de las claves de los agentes (Fernet)."""
import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


def generar_key() -> str:
    """Genera una FERNET_KEY nueva (base64 urlsafe de 32 bytes)."""
    return Fernet.generate_key().decode()


def _fernet() -> Fernet:
    key = settings.fernet_key
    if not key:
        # Respaldo de desarrollo: deriva la clave del JWT_SECRET.
        derivada = hashlib.sha256(settings.jwt_secret.encode("utf-8")).digest()
        key = base64.urlsafe_b64encode(derivada).decode()
    return Fernet(key.encode())


def cifrar(texto: str | None) -> str | None:
    if texto is None:
        return None
    return _fernet().encrypt(texto.encode("utf-8")).decode()


def descifrar(token: str | None) -> str | None:
    if not token:
        return None
    try:
        return _fernet().decrypt(token.encode()).decode()
    except (InvalidToken, Exception):
        return None
