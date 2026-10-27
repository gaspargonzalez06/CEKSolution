# -*- coding: utf-8 -*-
"""CRUD de usuarios y roles (solo admin)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core import acceso
from app.core.database import get_db
from app.core.deps import require_roles
from app.core.security import hash_password
from app.models import Usuario, UsuarioAgente, UsuarioCliente
from app.schemas import (
    AccesosIn,
    AccesosOut,
    UsuarioCreate,
    UsuarioOut,
    UsuarioUpdate,
)

router = APIRouter(prefix="/usuarios", tags=["Usuarios"], dependencies=[Depends(require_roles("admin"))])

ROLES = ("admin", "operador", "cliente", "agente")


@router.get("", response_model=list[UsuarioOut])
def listar(db: Session = Depends(get_db)):
    return db.query(Usuario).order_by(Usuario.id).all()


@router.post("", response_model=UsuarioOut, status_code=201)
def crear(data: UsuarioCreate, db: Session = Depends(get_db)):
    if data.rol not in ROLES:
        raise HTTPException(400, f"Rol inválido. Use uno de: {', '.join(ROLES)}")
    if db.query(Usuario).filter(Usuario.usuario == data.usuario).first():
        raise HTTPException(400, "El usuario ya existe")
    user = Usuario(
        usuario=data.usuario,
        nombre=data.nombre,
        email=data.email,
        rol=data.rol,
        activo=data.activo,
        id_agente=data.id_agente,
        id_cliente=data.id_cliente,
        password_hash=hash_password(data.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get("/{id}", response_model=UsuarioOut)
def obtener(id: int, db: Session = Depends(get_db)):
    user = db.get(Usuario, id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    return user


@router.put("/{id}", response_model=UsuarioOut)
def actualizar(id: int, data: UsuarioUpdate, db: Session = Depends(get_db)):
    user = db.get(Usuario, id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    cambios = data.model_dump(exclude_unset=True)
    if "password" in cambios:
        user.password_hash = hash_password(cambios.pop("password"))
    if "rol" in cambios and cambios["rol"] not in ROLES:
        raise HTTPException(400, f"Rol inválido. Use uno de: {', '.join(ROLES)}")
    for campo, valor in cambios.items():
        setattr(user, campo, valor)
    db.commit()
    db.refresh(user)
    return user


@router.delete("/{id}", status_code=204)
def eliminar(id: int, db: Session = Depends(get_db), actual: Usuario = Depends(require_roles("admin"))):
    if id == actual.id:
        raise HTTPException(400, "No puede eliminar su propio usuario")
    user = db.get(Usuario, id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    db.delete(user)
    db.commit()


@router.get("/{id}/accesos", response_model=AccesosOut)
def ver_accesos(id: int, db: Session = Depends(get_db)):
    """Agentes y clientes asignados al usuario (acceso customizable)."""
    user = db.get(Usuario, id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    agentes, clientes = acceso.asignados(db, user)
    efectivos = acceso.clientes_permitidos(db, user) or set()
    return AccesosOut(
        id_usuario=id,
        agentes=sorted(agentes),
        clientes=sorted(clientes),
        clientes_efectivos=sorted(efectivos),
    )


@router.put("/{id}/accesos", response_model=AccesosOut)
def poner_accesos(id: int, data: AccesosIn, db: Session = Depends(get_db)):
    """Reemplaza los agentes/clientes a los que el usuario tiene acceso.

    Asignar un agente da acceso a TODOS sus clientes; tambien se pueden asignar
    clientes sueltos para dar un acceso mas fino.
    """
    user = db.get(Usuario, id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")

    db.query(UsuarioAgente).filter(UsuarioAgente.id_usuario == id).delete()
    db.query(UsuarioCliente).filter(UsuarioCliente.id_usuario == id).delete()
    for id_ag in sorted(set(data.agentes)):
        db.add(UsuarioAgente(id_usuario=id, id_agente=id_ag))
    for id_cl in sorted(set(data.clientes)):
        db.add(UsuarioCliente(id_usuario=id, id_cliente=id_cl))
    db.commit()

    agentes, clientes = acceso.asignados(db, user)
    efectivos = acceso.clientes_permitidos(db, user) or set()
    return AccesosOut(
        id_usuario=id,
        agentes=sorted(agentes),
        clientes=sorted(clientes),
        clientes_efectivos=sorted(efectivos),
    )
