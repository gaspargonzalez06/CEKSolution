# -*- coding: utf-8 -*-
"""
Extrae los 'reporte_totales_*.csv' (parciales Preliminar + totales DTE Sustentos)
y los carga en MariaDB en una tabla ancha con TODAS las versiones.

Cada version queda identificada por reporte_id / periodo / fecha_pub / version_num,
de modo que se pueda comparar la evolucion (parcial -> total) dentro de la BD.

Uso:
  python extraer_sustento.py                 # carga periodos 202609,202610
  python extraer_sustento.py --periodos 202610
  python extraer_sustento.py --test 20000    # solo N filas por archivo (prueba)
  python extraer_sustento.py --truncate      # borra la tabla antes de cargar
"""
import sys, os, re, glob, json, argparse
import pandas as pd
import pymysql

sys.stdout.reconfigure(errors="replace")
BASE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(BASE, "raw")

KEYS = ["fecha", "hora", "subsistema", "agente", "suplidor"]
MEASURES = [
    "consumo", "consumo_pmo", "perdida_consumo", "energia_asignada", "energia_contrato",
    "suplido_local", "suplido_imp_con", "suplido_imp_opo", "suplido_pos_contratos",
    "suplido_mo", "suplido_mo_imp", "ocasional_venta", "ocasional_compra",
    "ocasional_monto", "opo_energia", "opo_monto_ocasional", "opo_monto_opo",
    "opo_monto_cuspt", "opo_monto_imp", "opo_diferencia", "opo_sobrecosto",
]
# nombre csv en mayusculas -> columna destino
CSV_TO_COL = {m: m for m in MEASURES}


def load_cfg():
    try:
        import yaml
        with open(os.path.join(BASE, "config.yaml"), encoding="utf-8") as f:
            return yaml.safe_load(f)["database"]
    except Exception:
        return dict(host="127.0.0.1", port=3306, database="cek", username="root", password="")


def connect(db):
    return pymysql.connect(host=db["host"], port=int(db["port"]), user=db["username"],
                           password=db.get("password") or "", database=db["database"],
                           charset="utf8mb4", autocommit=False)


def catalog_pubdates():
    """reporte_id -> Timestamp de publicacion (desde /Date(ms)/) del ultimo catalogo."""
    files = sorted(glob.glob(os.path.join(BASE, "catalog_*.json")))
    if not files:
        return {}
    cat = json.load(open(files[-1], encoding="utf-8"))
    out = {}
    for it in cat:
        fp = it.get("fechaPublica") or ""
        m = re.search(r"/Date\((\d+)\)/", fp)
        if m:
            out[str(it["id"])] = pd.to_datetime(int(m.group(1)), unit="ms")
    return out


def discover(periodos):
    found = []
    for f in glob.glob(os.path.join(RAW, "**", "*reporte_totales*.csv"), recursive=True):
        base = os.path.basename(f)
        m = re.match(r"(\d+)_reporte_totales_(\d{4})_(\d{2})", base)
        if not m:
            continue
        rid, anio, mes = m.group(1), m.group(2), m.group(3)
        per = f"{anio}{mes}"
        if periodos and per not in periodos:
            continue
        found.append(dict(path=f, reporte_id=int(rid), periodo=per))
    return found


def solo_unificados(found):
    """Para meses cerrados: si hay reporte unificado (CND_DTE_SUSTENTOS) de un
    periodo, ignora sus parciales (CND_PRELIMINAR_SUSTENTOS). Un periodo sin
    unificado conserva sus parciales (p. ej. el mes en curso). El mes en curso
    siempre conserva todas sus versiones para ver la evolucion."""
    from datetime import datetime as _dt
    actual = _dt.now().strftime("%Y%m")
    por_periodo = {}
    for fl in found:
        por_periodo.setdefault(fl["periodo"], []).append(fl)
    salida = []
    for per, archivos in por_periodo.items():
        if per == actual:
            salida.extend(archivos)
            continue
        unificados = [a for a in archivos if "CND_DTE_SUSTENTOS" in a["path"]]
        salida.extend(unificados if unificados else archivos)
    return salida


def ddl(conn):
    cols_sql = ",\n".join(f"  {m} DECIMAL(20,6) NULL" for m in MEASURES)
    sql = f"""
CREATE TABLE IF NOT EXISTS sustento_horario (
  id BIGINT NOT NULL AUTO_INCREMENT,
  reporte_id INT NOT NULL,
  periodo CHAR(6) NOT NULL,
  fecha_pub DATETIME NULL,
  version_num INT NULL,
  fecha DATE NOT NULL,
  hora TINYINT NULL,
  subsistema VARCHAR(25) NULL,
  agente VARCHAR(25) NULL,
  suplidor VARCHAR(40) NULL,
{cols_sql},
  PRIMARY KEY (id),
  UNIQUE KEY uq_sustento (reporte_id, fecha, hora, subsistema, agente, suplidor),
  KEY ix_periodo_fecha (periodo, fecha),
  KEY ix_agente_fecha (agente, fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"""
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()


def views(conn):
    v1 = """
CREATE OR REPLACE VIEW v_sustento_version AS
SELECT periodo, reporte_id, MAX(fecha_pub) AS fecha_pub, MAX(version_num) AS version_num,
       MIN(fecha) AS desde, MAX(fecha) AS hasta, COUNT(DISTINCT fecha) AS dias,
       COUNT(*) AS filas, SUM(consumo) AS consumo_total
FROM sustento_horario
GROUP BY periodo, reporte_id;"""
    v2 = """
CREATE OR REPLACE VIEW v_sustento_dia AS
SELECT periodo, version_num, reporte_id, fecha, COUNT(*) AS filas, SUM(consumo) AS consumo
FROM sustento_horario
GROUP BY periodo, version_num, reporte_id, fecha;"""
    v3 = """
CREATE OR REPLACE VIEW v_sustento_revision AS
SELECT g.periodo, g.fecha,
       MAX(CASE WHEN g.version_num = f.maxv     THEN g.consumo END) AS consumo_total,
       MAX(CASE WHEN g.version_num = f.maxv - 1 THEN g.consumo END) AS consumo_ultimo_parcial,
       COUNT(*) AS n_versiones
FROM v_sustento_dia g
JOIN (SELECT periodo, MAX(version_num) AS maxv FROM v_sustento_dia GROUP BY periodo) f
  ON f.periodo = g.periodo
GROUP BY g.periodo, g.fecha;"""
    with conn.cursor() as cur:
        for s in (v1, v2, v3):
            cur.execute(s)
    conn.commit()


def resumen(conn):
    """Recalcula las tablas resumen del mercado que usa el dashboard de la API."""
    ddl = [
        """CREATE TABLE IF NOT EXISTS sustento_mercado_resumen (
            periodo CHAR(6) NOT NULL, version_num INT NULL, fecha_pub DATETIME NULL,
            filas BIGINT NOT NULL DEFAULT 0, consumo DOUBLE NULL,
            energia_asignada DOUBLE NULL, ocasional_monto DOUBLE NULL,
            actualizado TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (periodo)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS sustento_agente_resumen (
            periodo CHAR(6) NOT NULL, version_num INT NULL, agente VARCHAR(25) NOT NULL,
            consumo DOUBLE NULL, PRIMARY KEY (periodo, agente),
            KEY ix_resumen_agente (agente)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
    ]
    ins_mercado = """
        INSERT INTO sustento_mercado_resumen
            (periodo, version_num, fecha_pub, filas, consumo, energia_asignada, ocasional_monto)
        SELECT s.periodo, s.version_num, MAX(s.fecha_pub), COUNT(*),
               ROUND(SUM(s.consumo), 1), ROUND(SUM(s.energia_asignada), 1),
               ROUND(SUM(s.ocasional_monto), 1)
        FROM sustento_horario s
        JOIN (SELECT periodo, MAX(version_num) v FROM sustento_horario GROUP BY periodo) m
          ON m.periodo = s.periodo AND m.v = s.version_num
        GROUP BY s.periodo, s.version_num"""
    ins_agente = """
        INSERT INTO sustento_agente_resumen (periodo, version_num, agente, consumo)
        SELECT s.periodo, s.version_num, s.agente, ROUND(SUM(s.consumo), 1)
        FROM sustento_horario s
        JOIN (SELECT periodo, MAX(version_num) v FROM sustento_horario GROUP BY periodo) m
          ON m.periodo = s.periodo AND m.v = s.version_num
        GROUP BY s.periodo, s.version_num, s.agente"""
    with conn.cursor() as cur:
        for s in ddl:
            cur.execute(s)
        cur.execute("DELETE FROM sustento_mercado_resumen")
        cur.execute(ins_mercado)
        cur.execute("DELETE FROM sustento_agente_resumen")
        cur.execute(ins_agente)
    conn.commit()


def read_file(path):
    last = None
    for enc in ("utf-8-sig", "latin-1"):
        try:
            df = pd.read_csv(path, sep=",", encoding=enc, low_memory=False)
            return df
        except Exception as e:
            last = e
    raise last


def prep(df):
    # quita columnas vacias tipo 'Unnamed: 26'
    df = df.loc[:, [c for c in df.columns if not str(c).startswith("Unnamed")]]
    df.columns = [c.strip().lower() for c in df.columns]
    df["fecha"] = pd.to_datetime(df["fecha"], format="%m/%d/%Y", errors="coerce").dt.date
    for c in df.columns:
        if c not in KEYS + ["fecha"]:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--periodos", default="202609,202610")
    ap.add_argument("--test", type=int, default=0)
    ap.add_argument("--truncate", action="store_true")
    ap.add_argument("--solo-unificado", action="store_true",
                    help="meses cerrados: cargar solo el reporte unificado "
                         "(CND_DTE_SUSTENTOS) y omitir los parciales")
    args = ap.parse_args()

    periodos = set(args.periodos.split(",")) if args.periodos else set()
    db = load_cfg()
    conn = connect(db)
    ddl(conn)

    pubdates = catalog_pubdates()
    files = discover(periodos)
    if args.solo_unificado:
        antes = len(files)
        files = solo_unificados(files)
        print(f"[SOLO UNIFICADO] {len(files)} de {antes} archivo(s)")

    # ordenar por fecha de publicacion para asignar version_num
    MIN = pd.Timestamp.min
    files.sort(key=lambda x: (x["periodo"], pubdates.get(str(x["reporte_id"]), MIN)))
    order = {}
    for fl in files:
        order[fl["periodo"]] = order.get(fl["periodo"], 0) + 1
        fl["version_num"] = order[fl["periodo"]]

    if args.truncate:
        with conn.cursor() as cur:
            cur.execute("TRUNCATE TABLE sustento_horario")
        conn.commit()

    cols = ["reporte_id", "periodo", "fecha_pub", "version_num"] + KEYS + MEASURES
    placeholders = ",".join(["%s"] * len(cols))
    insert = f"INSERT IGNORE INTO sustento_horario ({','.join(cols)}) VALUES ({placeholders})"

    print(f"{'reporte_id':>10} {'periodo':>8} {'v':>2} {'pub':19} {'filas':>9}  archivo")
    grand = 0
    for fl in files:
        df = prep(read_file(fl["path"]))
        if args.test:
            df = df.head(args.test)
        fp_ts = pubdates.get(str(fl["reporte_id"]))
        fp = fp_ts.to_pydatetime() if (fp_ts is not None and not pd.isna(fp_ts)) else None
        # arma tuplas rapido
        df = df.reindex(columns=["fecha", "hora", "subsistema", "agente", "suplidor"] + MEASURES)
        df["hora"] = pd.to_numeric(df["hora"], errors="coerce").astype("Int64")
        df.insert(0, "reporte_id", fl["reporte_id"])
        df.insert(1, "periodo", fl["periodo"])
        df.insert(2, "fecha_pub", fp)
        df.insert(3, "version_num", fl["version_num"])
        df = df[cols].where(pd.notna(df), None)
        rows = list(df.itertuples(index=False, name=None))
        with conn.cursor() as cur:
            cur.executemany(insert, rows)
        conn.commit()
        grand += len(rows)
        print(f"{fl['reporte_id']:>10} {fl['periodo']:>8} {fl['version_num']:>2} "
              f"{str(fp)[:19]:19} {len(rows):>9,}  {os.path.basename(fl['path'])[:40]}")

    views(conn)
    print("\nRecalculando tablas resumen del mercado (para el dashboard)...")
    resumen(conn)
    print(f"\nTotal insertado/considerado: {grand:,} filas")
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM sustento_horario")
        print("Filas en sustento_horario:", cur.fetchone()[0])
    conn.close()


if __name__ == "__main__":
    main()
