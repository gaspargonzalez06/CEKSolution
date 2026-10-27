# -*- coding: utf-8 -*-
import sys, pymysql
sys.stdout.reconfigure(errors="replace")
c = pymysql.connect(host="127.0.0.1", user="root", password="", database="cek")
cur = c.cursor()

def show(title, sql, args=None):
    print("\n== " + title + " ==")
    cur.execute(sql, args or ())
    for r in cur.fetchall():
        print("  ", r)

# BRILLOSOL por periodo y version (ultima)
show("BRILLOSOL consumo por periodo (ultima version)", """
 select periodo, version_num, count(*) filas, round(sum(consumo),2) consumo,
        round(sum(ocasional_monto),2) monto
 from sustento_horario
 where agente='BRILLOSOL'
   and version_num=(select max(version_num) from sustento_horario s2 where s2.periodo=sustento_horario.periodo)
 group by periodo, version_num order by periodo""")

show("Sistema vs BRILLOSOL (sep total v5)", """
 select 'SISTEMA' k, round(sum(consumo),2) from sustento_horario where periodo='202609' and version_num=5
 union all
 select 'BRILLOSOL', round(sum(consumo),2) from sustento_horario where periodo='202609' and version_num=5 and agente='BRILLOSOL'""")

show("BRILLOSOL diario (sep v5)", """
 select fecha, round(sum(consumo),2) c from sustento_horario
 where periodo='202609' and version_num=5 and agente='BRILLOSOL' group by fecha order by fecha limit 5""")

show("perfil horario promedio (sep v5, sistema)", """
 select hora, round(avg(consu),2) from
   (select fecha,hora,sum(consumo) consu from sustento_horario
    where periodo='202609' and version_num=5 group by fecha,hora) t
 group by hora order by hora""")
