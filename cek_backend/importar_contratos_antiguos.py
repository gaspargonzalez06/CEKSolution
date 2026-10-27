# -*- coding: utf-8 -*-
"""Importa los contratos del sistema viejo (SQL Server CEK) a la base nueva.

Fuente: CND_Flow_Explorer/contratos_antiguos.tsv  (salida de la consulta T-SQL).
Idempotente:
  - Agentes: upsert por codigo (nombre solo si falta; nunca pisa un nombre bueno).
  - Clientes: upsert por codigo (crea los que falten; completa ruc/nis si vacios).
  - Contratos: upsert por numero de contrato o por (agente, cliente); actualiza
    fechas, interes, garantia, indexacion y medicion.

Uso:  python importar_contratos_antiguos.py
"""
import sys
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.core.database import SessionLocal  # noqa: E402
from app.core.universo import es_gestionado  # noqa: E402
from app.models import Agente, Cliente, Contrato  # noqa: E402

ARCHIVO = Path(__file__).resolve().parent.parent / "CND_Flow_Explorer" / "contratos_antiguos.tsv"


def leer_filas():
    """Lee el TSV exportado de la base vieja."""
    texto = ARCHIVO.read_text(encoding="utf-8")
    lineas = [l for l in texto.splitlines() if l.strip()]
    cabecera = lineas[0].split("\t")
    filas = []
    for linea in lineas[1:]:
        partes = linea.split("\t")
        partes += [""] * (len(cabecera) - len(partes))
        filas.append(dict(zip(cabecera, partes)))
    return filas


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


def texto_o_none(valor):
    valor = (valor or "").strip()
    return valor or None


def main():
    filas = leer_filas()
    print(f"Filas en el TSV: {len(filas)}")

    db = SessionLocal()
    nuevos_cli = nuevos_con = act_con = 0
    try:
        for f in filas:
            cod_ag = f["agente_codigo"].strip().upper()
            cod_cli = f["cliente_codigo"].strip().upper()

            # --- agente (generador) ---
            ag = db.query(Agente).filter(Agente.codigo == cod_ag).first()
            if ag is None:
                ag = Agente(codigo=cod_ag, nombre=texto_o_none(f["agente_nombre"]),
                            generador=True, activo=True)
                db.add(ag)
                db.flush()
            if es_gestionado(cod_ag):
                ag.gestionado = True

            # --- cliente ---
            cli = db.query(Cliente).filter(Cliente.codigo == cod_cli).first()
            if cli is None:
                cli = Cliente(
                    codigo=cod_cli,
                    nombre=texto_o_none(f["cliente_nombre"]),
                    ruc=texto_o_none(f["cliente_ruc"]),
                    nis=texto_o_none(f["cliente_nis"]),
                    activo=True,
                )
                db.add(cli)
                db.flush()
                nuevos_cli += 1
            else:
                # No pisar un nombre existente bueno; si esta vacio, completarlo.
                if not cli.nombre:
                    cli.nombre = texto_o_none(f["cliente_nombre"])
                if not cli.ruc:
                    cli.ruc = texto_o_none(f["cliente_ruc"])
                if not cli.nis:
                    cli.nis = texto_o_none(f["cliente_nis"])

            # --- contrato: buscar por numero o por (agente, cliente) ---
            num = texto_o_none(f["contrato"])
            con = None
            if f["contrato"].strip():
                con = db.query(Contrato).filter(Contrato.contrato == f["contrato"].strip()).first()
            if con is None:
                con = (
                    db.query(Contrato)
                    .filter(Contrato.id_agente == ag.id, Contrato.id_cliente == cli.id)
                    .first()
                )
            if con is None:
                con = Contrato(id_agente=ag.id, id_cliente=cli.id, activo=True)
                db.add(con)
                nuevos_con += 1
            else:
                act_con += 1

            con.id_agente = ag.id
            con.id_cliente = cli.id
            con.contrato = texto_o_none(f["contrato"])
            con.id_antiguo = int(f["id_contrato"]) if (f.get("id_contrato") or "").strip().isdigit() else None
            con.inicio = fecha(f["inicio"])
            con.final = fecha(f["fin"])
            interes = (f["interes"] or "").strip()
            con.interes = float(interes) if interes else None
            con.garantia = texto_o_none(f["garantia"])
            con.indexacion = texto_o_none(f["indexacion"])
            con.medicion = texto_o_none(f["medicion"])
            con.activo = True

        db.commit()
        print(f"Clientes nuevos: {nuevos_cli} · Contratos nuevos: {nuevos_con} · Contratos actualizados: {act_con}")
        print("Totales -> agentes: %s · clientes: %s · contratos: %s" % (
            db.query(Agente).count(), db.query(Cliente).count(), db.query(Contrato).count(),
        ))
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
