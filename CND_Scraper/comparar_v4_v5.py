# -*- coding: utf-8 -*-
"""Compara el ultimo parcial (v4) vs el TOTAL (v5) para 2026-09, por medida."""
import sys, pymysql
sys.stdout.reconfigure(errors="replace")

meds = ["consumo", "energia_asignada", "energia_contrato", "perdida_consumo",
        "ocasional_monto", "opo_monto_ocasional", "opo_monto_opo", "opo_sobrecosto"]

c = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = c.cursor()
sel = ",".join(f"sum({m})" for m in meds)
cur.execute(f"select version_num,{sel} from sustento_horario "
            f"where periodo=202609 group by version_num order by version_num")
rows = cur.fetchall()
v4, v5 = rows[3], rows[4]

print(f"{'medida':22} {'v4 (ult.parcial)':>18} {'v5 (TOTAL)':>18} {'delta':>14} {'%':>8}")
for i, m in enumerate(meds):
    a = float(v4[i + 1])
    b = float(v5[i + 1])
    d = b - a
    p = (d / a * 100) if a else 0
    print(f"{m:22} {a:>18,.2f} {b:>18,.2f} {d:>14,.2f} {p:>7.3f}%")
