# -*- coding: utf-8 -*-
"""Dependencias de autenticacion y control de roles."""
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import leer_token
from app.models import Usuario

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> Usuario:
    cred_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No autenticado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = leer_token(token)
    except Exception:
        raise cred_exc

    sub = payload.get("sub")
    if sub is None:
        raise cred_exc

    user = db.get(Usuario, int(sub))
    if user is None or not user.activo:
        raise cred_exc
    return user


def require_roles(*roles: str):
    """Devuelve una dependencia que exige uno de los roles dados."""

    def _checker(user: Usuario = Depends(get_current_user)) -> Usuario:
        if roles and user.rol not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Sin permisos para esta operacion")
        return user

    return _checker
