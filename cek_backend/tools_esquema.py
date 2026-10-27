# -*- coding: utf-8 -*-
"""Muestra la estructura de las tablas dte / raw_data / scraping_log."""
import sys
import pymysql

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
conn = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek", charset="utf8mb4")
cur = conn.cursor()
for t in ("dte", "raw_data", "scraping_log", "sustento_horario"):
    print(f"\n===== {t} =====")
    try:
        cur.execute(f"SHOW CREATE TABLE {t}")
        print(cur.fetchone()[1])
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        print("filas:", cur.fetchone()[0])
        cur.execute(f"SELECT * FROM {t} LIMIT 3")
        for r in cur.fetchall():
            print("   ", r)
    except Exception as e:
        print("ERROR", e)
conn.close()
