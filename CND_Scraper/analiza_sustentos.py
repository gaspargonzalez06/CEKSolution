# -*- coding: utf-8 -*-
"""
Analiza los 'reporte_totales_*.csv' (parciales Preliminar y totales DTE Sustentos)
para ver como se traducen los parciales en el total.

No modifica nada: solo lee los crudos de raw\\ y reporta:
  - filas, rango de fechas, #dias, #agentes
  - suma de CONSUMO y de columnas economicas (si existen)
  - cobertura de fechas por archivo
"""
import sys, os, glob
import pandas as pd

sys.stdout.reconfigure(errors="replace")

RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")

def read_csv(path):
    last = None
    for enc in ("utf-8-sig", "latin-1"):
        try:
            return pd.read_csv(path, sep=",", encoding=enc, low_memory=False)
        except Exception as e:  # noqa
            last = e
    raise last

def num(df, col):
    if col not in df.columns:
        return None
    s = pd.to_numeric(df[col], errors="coerce")
    return float(s.sum(skipna=True))

def main():
    files = glob.glob(os.path.join(RAW, "**", "*reporte_totales*.csv"), recursive=True)
    files.sort()
    print(f"Encontrados {len(files)} archivos reporte_totales\n")
    header = f"{'archivo':52} {'filas':>9} {'dias':>5} {'desde':>10} {'hasta':>10} {'agentes':>8} {'SUM_CONSUMO':>14}"
    print(header)
    print("-" * len(header))
    details = []
    for f in files:
        rel = os.path.relpath(f, RAW)
        try:
            df = read_csv(f)
        except Exception as e:
            print(f"{rel:52} ERROR {e}")
            continue
        fecha = pd.to_datetime(df["FECHA"], format="%m/%d/%Y", errors="coerce")
        dias = fecha.dt.date.nunique()
        dmin = fecha.min()
        dmax = fecha.max()
        n_ag = df["AGENTE"].nunique() if "AGENTE" in df.columns else -1
        cons = num(df, "CONSUMO")
        short = os.path.basename(os.path.dirname(f)) + "/" + os.path.basename(f)
        cons_txt = f"{cons:,.2f}" if cons is not None else "-"
        print(f"{short[:52]:52} {len(df):>9,} {dias:>5} "
              f"{str(dmin)[:10]:>10} {str(dmax)[:10]:>10} {n_ag:>8} {cons_txt:>14}")
        details.append(dict(rel=rel, filas=len(df), dias=dias,
                            dmin=str(dmin)[:10], dmax=str(dmax)[:10],
                            agentes=n_ag, consumo=cons,
                            fechas=sorted(set(fecha.dt.strftime('%Y-%m-%d').dropna()))))

    print("\n\n=== Cobertura de fechas por archivo ===")
    for d in details:
        fs = d["fechas"]
        if not fs:
            print(f"{d['rel']}: (sin fechas)")
            continue
        print(f"{d['rel']}")
        print(f"   {fs[0]} .. {fs[-1]}  ({len(fs)} dias)")

if __name__ == "__main__":
    main()
