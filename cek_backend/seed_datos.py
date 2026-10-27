# -*- coding: utf-8 -*-
"""Carga inicial de datos (agentes, clientes, contratos) desde los DTE tabulares.

- BRILLOSOL  -> agente generador emisor.
- GCP####    -> clientes de BRILLOSOL (contratos BRILLOSOL -> cliente).
- Resto      -> agentes del mercado (ENSA/EDEMET/EDECHI marcados como distribuidores).

Es idempotente: se puede correr varias veces.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from app.core.database import SessionLocal  # noqa: E402
from app.core.universo import es_gestionado  # noqa: E402
from app.models import Agente, Cliente, Contrato  # noqa: E402

BASE_DIR = Path(__file__).resolve().parents[1]
RAW = BASE_DIR / "CND_Scraper" / "raw"

DISTRIBUIDORES = {"ENSA", "EDEMET", "EDECHI"}


def leer_texto(archivo: Path) -> str:
    """Los archivos del portal son UTF-8; se intenta utf-8-sig y luego latin-1.

    Antes se leia directo como latin-1, lo que convertia "Panamá" en "PanamÃ¡"
    (UTF-8 leido como latin-1) y corrompia todos los nombres cargados en la BD.
    """
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return archivo.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return archivo.read_text(encoding="latin-1", errors="replace")


def leer_dte():
    """Devuelve (clientes, contrapartes) detectados en los DTE tabulares."""
    clientes: dict[str, str] = {}
    contrapartes: dict[str, str] = {}
    agente_nombre: dict[str, str] = {}
    for carpeta in RAW.rglob("CND_DTE_TABULAR"):
        for archivo in carpeta.rglob("*.txt"):
            try:
                texto = leer_texto(archivo)
            except Exception:
                continue
            for linea in texto.splitlines()[1:]:
                if not linea.strip():
                    continue
                p = linea.split("\t")
                if len(p) < 5:
                    continue
                nom = p[0].strip().strip('"')
                cod = p[1].strip().strip('"')
                nomb = p[3].strip().strip('"')
                codb = p[4].strip().strip('"')
                if cod:
                    agente_nombre[cod.upper()] = nom
                if cod.upper().startswith("GCP") and nom:
                    clientes[cod.upper()] = nom
                if codb and nomb:
                    contrapartes[codb.upper()] = nomb
    return agente_nombre, clientes, contrapartes


def es_mojibake(s: str | None) -> bool:
    """True si el texto parece UTF-8 leido como latin-1 ("PanamÃ¡")."""
    return bool(s) and any(ch in s for ch in ("Ã", "Â", "�"))


def upsert_agente(db, codigo, nombre, *, distribuidor=False, generador=False, codigo_cnd=None):
    ag = db.query(Agente).filter(Agente.codigo == codigo).first()
    if ag is None:
        ag = Agente(codigo=codigo, nombre=nombre, activo=True)
        db.add(ag)
        db.flush()
    if nombre and (not ag.nombre or es_mojibake(ag.nombre)):
        ag.nombre = nombre
    ag.distribuidor = ag.distribuidor or distribuidor
    ag.generador = ag.generador or generador
    if codigo_cnd and not ag.codigo_cnd:
        ag.codigo_cnd = codigo_cnd
    # Solo los 14 agentes del universo tienen credenciales del portal privado del CND.
    # Nunca se apaga una marca manual (solo se enciende si corresponde al universo).
    if es_gestionado(codigo):
        ag.gestionado = True
    return ag


def main():
    agente_nombre, clientes, contrapartes = leer_dte()
    print(f"Detectados: {len(agente_nombre)} agentes, {len(clientes)} clientes GCP, {len(contrapartes)} contrapartes")

    db = SessionLocal()
    try:
        # 1) BRILLOSOL y demas agentes del mercado
        brillo = upsert_agente(
            db, "BRILLOSOL", agente_nombre.get("BRILLOSOL", "Generadora Brillo Solar, S. A."),
            generador=True, codigo_cnd="BRILLOSOL",
        )
        for cod, nom in sorted(contrapartes.items()):
            if cod == "BRILLOSOL":
                continue
            upsert_agente(
                db, cod, nom,
                distribuidor=cod in DISTRIBUIDORES,
                generador=cod not in DISTRIBUIDORES,
                codigo_cnd=cod,
            )
        db.flush()

        # 2) Clientes GCP + contrato con BRILLOSOL
        creados_cli = 0
        creados_con = 0
        for cod, nom in sorted(clientes.items()):
            cli = db.query(Cliente).filter(Cliente.codigo == cod).first()
            if cli is None:
                cli = Cliente(codigo=cod, nombre=nom, activo=True)
                db.add(cli)
                db.flush()
                creados_cli += 1
            elif not cli.nombre or es_mojibake(cli.nombre):
                cli.nombre = nom
            con = (
                db.query(Contrato)
                .filter(Contrato.id_agente == brillo.id, Contrato.id_cliente == cli.id)
                .first()
            )
            if con is None:
                db.add(Contrato(
                    contrato=f"{brillo.codigo}-{cod}",
                    id_agente=brillo.id,
                    id_cliente=cli.id,
                    activo=True,
                ))
                creados_con += 1

        db.commit()
        print(f"Clientes nuevos: {creados_cli} · Contratos nuevos: {creados_con}")
        print("Agentes totales:", db.query(Agente).count())
        print("Clientes totales:", db.query(Cliente).count())
        print("Contratos totales:", db.query(Contrato).count())
    finally:
        db.close()


if __name__ == "__main__":
    main()
