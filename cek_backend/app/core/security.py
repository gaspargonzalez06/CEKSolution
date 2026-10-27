# -*- coding: utf-8 -*-
"""Hash de contrasenas (PBKDF2-SHA256, solo stdlib) y tokens JWT."""
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt

from app.core.config import settings

_ITERACIONES = 200_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERACIONES)
    return f"pbkdf2_sha256${_ITERACIONES}${salt.hex()}${dk.hex()}"


def verify_password(password: str, hashed: str) -> bool:
    try:
        _algo, iters, salt_hex, dk_hex = hashed.split("$")
        dk = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), bytes.fromhex(salt_hex), int(iters)
        )
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def crear_token(data: dict) -> str:
    payload = data.copy()
    payload["exp"] = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_minutes)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_alg)


def leer_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_alg])
