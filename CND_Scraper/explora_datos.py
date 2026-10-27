# -*- coding: utf-8 -*-
import sys, pymysql
sys.stdout.reconfigure(errors="replace")
c = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = c.cursor()

def show(title, sql):
    print("\n== " + title + " ==")
    cur.execute(sql)
    for r in cur.fetchall():
        print("  ", r)

show("subsistemas", "select subsistema, count(*), round(sum(consumo),1) from sustento_horario where periodo='202610' group by subsistema order by 3 desc")
show("top AGENTE (oct, v_max)", """
  select agente, round(sum(consumo),1) c from sustento_horario
  where periodo='202610' and version_num=(select max(version_num) from sustento_horario where periodo='202610')
  group by agente order by c desc limit 12""")
show("BRILLOSOL en AGENTE?", "select count(*) from sustento_horario where agente like '%BRILLO%'")
show("BRILLOSOL en SUPLIDOR?", "select count(*), round(sum(consumo),1) from sustento_horario where suplidor like '%BRILLO%'")
show("top SUPLIDOR (oct, v_max)", """
  select suplidor, round(sum(consumo),1) c from sustento_horario
  where periodo='202610' and version_num=(select max(version_num) from sustento_horario where periodo='202610')
  group by suplidor order by c desc limit 12""")
show("num agentes / suplidores", "select count(distinct agente), count(distinct suplidor) from sustento_horario")
show("rango horas", "select min(hora), max(hora) from sustento_horario")
