# -*- coding: utf-8 -*-
"""Universo de agentes gestionados por CEK CONSULTORES.

Son los agentes para los que CEK tiene credenciales en el portal privado del CND
(https://www.cnd.com.pa/privado/) y por tanto los unicos que se gestionan en la
aplicacion. El resto de agentes que aparecen en los reportes del mercado son
contrapartes y no deben listarse como agentes propios.

Codigo -> usuario del portal privado del CND.
"""

# Orden alfabetico. El usuario del portal coincide con el codigo del agente.
AGENTES_UNIVERSO: dict[str, str] = {
    "BRILLOSOL": "BRILLOSOL",
    "CAPIRAPARK": "CAPIRAPARK",
    "CSOLAR": "CSOLAR",
    "DECASOLAR": "DECASOLAR",
    "ELESOLAR": "ELESOLAR",
    "GENENEREN": "GENENEREN",
    "MERCURISOL": "MERCURISOL",
    "NEONSOLAR": "NEONSOLAR",
    "OROSOL": "OROSOL",
    "SAZUEROVEN": "SAZUEROVEN",
    "SCOCLEVEN": "SCOCLEVEN",
    "SOLENEPARK": "SOLENEPARK",
    "SPMAVEN": "SPMAVEN",
    "SUNERGY1": "SUNERGY1",
}

UNIVERSO_CODIGOS: frozenset[str] = frozenset(AGENTES_UNIVERSO)


def es_gestionado(codigo: str | None) -> bool:
    return bool(codigo) and codigo.strip().upper() in UNIVERSO_CODIGOS
