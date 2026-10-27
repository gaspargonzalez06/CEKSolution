# -*- coding: utf-8 -*-
"""Importa los PRECIOS (tarifas) del sistema viejo a la base nueva.

Fuente: CND_Flow_Explorer/precios_antiguos.tsv (o .csv) con la salida de la
consulta 2 de consultas_CEK_antigua.sql. Columnas esperadas:
    id_precio, id_contrato, contrato, tarifa, precio, inicia, termina

El contrato se resuelve por su id original (Contrato.id_antiguo) y, si no,
por el numero de contrato (texto). Es idempotente: si ya existe un precio con
el mismo contrato + fecha de inicio + tarifa, solo actualiza el monto.

Uso:  python importar_precios_antiguos.py
"""
import sys
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.core.database import SessionLocal  # noqa: E402
from app.models import Contrato, Precio  # noqa: E402
from lector_antiguo import leer_tabla  # noqa: E402

BASE = Path(__file__).resolve().parent.parent / "CND_Flow_Explorer"


def localizar(nombre: str) -> Path | None:
    for ext in (".tsv", ".csv", ".txt"):
        p = BASE / f"{nombre}{ext}"
        if p.exists():
            return p
    return None


def fecha(valor):
    valor = (valor or "").strip()
    if not valor:
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%d/%m/%Y"):
        try:
            return datetime.strptime(valor, fmt)
        except ValueError:
            continue
    return None


def num(valor):
    valor = (valor or "").strip().replace(",", "")
    if not valor:
        return None
    try:
        return float(valor)
    except ValueError:
        return None


def resolver_contrato(db, fila):
    id_antiguo = (fila.get("id_contrato") or "").strip()
    if id_antiguo.isdigit():
        c = db.query(Contrato).filter(Contrato.id_antiguo == int(id_antiguo)).first()
        if c:
            return c
    texto = (fila.get("contrato") or "").strip()
    if texto:
        return db.query(Contrato).filter(Contrato.contrato == texto).first()
    return None


def main():
    ruta = localizar("precios_antiguos")
    if ruta is None:
        print("No encontre 'precios_antiguos.tsv/.csv' en CND_Flow_Explorer. "
              "Exporta la consulta 2 y guardala ahi.")
        return
    datos = leer_tabla(ruta)
    print(f"Archivo: {ruta.name} · filas: {len(datos)}")

    db = SessionLocal()
    nuevos = act = sin_contrato = 0
    try:
        for f in datos:
            con = resolver_contrato(db, f)
            if con is None:
                sin_contrato += 1
                continue
            inicia = fecha(f.get("inicia"))
            tarifa = (f.get("tarifa") or "").strip() or None
            id_viejo = (f.get("id_precio") or "").strip()
            id_viejo = int(id_viejo) if id_viejo.isdigit() else None
            # Idempotencia: primero por el id de la tabla vieja (Precios.id),
            # luego por contrato+inicio+tarifa.
            p = None
            if id_viejo is not None:
                p = db.query(Precio).filter(Precio.id_antiguo == id_viejo).first()
            if p is None:
                p = (
                    db.query(Precio)
                    .filter(Precio.id_contrato == con.id, Precio.inicia == inicia, Precio.tarifa == tarifa)
                    .first()
                )
            if p is None:
                p = Precio(id_contrato=con.id, inicia=inicia, tarifa=tarifa)
                db.add(p)
                nuevos += 1
            else:
                act += 1
            p.id_antiguo = id_viejo
            p.precio = num(f.get("precio"))
            p.termina = fecha(f.get("termina"))
        db.commit()
        print(f"Precios nuevos: {nuevos} · actualizados: {act} · sin contrato: {sin_contrato}")
        print(f"Total precios en BD: {db.query(Precio).count()}")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
