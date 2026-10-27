# -*- coding: utf-8 -*-
import sys, pymysql
sys.stdout.reconfigure(errors="replace")
c = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = c.cursor()
V = "(select max(version_num) from sustento_horario where periodo='202609')"

print("== distintos SUPLIDOR (posibles generadores/agentes) ==")
cur.execute("select suplidor, count(distinct agente) na, round(sum(consumo),1) c "
            "from sustento_horario where periodo='202609' group by suplidor order by c desc")
for r in cur.fetchall():
    print(f"   {r[0]:16} agentes={r[1]:>4}  consumo={float(r[2]):>12,.1f}")

print("\n== AGENTES con mas SUPLIDORES (posibles distribuidores) ==")
cur.execute(f"""select agente, count(distinct suplidor) n, group_concat(distinct suplidor separator ', ')
 from sustento_horario where periodo='202609' and version_num={V} group by agente order by n desc limit 12""")
for r in cur.fetchall():
    print(f"   {r[0]:14} n={r[1]:>3}  {r[2][:90]}")

print("\n== agente BRILLOSOL: suplidores ==")
cur.execute(f"select distinct suplidor from sustento_horario where agente='BRILLOSOL' and periodo='202609' and version_num={V}")
print("   ", [r[0] for r in cur.fetchall()])

print("\n== muestra de AGENTES (orden alfabetico, primeros 40) ==")
cur.execute("select distinct agente from sustento_horario order by agente limit 40")
print("   ", ", ".join(r[0] for r in cur.fetchall()))
