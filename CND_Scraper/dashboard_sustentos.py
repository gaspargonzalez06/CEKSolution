# -*- coding: utf-8 -*-
"""
Genera un dashboard HTML autocontenido (Chart.js incrustado) a partir de la
tabla cek.sustento_horario.

Muestra:
  - KPIs del mes en curso y del mes cerrado
  - Evolucion diaria + proyeccion de cierre
  - "Pintado" del mes por version (acumulado)
  - Parcial vs Total del mes cerrado (asociacion + ajuste)
  - Ajuste % por medida
  - Perfil horario promedio
  - Top agentes del sistema
  - BRILLOSOL: monto ocasional diario + proyeccion
  - Tabla de versiones

Uso: python dashboard_sustentos.py
Salida: dashboard.html
"""
import sys, os, json, datetime
import pymysql

sys.stdout.reconfigure(errors="replace")
BASE = os.path.dirname(os.path.abspath(__file__))
CHARTJS = os.path.join(BASE, "assets", "chart.umd.min.js")

MES_CURSO = "202610"
MES_CERRADO = "202609"
DIAS_MES = {"202609": 30, "202610": 31}


def connect():
    try:
        import yaml
        db = yaml.safe_load(open(os.path.join(BASE, "config.yaml"), encoding="utf-8"))["database"]
    except Exception:
        db = dict(host="127.0.0.1", port=3306, database="cek", username="root", password="")
    return pymysql.connect(host=db["host"], port=int(db["port"]), user=db["username"],
                           password=db.get("password") or "", database=db["database"], charset="utf8mb4")


def catalog_tipos():
    import glob
    files = sorted(glob.glob(os.path.join(BASE, "catalog_*.json")))
    if not files:
        return {}
    cat = json.load(open(files[-1], encoding="utf-8"))
    return {str(it["id"]): (it.get("tipo") or {}).get("name", "") for it in cat}


def f(x):
    return round(float(x), 2) if x is not None else 0.0


def main():
    conn = connect()
    cur = conn.cursor()
    tipos = catalog_tipos()

    def q(sql):
        cur.execute(sql)
        return cur.fetchall()

    # --- versiones ---
    vers = []
    for r in q("""SELECT periodo, reporte_id, fecha_pub, version_num, dias, desde, hasta, filas, consumo_total
                  FROM v_sustento_version ORDER BY periodo, version_num"""):
        rid = str(r[1])
        vers.append(dict(periodo=r[0], reporte_id=r[1], fecha_pub=str(r[2]),
                         version=r[3], dias=r[4], desde=str(r[5]), hasta=str(r[6]),
                         filas=r[7], consumo=f(r[8]), tipo=tipos.get(rid, ""),
                         es_total=(tipos.get(rid) == "DTE Sustentos")))
    # version "final" por periodo
    final = {}
    for v in vers:
        if v["es_total"]:
            final[v["periodo"]] = v["version"]

    # --- diario por version (matriz) ---
    dia = {}
    for r in q("SELECT periodo, version_num, fecha, consumo FROM v_sustento_dia"):
        dia.setdefault(r[0], {}).setdefault(r[1], {})[r[2].day] = f(r[3])

    def daily(periodo, version):
        d = dia.get(periodo, {}).get(version, {})
        return [d.get(i) for i in range(1, DIAS_MES[periodo] + 1)]

    # --- agregados por version del mes cerrado (para ajuste por medida) ---
    MEDS = ["consumo", "energia_asignada", "perdida_consumo", "ocasional_monto"]
    sel = ",".join(f"SUM({m})" for m in MEDS)
    agv = {}
    for r in q(f"SELECT version_num,{sel} FROM sustento_horario WHERE periodo='{MES_CERRADO}' GROUP BY version_num ORDER BY version_num"):
        agv[r[0]] = {m: f(r[i + 1]) for i, m in enumerate(MEDS)}

    # --- perfil horario (usando version final/ultima de cada periodo) ---
    vfinal_curso = max(v["version"] for v in vers if v["periodo"] == MES_CURSO)
    perfil = {}
    for r in q(f"""
        SELECT periodo, hora, AVG(d) FROM (
          SELECT periodo, fecha, hora, SUM(consumo) d FROM sustento_horario
          WHERE (periodo='{MES_CERRADO}' AND version_num={final[MES_CERRADO]})
             OR (periodo='{MES_CURSO}'  AND version_num={vfinal_curso})
          GROUP BY periodo, fecha, hora) t
        GROUP BY periodo, hora ORDER BY periodo, hora"""):
        perfil.setdefault(r[0], {})[int(r[1])] = f(r[2])

    # --- top agentes (mes en curso, ultima version) ---
    top = [dict(agente=r[0], consumo=f(r[1])) for r in q(f"""
        SELECT agente, SUM(consumo) c FROM sustento_horario
        WHERE periodo='{MES_CURSO}' AND version_num={vfinal_curso}
        GROUP BY agente ORDER BY c DESC LIMIT 12""")]

    # --- BRILLOSOL diario (monto ocasional + energia) ---
    bri = {}
    for r in q(f"""
        SELECT periodo, fecha, SUM(ocasional_monto), SUM(energia_asignada)
        FROM sustento_horario WHERE agente='BRILLOSOL'
          AND ((periodo='{MES_CERRADO}' AND version_num={final[MES_CERRADO]})
            OR (periodo='{MES_CURSO}'  AND version_num={vfinal_curso}))
        GROUP BY periodo, fecha"""):
        bri.setdefault(r[0], {})[r[1].day] = dict(monto=f(r[2]), energia=f(r[3]))

    def bri_daily(periodo, key):
        d = bri.get(periodo, {})
        return [d.get(i, {}).get(key, 0) for i in range(1, DIAS_MES[periodo] + 1)]

    # --- serie del sistema (mes en curso y cerrado) ---
    curso = daily(MES_CURSO, vfinal_curso)
    curso_ok = [x for x in curso if x is not None]
    dias_curso = len(curso_ok)
    total_curso = sum(curso_ok)
    prom_curso = total_curso / dias_curso if dias_curso else 0
    proy_curso = prom_curso * DIAS_MES[MES_CURSO]

    cerr_total = daily(MES_CERRADO, final[MES_CERRADO])
    cerr_parcial = daily(MES_CERRADO, final[MES_CERRADO] - 1)
    total_cerr = sum(x for x in cerr_total if x)
    total_parc = sum(x for x in cerr_parcial if x)
    ajuste = total_cerr - total_parc

    # BRILLOSOL
    bri_curso = bri_daily(MES_CURSO, "monto")
    bri_ok = [x for x in bri_curso if x]
    bri_dias = len([d for d in bri.get(MES_CURSO, {})])
    bri_total = sum(bri_daily(MES_CURSO, "monto"))
    bri_prom = bri_total / bri_dias if bri_dias else 0
    bri_proy = bri_prom * DIAS_MES[MES_CURSO]
    bri_cerr = sum(bri_daily(MES_CERRADO, "monto"))
    bri_ener_cerr = sum(bri_daily(MES_CERRADO, "energia"))
    bri_ener_curso = sum(bri_daily(MES_CURSO, "energia"))

    # proyeccion lineal restante (para graficar)
    proy_serie = list(curso)
    for i in range(dias_curso, DIAS_MES[MES_CURSO]):
        proy_serie.append(round(prom_curso, 1))

    def acum(seq):
        out, acc = [], 0
        for x in seq:
            if x is None:
                out.append(None)
            else:
                acc += x
                out.append(round(acc, 1))
        return out

    acum_serie = {str(v["version"]): acum(daily(MES_CURSO, v["version"]))
                  for v in vers if v["periodo"] == MES_CURSO}

    ajuste_medidas = []
    for m in MEDS:
        p = agv.get(final[MES_CERRADO] - 1, {}).get(m, 0) or 0
        t = agv.get(final[MES_CERRADO], {}).get(m, 0) or 0
        ajuste_medidas.append(dict(medida=m, parcial=p, total=t,
                                   pct=round((t - p) / p * 100, 3) if p else 0))

    DATA = dict(
        generado=datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        mes_curso=MES_CURSO, mes_cerrado=MES_CERRADO,
        dias_mes_curso=DIAS_MES[MES_CURSO],
        kpis=dict(
            dias_curso=dias_curso, total_curso=round(total_curso, 1), prom_curso=round(prom_curso, 1),
            proy_curso=round(proy_curso, 1),
            total_cerr=round(total_cerr, 1), total_parc=round(total_parc, 1), ajuste=round(ajuste, 1),
            ajuste_pct=round(ajuste / total_parc * 100, 3) if total_parc else 0,
            bri_total=round(bri_total, 1), bri_prom=round(bri_prom, 1), bri_proy=round(bri_proy, 1),
            bri_cerr=round(bri_cerr, 1), bri_ener_cerr=round(bri_ener_cerr, 1),
            bri_ener_curso=round(bri_ener_curso, 1),
        ),
        labels_curso=[str(i) for i in range(1, DIAS_MES[MES_CURSO] + 1)],
        labels_cerrado=[str(i) for i in range(1, DIAS_MES[MES_CERRADO] + 1)],
        curso=curso, proy_serie=proy_serie, cerr_total=cerr_total, cerr_parcial=cerr_parcial,
        ajuste_dia=[(cerr_total[i] - cerr_parcial[i]) if (cerr_total[i] and cerr_parcial[i]) else None
                    for i in range(DIAS_MES[MES_CERRADO])],
        acum_serie=acum_serie,
        ajuste_medidas=ajuste_medidas,
        perfil_curso=[perfil.get(MES_CURSO, {}).get(i) for i in range(1, 25)],
        perfil_cerrado=[perfil.get(MES_CERRADO, {}).get(i) for i in range(1, 25)],
        top=top,
        bri_curso=bri_curso, bri_cerrado=bri_daily(MES_CERRADO, "monto"),
        versiones=vers,
    )

    conn.close()

    chartjs = open(CHARTJS, encoding="utf-8").read()
    html = TEMPLATE.replace("/*__DATA__*/", json.dumps(DATA, ensure_ascii=False))
    html = html.replace("/*__CHARTJS__*/", chartjs)
    out = os.path.join(BASE, "dashboard.html")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(html)
    print("Generado:", out, f"({len(html):,} bytes)")


TEMPLATE = r"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dashboard Sustentos CND</title>
<script>/*__CHARTJS__*/</script>
<style>
:root{--bg:#0d1117;--card:#161b22;--card2:#1c2330;--bd:#2a3341;--tx:#e6edf3;--mut:#8b949e;
--acc:#58a6ff;--acc2:#3fb950;--warn:#d29922;--red:#f85149;--pur:#bc8cff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.4 system-ui,Segoe UI,Roboto,sans-serif}
header{padding:18px 24px;border-bottom:1px solid var(--bd);display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px}
h1{font-size:19px;margin:0}
h1 span{color:var(--acc)}
.sub{color:var(--mut);font-size:12px}
.wrap{padding:18px 24px 40px;max-width:1500px;margin:0 auto}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px;margin-bottom:18px}
.kpi{background:linear-gradient(180deg,var(--card2),var(--card));border:1px solid var(--bd);border-radius:12px;padding:14px 16px}
.kpi .lbl{color:var(--mut);font-size:11.5px;text-transform:uppercase;letter-spacing:.4px}
.kpi .val{font-size:24px;font-weight:700;margin-top:6px}
.kpi .val small{font-size:13px;color:var(--mut);font-weight:400}
.kpi .foot{color:var(--mut);font-size:12px;margin-top:4px}
.pos{color:var(--acc2)}.neg{color:var(--red)}.w{color:var(--warn)}.p{color:var(--pur)}
.grid{display:grid;grid-template-columns:repeat(12,1fr);gap:16px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:12px;padding:14px 16px 8px}
.card h3{margin:0 0 4px;font-size:14px}
.card .note{color:var(--mut);font-size:12px;margin-bottom:8px}
.c6{grid-column:span 6}.c12{grid-column:span 12}.c4{grid-column:span 4}.c8{grid-column:span 8}
@media(max-width:1000px){.c6,.c4,.c8{grid-column:span 12}}
canvas{width:100%!important;height:290px!important}
.tall canvas{height:330px!important}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th,td{padding:6px 8px;border-bottom:1px solid var(--bd);text-align:right}
th:first-child,td:first-child{text-align:left}
th{color:var(--mut);font-weight:600;text-transform:uppercase;font-size:11px}
tr.tot td{color:var(--acc);font-weight:700}
.badge{display:inline-block;padding:1px 7px;border-radius:20px;font-size:11px;border:1px solid var(--bd);color:var(--mut)}
.badge.tot{color:var(--acc2);border-color:var(--acc2)}
</style>
</head>
<body>
<header>
  <div>
    <h1>Centro de Control &middot; <span>Sustentos CND</span></h1>
    <div class="sub">Reporte de totales (preliminar vs DTE Sustentos) &middot; generado <b id="gen"></b></div>
  </div>
  <div class="sub">Mes en curso <b id="mc" class="pos"></b> &nbsp;|&nbsp; Mes cerrado <b id="mz" class="p"></b></div>
</header>
<div class="wrap">
  <div class="kpis" id="kpis"></div>
  <div class="grid">
    <div class="card c8"><h3>Evolución diaria del sistema</h3><div class="note">Mes en curso (barras) + proyección de cierre (barras tenues) vs mes cerrado (línea).</div><canvas id="cEvo"></canvas></div>
    <div class="card c4"><h3>Top 12 agentes (mes en curso)</h3><div class="note">Consumo acumulado por agente.</div><canvas id="cTop"></canvas></div>
    <div class="card c6 tall"><h3>"Pintado" del mes por versión</h3><div class="note">Consumo acumulado según cada parcial publicado (así crece el mes).</div><canvas id="cAcum"></canvas></div>
    <div class="card c6 tall"><h3>Parcial vs Total &mdash; mes cerrado</h3><div class="note">Cómo el último parcial se asocia con el total y qué ajusta el final.</div><canvas id="cRev"></canvas></div>
    <div class="card c4"><h3>Ajuste final por medida</h3><div class="note">Variación % (total vs último parcial).</div><canvas id="cMed"></canvas></div>
    <div class="card c4"><h3>Perfil horario promedio</h3><div class="note">Consumo por hora (1–24).</div><canvas id="cHora"></canvas></div>
    <div class="card c4"><h3>BRILLOSOL &mdash; monto ocasional</h3><div class="note">Por día; proyección de cierre.</div><canvas id="cBri"></canvas></div>
    <div class="card c12"><h3>Versiones publicadas</h3><div class="note">Cada archivo descargado y cargado.</div><div id="tabla"></div></div>
  </div>
</div>
<script>
const D = /*__DATA__*/;
document.getElementById('gen').textContent = D.generado;
document.getElementById('mc').textContent = D.mes_curso;
document.getElementById('mz').textContent = D.mes_cerrado;
const nf = (n,d=0)=> (n==null?'—':Number(n).toLocaleString('es-PA',{minimumFractionDigits:d,maximumFractionDigits:d}));

// KPIs
const k = D.kpis;
const kpi = [
 {lbl:'Mes en curso · días', val:k.dias_curso+' <small>/ '+D.dias_mes_curso+'</small>', foot:'progreso del mes'},
 {lbl:'Consumo acumulado (MWh)', val:nf(k.total_curso,0), foot:'promedio '+nf(k.prom_curso,0)+' / día'},
 {lbl:'Proyección cierre (MWh)', val:'<span class="w">'+nf(k.proy_curso,0)+'</span>', foot:'lineal según avance actual'},
 {lbl:'Mes cerrado · total (MWh)', val:nf(k.total_cerr,0), foot:'DTE Sustentos final'},
 {lbl:'Ajuste final del mes', val:'<span class="pos">+'+nf(k.ajuste,0)+'</span>', foot:'+'+nf(k.ajuste_pct,2)+'% vs último parcial'},
 {lbl:'BRILLOSOL · monto acum.', val:''+nf(k.bri_total,0), foot:'proyección '+nf(k.bri_proy,0)},
 {lbl:'BRILLOSOL · mes cerrado', val:''+nf(k.bri_cerr,0), foot:'monto ocasional final'},
];
document.getElementById('kpis').innerHTML = kpi.map(x=>
  `<div class="kpi"><div class="lbl">${x.lbl}</div><div class="val">${x.val}</div><div class="foot">${x.foot}</div></div>`).join('');

const grid='rgba(139,148,158,.12)';
Chart.defaults.color='#8b949e'; Chart.defaults.borderColor=grid; Chart.defaults.font.family='system-ui';
const tip={backgroundColor:'#0d1117',borderColor:'#2a3341',borderWidth:1,padding:10};

// 1 Evolucion
new Chart(cEvo,{type:'bar',data:{labels:D.labels_curso,datasets:[
 {label:'Real',data:D.curso,backgroundColor:'#58a6ff',borderRadius:3,order:2},
 {label:'Proyección',data:D.proy_serie.map((v,i)=>i<k.dias_curso?null:v),backgroundColor:'rgba(210,153,34,.45)',borderRadius:3,order:3},
 {type:'line',label:'Mes cerrado',data:D.cerr_total, borderColor:'#bc8cff',backgroundColor:'transparent',tension:.3,pointRadius:0,borderWidth:2,order:1}
]},options:{plugins:{legend:{position:'bottom'},tooltip:tip},scales:{y:{title:{display:true,text:'MWh'}}}}});

// 2 Top agentes
new Chart(cTop,{type:'bar',data:{labels:D.top.map(t=>t.agente),datasets:[
 {data:D.top.map(t=>t.consumo),backgroundColor:'#3fb950',borderRadius:3}
]},options:{indexAxis:'y',plugins:{legend:{display:false},tooltip:tip},scales:{x:{title:{display:true,text:'MWh'}}}}});

// 3 acumulado por version
const colores=['#58a6ff','#3fb950','#d29922','#bc8cff','#f85149','#39c5cf','#db61a2'];
const dsAcum=Object.keys(D.acum_serie).map((v,i)=>({label:'v'+v,data:D.acum_serie[v],borderColor:colores[i%colores.length],backgroundColor:'transparent',tension:.25,pointRadius:0,borderWidth:2}));
new Chart(cAcum,{type:'line',data:{labels:D.labels_curso,datasets:dsAcum},options:{plugins:{legend:{position:'bottom'},tooltip:tip},scales:{y:{title:{display:true,text:'MWh acumulado'}}}}});

// 4 parcial vs total
new Chart(cRev,{type:'line',data:{labels:D.labels_cerrado,datasets:[
 {type:'line',label:'Último parcial',data:D.cerr_parcial,borderColor:'#d29922',backgroundColor:'transparent',tension:.25,pointRadius:2,borderWidth:2},
 {type:'line',label:'Total (final)',data:D.cerr_total,borderColor:'#3fb950',backgroundColor:'transparent',tension:.25,pointRadius:2,borderWidth:2},
 {type:'bar',label:'Ajuste Δ',data:D.ajuste_dia,backgroundColor:'rgba(248,81,73,.55)',yAxisID:'y1',borderRadius:2}
]},options:{plugins:{legend:{position:'bottom'},tooltip:tip},scales:{y:{title:{display:true,text:'MWh/día'}},y1:{position:'right',grid:{drawOnChartArea:false},title:{display:true,text:'Δ MWh'}}}}});

// 5 ajuste por medida
new Chart(cMed,{type:'bar',data:{labels:D.ajuste_medidas.map(a=>a.medida.replace(/_/g,' ')),datasets:[
 {data:D.ajuste_medidas.map(a=>a.pct),backgroundColor:D.ajuste_medidas.map(a=>a.pct>=0?'#3fb950':'#f85149'),borderRadius:3}
]},options:{plugins:{legend:{display:false},tooltip:{...tip,callbacks:{label:c=>' '+c.parsed.y+' %'}}},scales:{y:{title:{display:true,text:'% variación'}}}}});

// 6 perfil horario
new Chart(cHora,{type:'line',data:{labels:Array.from({length:24},(_,i)=>i+1),datasets:[
 {label:'Mes en curso',data:D.perfil_curso,borderColor:'#58a6ff',backgroundColor:'rgba(88,166,255,.12)',tension:.35,pointRadius:0,borderWidth:2,fill:true},
 {label:'Mes cerrado',data:D.perfil_cerrado,borderColor:'#bc8cff',backgroundColor:'transparent',tension:.35,pointRadius:0,borderWidth:2}
]},options:{plugins:{legend:{position:'bottom'},tooltip:tip},scales:{y:{title:{display:true,text:'MWh/hora'}}}}});

// 7 BRILLOSOL monto
new Chart(cBri,{type:'bar',data:{labels:D.labels_curso,datasets:[
 {label:'Monto ocasional',data:D.bri_curso,backgroundColor:'#d29922',borderRadius:3}
]},options:{plugins:{legend:{display:false},tooltip:tip},scales:{y:{title:{display:true,text:'monto'}}}}});

// Tabla versiones
let rows=D.versiones.map(v=>`<tr><td>${v.periodo}</td><td>${v.reporte_id}</td><td>${v.tipo}</td><td>v${v.version}</td><td>${v.fecha_pub.slice(0,16)}</td><td>${v.dias}</td><td>${nf(v.filas)}</td><td>${nf(v.consumo)}</td></tr>`).join('');
document.getElementById('tabla').innerHTML=`<table><thead><tr><th>Periodo</th><th>ID</th><th>Tipo</th><th>Ver</th><th>Publicado</th><th>Días</th><th>Filas</th><th>Consumo</th></tr></thead><tbody>${rows}</tbody></table>`;
</script>
</body>
</html>"""

if __name__ == "__main__":
    main()
