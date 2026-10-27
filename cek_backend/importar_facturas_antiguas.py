# -*- coding: utf-8 -*-
"""Importa las FACTURAS del sistema viejo (historico) a la base nueva.

Fuente: CND_Flow_Explorer/facturas_antiguas.tsv (o .csv) con la salida de la
consulta 5 de consultas_CEK_antigua.sql. Columnas esperadas:
    generador, cliente, contrato, annio, mes, consumo, precio, valor, costo,
    descuento, texto_otros_cargos, monto_otros_cargos

Se conservan tal cual en la tabla `facturas_historicas`. El contrato nuevo se
resuelve por (codigo de agente + codigo de cliente) y, si no, por el numero de
contrato. Es idempotente (clave: generador + cliente + contrato + anio + mes).

Uso:  python importar_facturas_antiguas.py
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.core.database import SessionLocal  # noqa: E402
from app.models import Agente, Cliente, Contrato, FacturaHistorica  # noqa: E402
from lector_antiguo import leer_tabla  # noqa: E402

BASE = Path(__file__).resolve().parent.parent / "CND_Flow_Explorer"


def localizar(nombre: str) -> Path | None:
    for ext in (".tsv", ".csv", ".txt"):
        p = BASE / f"{nombre}{ext}"
        if p.exists():
            return p
    return None


def num(valor):
    valor = (valor or "").strip().replace(",", "")
    if not valor:
        return None
    try:
        return float(valor)
    except ValueError:
        return None


def ent(valor):
    valor = (valor or "").strip()
    try:
        return int(float(valor))
    except ValueError:
        return None


def resolver_contrato(db, generador, cliente, texto):
    ag = db.query(Agente).filter(Agente.codigo == generador).first() if generador else None
    cl = db.query(Cliente).filter(Cliente.codigo == cliente).first() if cliente else None
    if ag and cl:
        c = db.query(Contrato).filter(Contrato.id_agente == ag.id, Contrato.id_cliente == cl.id).first()
        if c:
            return c
    if texto:
        return db.query(Contrato).filter(Contrato.contrato == texto).first()
    return None


def main():
    ruta = localizar("facturas_antiguas")
    if ruta is None:
        print("No encontre 'facturas_antiguas.tsv/.csv' en CND_Flow_Explorer. "
              "Exporta la consulta 5 y guardala ahi.")
        return
    datos = leer_tabla(ruta)
    print(f"Archivo: {ruta.name} · filas: {len(datos)}")

    db = SessionLocal()
    nuevos = act = sin_contrato = 0
    try:
        for f in datos:
            generador = (f.get("generador") or "").strip()
            cliente = (f.get("cliente") or "").strip()
            texto = (f.get("contrato") or "").strip()
            annio = ent(f.get("annio"))
            mes = ent(f.get("mes"))
            con = resolver_contrato(db, generador, cliente, texto)
            if con is None:
                sin_contrato += 1
            h = (
                db.query(FacturaHistorica)
                .filter(
                    FacturaHistorica.generador == generador,
                    FacturaHistorica.cliente == cliente,
                    FacturaHistorica.contrato == texto,
                    FacturaHistorica.annio == annio,
                    FacturaHistorica.mes == mes,
                )
                .first()
            )
            if h is None:
                h = FacturaHistorica(
                    generador=generador, cliente=cliente, contrato=texto, annio=annio, mes=mes
                )
                db.add(h)
                nuevos += 1
            else:
                act += 1
            h.id_contrato = con.id if con else None
            h.consumo = num(f.get("consumo"))
            h.precio = num(f.get("precio"))
            h.valor = num(f.get("valor"))
            h.costo = num(f.get("costo"))
            h.descuento = num(f.get("descuento"))
            h.texto_otros_cargos = (f.get("texto_otros_cargos") or "").strip() or None
            h.monto_otros_cargos = num(f.get("monto_otros_cargos"))
        db.commit()
        print(f"Facturas nuevas: {nuevos} · actualizadas: {act} · sin contrato resuelto: {sin_contrato}")
        print(f"Total facturas historicas en BD: {db.query(FacturaHistorica).count()}")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
