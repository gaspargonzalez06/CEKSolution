# -*- coding: utf-8 -*-
"""Control de acceso por usuario: qué agentes y clientes puede ver cada uno.

admin y operador ven todo. Los demás roles (cliente, agente, ...) ven solo lo
que se les asigne:
  - agentes completos -> y, por tanto, TODOS sus clientes (via contratos), o
  - clientes sueltos.

El acceso es customizable: un usuario puede tener varios agentes y varios
clientes a la vez. Si no tiene nada asignado pero sí el campo `id_agente` o
`id_cliente` heredado, se usa ese.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import Contrato, Usuario, UsuarioAgente, UsuarioCliente

ROLES_TOTALES = ("admin", "operador")


def ve_todo(usuario: Usuario | None) -> bool:
    """True si el usuario puede ver todos los agentes/clientes."""
    return usuario is None or usuario.rol in ROLES_TOTALES


def asignados(db: Session, usuario: Usuario) -> tuple[set[int], set[int]]:
    """(agentes, clientes) asignados explícitamente al usuario."""
    agentes = {
        a[0]
        for a in db.query(UsuarioAgente.id_agente)
        .filter(UsuarioAgente.id_usuario == usuario.id)
        .all()
    }
    clientes = {
        c[0]
        for c in db.query(UsuarioCliente.id_cliente)
        .filter(UsuarioCliente.id_usuario == usuario.id)
        .all()
    }
    if usuario.id_agente:
        agentes.add(usuario.id_agente)
    if usuario.id_cliente:
        clientes.add(usuario.id_cliente)
    return agentes, clientes


def clientes_permitidos(db: Session, usuario: Usuario | None) -> set[int] | None:
    """Conjunto de `id_cliente` visibles, o None si el usuario ve todos."""
    if ve_todo(usuario):
        return None
    assert usuario is not None
    agentes, clientes = asignados(db, usuario)
    if agentes:
        filas = (
            db.query(Contrato.id_cliente)
            .filter(Contrato.id_agente.in_(agentes))
            .all()
        )
        clientes |= {f[0] for f in filas}
    return clientes


def agentes_permitidos(db: Session, usuario: Usuario | None) -> set[int] | None:
    """Conjunto de `id_agente` visibles, o None si ve todos."""
    if ve_todo(usuario):
        return None
    assert usuario is not None
    agentes, _ = asignados(db, usuario)
    return agentes


def puede_ver_cliente(db: Session, usuario: Usuario | None, id_cliente: int) -> bool:
    permitidos = clientes_permitidos(db, usuario)
    return permitidos is None or id_cliente in permitidos
