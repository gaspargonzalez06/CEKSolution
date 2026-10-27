# -*- coding: utf-8 -*-
"""
Muestra COMO se traducen los parciales en el total (mes 2026-09):
 1) acumulacion de filas y CONSUMO por dia a traves de cada version
 2) diferencias entre el ultimo parcial y el total final (DTE Sustentos)
"""
import sys, os
import pandas as pd

sys.stdout.reconfigure(errors="replace")
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")

VERS = [
    ("P1-27d", r"CND\CND_PRELIMINAR_SUSTENTOS\202609\4125972_reporte_totales_2026_09.csv"),
    ("P2-28d", r"CND\CND_PRELIMINAR_SUSTENTOS\202609\4129525_reporte_totales_2026_09.csv"),
    ("P3-29d", r"CND\CND_PRELIMINAR_SUSTENTOS\202609\4132937_reporte_totales_2026_09.csv"),
    ("P4-30d", r"CND\CND_PRELIMINAR_SUSTENTOS\202609\4136154_reporte_totales_2026_09.csv"),
    ("TOTAL ", r"CND\CND_DTE_SUSTENTOS\202609\4143560_reporte_totales_2026_09.csv"),
]

def load(p):
    for enc in ("utf-8-sig", "latin-1"):
        try:
            return pd.read_csv(p, sep=",", encoding=enc, low_memory=False)
        except Exception:
            pass
    raise RuntimeError(p)

frames = {}
for name, rel in VERS:
    df = load(os.path.join(RAW, rel))
    df["_fecha"] = pd.to_datetime(df["FECHA"], format="%m/%d/%Y", errors="coerce").dt.date
    df["_cons"] = pd.to_numeric(df["CONSUMO"], errors="coerce")
    frames[name] = df
    print(f"{name}: {len(df):>8,} filas, {df['_fecha'].nunique()} dias")

print("\n=== Filas y CONSUMO por dia, por version ===")
by_day = {}
for name, df in frames.items():
    g = df.groupby("_fecha").agg(filas=("_cons", "size"), consumo=("_cons", "sum"))
    by_day[name] = g

all_days = sorted(set().union(*[set(g.index) for g in by_day.values()]))
hdr = f"{'dia':>3} | " + " | ".join(f"{n:>22}" for n, _ in VERS)
print(hdr)
for d in all_days:
    cells = []
    for name, _ in VERS:
        g = by_day[name]
        if d in g.index:
            cells.append(f"{int(g.loc[d,'filas']):>9,}/{g.loc[d,'consumo']:>11,.1f}")
        else:
            cells.append(f"{'--':>22}")
    print(f"{d.day:>3} | " + " | ".join(cells))

print("\n=== Ultimo parcial (P4) vs TOTAL: filas por dia ===")
g4 = by_day["P4-30d"]["filas"]
gt = by_day["TOTAL "]["filas"]
diff_rows = (gt - g4.reindex(gt.index)).fillna(0).astype(int)
print("dias con distinto # filas:", (diff_rows != 0).sum())
print(diff_rows[diff_rows != 0].to_string() or "  (ninguno)")

print("\n=== Ultimo parcial (P4) vs TOTAL: CONSUMO por dia (delta) ===")
c4 = by_day["P4-30d"]["consumo"]
ct = by_day["TOTAL "]["consumo"]
delta = (ct - c4.reindex(ct.index))
print(f"delta total del mes: {delta.sum():,.2f}")
print("top 5 dias con mayor diferencia:")
print(delta.abs().sort_values(ascending=False).head(5).to_string())

# Comparacion a nivel de celda (solo CONSUMO) usando llave fecha/hora/agente/suplidor
print("\n=== Comparacion a nivel de fila: P4 vs TOTAL (CONSUMO) ===")
keys = ["FECHA", "HORA", "AGENTE", "SUPLIDOR"]
p4 = frames["P4-30d"][keys + ["CONSUMO"]].copy()
tt = frames["TOTAL "][keys + ["CONSUMO"]].copy()
p4["CONSUMO"] = pd.to_numeric(p4["CONSUMO"], errors="coerce")
tt["CONSUMO"] = pd.to_numeric(tt["CONSUMO"], errors="coerce")
m = p4.merge(tt, on=keys, how="outer", suffixes=("_p4", "_tot"), indicator=True)
print("llaves solo en P4 :", (m["_merge"] == "left_only").sum())
print("llaves solo en TOTAL:", (m["_merge"] == "right_only").sum())
both = m[m["_merge"] == "both"].copy()
both["d"] = (both["CONSUMO_tot"] - both["CONSUMO_p4"]).abs()
n_diff = (both["d"] > 1e-9).sum()
print(f"llaves comunes: {len(both):,} | con CONSUMO distinto: {n_diff:,} "
      f"({100*n_diff/max(len(both),1):.3f}%)")
if n_diff:
    print("mayores correcciones (P4 -> TOTAL):")
    print(both.sort_values("d", ascending=False)
          [keys + ["CONSUMO_p4", "CONSUMO_tot"]].head(8).to_string(index=False))
