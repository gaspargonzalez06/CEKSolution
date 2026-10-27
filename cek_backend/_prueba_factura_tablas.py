# -*- coding: utf-8 -*-
"""Prueba la factura armada SOLO con las tablas dte/dter cargadas de los crudos."""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.core.database import SessionLocal  # noqa: E402
from app.services import facturas as svc  # noqa: E402

CLI = "GCP0728"
PER = "202607"
CONSUMO = 102.776640
PRECIO = 0.0710
ITBMS = 7.0

db = SessionLocal()
med = svc.consumo_desde_mediciones(db, CLI, PER)
print(f"=== consumo desde tabla mediciones = {med}")
hist = svc.historial_mediciones(db, CLI)
print("=== historial mediciones ===")
for p, m in hist.items():
    print(f"  {p}  {m:.6f}")
cargos = svc.cargos_desde_dte(db, CLI, PER)
print("=== cargos desde tabla dte (Regular) ===")
for k, v in cargos.items():
    print(f"  {v['debito']-v['credito']:>10.2f}   {k}")

dter = svc.dter_desde_tabla(db, CLI, svc.periodo_anterior(PER))
print(f"=== DTER desde tabla ({svc.periodo_anterior(PER)}) = {dter:.2f}")

lineas = svc.lineas_factura(cargos, CONSUMO, PRECIO, True, periodo=PER,
                            dter_monto=dter,
                            dter_periodo=svc.periodo_anterior(PER))
sub, itbms, total = svc.totales(lineas, ITBMS)
print("=== lineas ===")
for l in lineas:
    print(f"  {('T' if l['es_total'] else ' ')} {str(l['monto']):>10}   {l['descripcion']}")
print(f"  Subtotal {sub:.2f}  ITBMS {itbms:.2f}  TOTAL {total:.2f}")
print()
print("referencia vieja: energia 7,297.14  perdidas 111.14  extra 32.01  "
      "servaux 2.71  servauxiliares 85.72  dter 58.09  TOTAL 7,586.81")

# historico de la columna Consumos tal como lo arma el router (mediciones + facturas)
from app.models import Cliente  # noqa: E402
from app.routers.facturas import _historico_cliente  # noqa: E402
cli = db.query(Cliente).filter_by(codigo=CLI).first()
if cli:
    print("=== columna Consumos (router, id_cliente=%s) ===" % cli.id)
    for h in _historico_cliente(db, cli.id, PER, limite=6):
        print(f"  {h['etiqueta']}  {h['mwh']}")
db.close()
