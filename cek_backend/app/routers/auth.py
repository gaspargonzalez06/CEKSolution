# -*- coding: utf-8 -*-
"""Autenticacion: login (JWT) y usuario actual."""
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import crear_token, verify_password
from app.models import Usuario
from app.schemas import Token, UsuarioOut

router = APIRouter(prefix="/auth", tags=["Autenticación"])


@router.post("/login", response_model=Token)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.usuario == form.username).first()
    if not user or not user.activo or not verify_password(form.password, user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Usuario o contraseña incorrectos")
    token = crear_token({"sub": str(user.id), "rol": user.rol})
    return Token(access_token=token, usuario=UsuarioOut.model_validate(user))


@router.get("/me", response_model=UsuarioOut)
def me(user: Usuario = Depends(get_current_user)):
    return user
