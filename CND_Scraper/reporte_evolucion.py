# -*- coding: utf-8 -*-
"""
Reporte de evolucion desde la BD (sustento_horario):
  1) versiones por periodo
  2) matriz fecha x version  (consumo diario segun cada parcial/total)
  3) revision: total vs ultimo parcial por dia (delta y %)
Exporta CSV a  .\\analisis\\  y muestra en consola.
"""
import sys, os
import pandas as pd
from sqlalchemy import create_engine

sys.stdout.reconfigure(errors="replace")
BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "analisis")
os.makedirs(OUT, exist_ok=True)


def load_cfg():
    try:
        import yaml
        with open(os.path.join(BASE, "config.yaml"), encoding="utf-8") as f:
            return yaml.safe_load(f)["database"]
    except Exception:
        return dict(host="127.0.0.1", port=3306, database="cek", username="root", password="")


def q(conn, sql):
    return pd.read_sql(sql, conn)


def main():
    db = load_cfg()
    conn = create_engine(
        f"mysql+pymysql://{db['username']}:{db.get('password') or ''}"
        f"@{db['host']}:{int(db['port'])}/{db['database']}?charset=utf8mb4")

    print("=" * 70)
    print("1) VERSIONES POR PERIODO")
    print("=" * 70)
    ver = q(conn, "SELECT * FROM v_sustento_version ORDER BY periodo, version_num")
    ver["consumo_total"] = ver["consumo_total"].astype(float)
    print(ver.to_string(index=False))
    ver.to_csv(os.path.join(OUT, "evolucion_versiones.csv"), index=False, encoding="utf-8-sig")

    for per in sorted(ver["periodo"].unique()):
        print("\n" + "=" * 70)
        print(f"2) EVOLUCION DIARIA - periodo {per} (consumo por dia y version)")
        print("=" * 70)
        dia = q(conn, f"""
            SELECT fecha, version_num, consumo
            FROM v_sustento_dia WHERE periodo='{per}'
            ORDER BY fecha, version_num""")
        dia["fecha"] = pd.to_datetime(dia["fecha"])
        piv = dia.pivot_table(index="fecha", columns="version_num", values="consumo", aggfunc="sum")
        piv.columns = [f"v{int(c)}" for c in piv.columns]
        piv.index = piv.index.strftime("%Y-%m-%d")
        piv = piv.round(1)
        print(piv.to_string())
        piv.to_csv(os.path.join(OUT, f"evolucion_diaria_{per}.csv"), encoding="utf-8-sig")

    print("\n" + "=" * 70)
    print("3) REVISION: total (ultima version) vs ultimo parcial, por dia")
    print("=" * 70)
    rev = q(conn, "SELECT * FROM v_sustento_revision ORDER BY periodo, fecha")
    rev = rev.dropna(subset=["consumo_ultimo_parcial"], how="all")
    rev["fecha"] = pd.to_datetime(rev["fecha"])
    rev["delta"] = (rev["consumo_total"] - rev["consumo_ultimo_parcial"]).astype(float)
    rev["pct"] = (rev["delta"] / rev["consumo_ultimo_parcial"].astype(float) * 100).round(4)
    for per in sorted(rev["periodo"].unique()):
        sub = rev[rev["periodo"] == per].copy()
        sub["fecha"] = sub["fecha"].dt.strftime("%Y-%m-%d")
        sub["consumo_total"] = sub["consumo_total"].astype(float).round(2)
        sub["consumo_ultimo_parcial"] = sub["consumo_ultimo_parcial"].astype(float).round(2)
        sub["delta"] = sub["delta"].round(2)
        print(f"\n--- periodo {per} (delta mes = {sub['delta'].sum():,.2f}) ---")
        print(sub[["fecha", "consumo_ultimo_parcial", "consumo_total", "delta", "pct"]].to_string(index=False))
    rev.to_csv(os.path.join(OUT, "evolucion_revision.csv"), index=False, encoding="utf-8-sig")
    print(f"\nCSV exportados en: {OUT}")
    # Excel consolidado para revision visual
    xlsx = os.path.join(OUT, "Evolucion_Sustentos.xlsx")
    xw = pd.ExcelWriter(xlsx, engine="openpyxl")
    pd.read_csv(os.path.join(OUT, "evolucion_versiones.csv")).to_excel(xw, sheet_name="Versiones", index=False)
    for per in sorted(ver["periodo"].unique()):
        pd.read_csv(os.path.join(OUT, f"evolucion_diaria_{per}.csv")).to_excel(
            xw, sheet_name=f"Diaria_{per}", index=False)
    pd.read_csv(os.path.join(OUT, "evolucion_revision.csv")).to_excel(xw, sheet_name="Revision", index=False)
    xw.close()
    print(f"Excel: {xlsx}")
    conn.dispose()


if __name__ == "__main__":
    main()
