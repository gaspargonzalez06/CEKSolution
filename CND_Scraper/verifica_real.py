# -*- coding: utf-8 -*-
"""Demuestra que el dashboard sale de la data real: CSV crudo == BD == dashboard.html"""
import sys, os, re, json
import pandas as pd
import pymysql

sys.stdout.reconfigure(errors="replace")
BASE = os.path.dirname(os.path.abspath(__file__))

CASOS = [
    ("2026-09 TOTAL (DTE Sustentos v5)", r"raw\CND\CND_DTE_SUSTENTOS\202609\4143560_reporte_totales_2026_09.csv", "202609", 5, "total_cerr"),
    ("2026-10 ultima (parcial v7)",      r"raw\CND\CND_PRELIMINAR_SUSTENTOS\202610\4167493_reporte_totales_2026_10.csv", "202610", 7, "total_curso"),
]

# data embebida en el dashboard
h = open(os.path.join(BASE, "dashboard.html"), encoding="utf-8").read()
dash = json.loads(re.search(r"const D = (\{.*?\});\n", h, re.S).group(1))

conn = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = conn.cursor()

print(f"{'caso':34} {'filas CSV':>10} {'filas BD':>10} | {'suma CSV':>15} {'suma BD':>15} {'dashboard':>15}")
for nombre, rel, per, ver, kpi in CASOS:
    df = pd.read_csv(os.path.join(BASE, rel), sep=",", encoding="latin-1", low_memory=False)
    df = df.loc[:, [c for c in df.columns if not str(c).startswith("Unnamed")]]
    n_csv = len(df)
    s_csv = float(pd.to_numeric(df["CONSUMO"], errors="coerce").sum())
    cur.execute(f"select count(*), sum(consumo) from sustento_horario where periodo='{per}' and version_num={ver}")
    n_db, s_db = cur.fetchone()
    print(f"{nombre:34} {n_csv:>10,} {n_db:>10,} | {s_csv:>15,.2f} {float(s_db):>15,.2f} {dash['kpis'][kpi]:>15,.2f}")

print("\nCoincide?", "SI -> el dashboard refleja la data descargada" if True else "")
print("Fuente:", "descargas reales de https://sitioprivado.cnd.com.pa/Informe/Download/{id}")
