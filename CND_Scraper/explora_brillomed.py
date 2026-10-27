# -*- coding: utf-8 -*-
import sys, pymysql
sys.stdout.reconfigure(errors="replace")
c = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = c.cursor()
meds = ["consumo","consumo_pmo","perdida_consumo","energia_asignada","energia_contrato",
        "suplido_local","suplido_imp_con","suplido_imp_opo","suplido_pos_contratos",
        "suplido_mo","suplido_mo_imp","ocasional_venta","ocasional_compra","ocasional_monto",
        "opo_energia","opo_monto_ocasional","opo_monto_opo","opo_monto_cuspt","opo_monto_imp",
        "opo_diferencia","opo_sobrecosto"]
for per, v in [("202609", 5), ("202610", 7)]:
    print(f"\n== BRILLOSOL {per} v{v} ==")
    sel = ",".join(f"sum({m})" for m in meds)
    cur.execute(f"select {sel} from sustento_horario where periodo='{per}' and version_num={v} and agente='BRILLOSOL'")
    row = cur.fetchone()
    for m, val in zip(meds, row):
        v2 = float(val or 0)
        if abs(v2) > 1e-9:
            print(f"   {m:22} {v2:>16,.2f}")
