#!/usr/bin/env python3
"""
CND SYNC - scraper headless (sin ventanas) que baja los reportes del portal CND
y los guarda CRUDOS en disco + los registra en MariaDB.

- Login headless con Playwright (sin pestanas visibles).
- Catalogo via API JSON paginada (encuentra TODOS los tipos, no solo la pagina 1).
- Por defecto baja SOLO formatos NO-Excel (csv, txt).
- Guarda el archivo crudo en ./raw/<cliente>/<tipo>/<periodo>/ y en MariaDB
  guarda metadatos + columnas + una muestra (no revienta la BD con 23 MB).
- Incremental: no vuelve a bajar lo que ya esta en raw_data (por reporte_id).

Uso:
    python cnd_sync.py                       # csv, txt (no excel)
    python cnd_sync.py --all                 # todo (incluye xlsx/xls/xlsm)
    python cnd_sync.py --ext csv,txt,zip,pdf # formatos especificos
    python cnd_sync.py --pages 60            # mas historial (20 items/pagina)
    python cnd_sync.py --limit 10            # maximo 10 archivos
    python cnd_sync.py --catalog-only        # solo listar, no descargar
    python cnd_sync.py --no-incremental      # re-descargar todo
"""
import argparse
import asyncio
import hashlib
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import aiomysql
import pandas as pd
import yaml
from playwright.async_api import async_playwright

# Consola Windows (cp1252): evitar crash por caracteres unicode en mensajes
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(errors="replace")
    except Exception:
        pass

ROOT = Path(__file__).resolve().parent
CFG = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))

DB = CFG["database"]
PORTAL = CFG["portal"]
PORTAL_BASE = "https://sitioprivado.cnd.com.pa"
AGENTES = CFG["agentes"]
EXCEL_EXTS = {"xlsx", "xls", "xlsm", "xlsb"}

# Archivos de Ajuste/Reclamo: sufijo _Aj1, _Aj2, ... o nombres "Ajuste_AJ1_..."
AJUSTE_RE = re.compile(r"(?:^|[_/])aj(?:uste)?\d", re.I)

# ---------------------------------------------------------------------------
# Perfiles de descarga: solo lo que la app realmente consume.
#
#   facturacion        -> liquidacion (mediciones), DTE tabular, detalle de
#                         perdidas y DTER oficial.  Son los archivos por agente.
#   sustento_unificado -> reporte_totales del DTE (un archivo por mes cerrado).
#   sustento_parcial   -> reporte_totales preliminar (diario; util para el mes
#                         en curso, cuando aun no hay unificado).
#
# La coincidencia es por carpeta de tipo (`tipo.directory`) y, si se indica,
# por subcadena del nombre de archivo.  Los formatos por tipo están fijados a
# los que abren los importadores: asi no se bajan GB de xlsx que nadie usa.
# ---------------------------------------------------------------------------
PERFIL_SECCIONES = {
    "facturacion": {
        "tipos": {
            "CND_DTE_LIQUIDACION": {"xlsx"},
            "CND_DTE_TABULAR": {"txt"},
            "CND_DTE_DETALLE_PERDIDAS": {"xlsx"},
            "CND_DTER_OFICIAL": {"xlsx"},
        },
    },
    "sustento_unificado": {
        "tipos": {"CND_DTE_SUSTENTOS": {"csv"}},
        "nombres": ["reporte_totales"],
    },
    "sustento_parcial": {
        "tipos": {"CND_PRELIMINAR_SUSTENTOS": {"csv"}},
        "nombres": ["reporte_totales"],
    },
}

# Perfil recomendado por la app: todo lo necesario para operar.
PERFIL_ESENCIAL = "facturacion,sustento_unificado"


def coincide_perfil(tipo_dir, nombre, ext, secciones):
    """True si el archivo cae dentro de alguno de los perfiles pedidos.

    `secciones` es una lista ya normalizada (minusculas).  La sección "todo"
    deja pasar cualquier archivo.
    """
    if not secciones:
        return True
    ext = (ext or "").lower().lstrip(".")
    nombre_l = (nombre or "").lower()
    for sec in secciones:
        if sec == "todo":
            return True
        reglas = PERFIL_SECCIONES.get(sec)
        if not reglas:
            continue
        tipos = reglas.get("tipos")
        if tipos is not None:
            exts = tipos.get(tipo_dir)
            if exts is None or ext not in exts:
                continue
        nombres = reglas.get("nombres")
        if nombres and not any(n in nombre_l for n in nombres):
            continue
        return True
    return False


def es_ajuste(nombre):
    """True si el nombre de archivo corresponde a un ajuste/reclamo (Aj1, Aj2...)."""
    return bool(AJUSTE_RE.search(nombre or ""))


def list_url(page, anio=None, mes=None, tipo=0):
    """URL del listado. Si se indica anio/mes, el portal filtra ese mes.

    Sin filtro (anio=null&mes=0) el portal solo devuelve los meses recientes;
    con anio/mes trae el historial completo de ese mes.
    Si tipo>0 el portal devuelve solo ese tipo de reporte (id de tipo).
    """
    a = "null" if anio is None else str(anio)
    m = 0 if mes is None else int(mes)
    t = 0 if tipo is None else int(tipo)
    return (PORTAL_BASE + "/Informe/GetListOperativosComerciales"
            f"?page={page}&tipo={t}&categoria=0&anio={a}&mes={m}&semana=0&publico=0")

# ---------------------------------------------------------------- schema
SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS scraping_log (
        id BIGINT NOT NULL AUTO_INCREMENT,
        cliente_codigo VARCHAR(20) NOT NULL,
        cliente_nombre VARCHAR(100) DEFAULT NULL,
        periodo CHAR(6) NOT NULL,
        reporte_tipo VARCHAR(50) NOT NULL,
        archivo_nombre VARCHAR(255) NOT NULL,
        archivo_hash CHAR(64) NOT NULL,
        archivo_tamano BIGINT DEFAULT NULL,
        estado ENUM('PENDIENTE','PROCESANDO','PROCESADO','ERROR','SALTADO') DEFAULT 'PENDIENTE',
        registros_nuevos INT DEFAULT 0,
        registros_actualizados INT DEFAULT 0,
        error_mensaje TEXT DEFAULT NULL,
        fecha_inicio DATETIME DEFAULT CURRENT_TIMESTAMP,
        fecha_fin DATETIME DEFAULT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uk_scraping_log (cliente_codigo, periodo, reporte_tipo, archivo_hash),
        INDEX idx_scraping_cliente_periodo (cliente_codigo, periodo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS raw_data (
        id BIGINT NOT NULL AUTO_INCREMENT,
        cliente_codigo VARCHAR(20) NOT NULL,
        periodo CHAR(6) NOT NULL,
        reporte_tipo VARCHAR(50) NOT NULL,
        archivo_nombre VARCHAR(255) NOT NULL,
        archivo_hash CHAR(64) NOT NULL,
        archivo_tamano BIGINT DEFAULT NULL,
        data_json LONGTEXT NOT NULL,
        campos_detectados JSON DEFAULT NULL,
        archivo_origen VARCHAR(255) DEFAULT NULL,
        fecha_carga DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uk_raw_data (cliente_codigo, periodo, reporte_tipo, archivo_hash),
        INDEX idx_raw_cliente_periodo (cliente_codigo, periodo),
        INDEX idx_raw_tipo (reporte_tipo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
]


async def connect_db():
    return await aiomysql.connect(
        host=DB["host"], port=int(DB["port"]), user=DB["username"],
        password=DB["password"], db=DB["database"], charset="utf8mb4",
        autocommit=True,
    )


async def ensure_schema(conn):
    async with conn.cursor() as cur:
        for stmt in SCHEMA:
            await cur.execute(stmt)
        # columnas para scraping incremental
        for stmt in (
            "ALTER TABLE raw_data ADD COLUMN IF NOT EXISTS reporte_id BIGINT DEFAULT NULL",
            "ALTER TABLE scraping_log ADD COLUMN IF NOT EXISTS reporte_id BIGINT DEFAULT NULL",
        ):
            try:
                await cur.execute(stmt)
            except Exception:
                pass


async def already_have(conn, cliente, reporte_tipo, reporte_id):
    async with conn.cursor() as cur:
        await cur.execute(
            "SELECT 1 FROM raw_data WHERE cliente_codigo=%s AND reporte_tipo=%s AND reporte_id=%s LIMIT 1",
            (cliente, reporte_tipo, reporte_id))
        return await cur.fetchone() is not None


# ---------------------------------------------------------------- helpers
def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def fname_from_path(p: str) -> str:
    return (p or "").replace("\\", "/").split("/")[-1]


async def fetch_with_retry(ctx, url, *, retries=5, timeout=30000):
    """GET con reintentos; devuelve Response o None."""
    last = None
    for intento in range(1, retries + 1):
        try:
            return await ctx.request.get(url, timeout=timeout)
        except Exception as e:
            last = e
            print(f"        (reintento {intento}/{retries} {url.split('?')[0]}: {str(e)[:80]})")
            await asyncio.sleep(2 * intento)
    print(f"        [WARN] fallo definitivo: {last}")
    return None


def periodo_of(item) -> str:
    anio = item.get("anio") or 0
    mes = ((item.get("mes") or {}).get("numero")) or 0
    return f"{anio:04d}{mes:02d}"


def decode_bytes(raw: bytes) -> str:
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1", errors="replace")


PREVIEW_ROWS = 100


def parse_content(ext: str, raw: bytes):
    """Devuelve (data_json, columnas, n_rows, aviso).
    Solo guarda una MUESTRA (no el archivo completo) para no reventar la BD."""
    ext = ext.lower().lstrip(".")
    info = {"formato": ext, "bytes": len(raw)}
    cols, n = [], 0
    try:
        if ext in ("csv", "txt"):
            text = decode_bytes(raw)
            info["filas_totales"] = text.count("\n")
            sep = "\t" if ext == "txt" else ","
            df = pd.read_csv(pd.io.common.StringIO(text), sep=sep, dtype=str,
                             nrows=PREVIEW_ROWS, on_bad_lines="skip")
            cols = [str(c).strip() for c in df.columns]
            info["columnas"] = cols
            info["muestra"] = df.fillna("").to_dict(orient="records")
            n = info["filas_totales"]
        elif ext in ("xlsx", "xlsm", "xls"):
            engine = "openpyxl" if ext in ("xlsx", "xlsm") else None
            df = pd.read_excel(pd.io.common.BytesIO(raw), dtype=str, engine=engine,
                               nrows=PREVIEW_ROWS)
            cols = [str(c).strip() for c in df.columns]
            info["columnas"] = cols
            info["muestra"] = df.fillna("").to_dict(orient="records")
            n = len(df)
        else:
            info["nota"] = "formato binario guardado en disco (sin parseo)"
    except Exception as e:
        info["aviso"] = str(e)[:300]
    return json.dumps(info, ensure_ascii=False, default=str), cols, n, info.get("aviso")


async def save_raw(conn, *, cliente_codigo, cliente_nombre, periodo, reporte_tipo,
                   archivo_nombre, archivo_hash, archivo_tamano, data_json,
                   campos, origen, reporte_id=None):
    async with conn.cursor() as cur:
        await cur.execute(
            """INSERT INTO raw_data
               (cliente_codigo, periodo, reporte_tipo, archivo_nombre, archivo_hash,
                archivo_tamano, data_json, campos_detectados, archivo_origen, reporte_id)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               ON DUPLICATE KEY UPDATE
                 data_json=VALUES(data_json), archivo_tamano=VALUES(archivo_tamano),
                 campos_detectados=VALUES(campos_detectados), reporte_id=VALUES(reporte_id),
                 fecha_carga=NOW()""",
            (cliente_codigo, periodo, reporte_tipo, archivo_nombre, archivo_hash,
             archivo_tamano, data_json, json.dumps(campos, ensure_ascii=False), origen,
             reporte_id),
        )
        await cur.execute(
            """INSERT INTO scraping_log
               (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre,
                archivo_hash, archivo_tamano, estado, registros_nuevos, fecha_fin, reporte_id)
               VALUES (%s,%s,%s,%s,%s,%s,%s,'PROCESADO',%s,NOW(),%s)
               ON DUPLICATE KEY UPDATE
                 estado='PROCESADO', registros_nuevos=VALUES(registros_nuevos),
                 archivo_tamano=VALUES(archivo_tamano), fecha_fin=NOW(),
                 error_mensaje=NULL, reporte_id=VALUES(reporte_id)""",
            (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre,
             archivo_hash, archivo_tamano, 0, reporte_id),
        )


async def log_error(conn, *, cliente_codigo, cliente_nombre, periodo, reporte_tipo,
                    archivo_nombre, archivo_hash, tamano, error):
    async with conn.cursor() as cur:
        await cur.execute(
            """INSERT INTO scraping_log
               (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre,
                archivo_hash, archivo_tamano, estado, error_mensaje, fecha_fin)
               VALUES (%s,%s,%s,%s,%s,%s,%s,'ERROR',%s,NOW())
               ON DUPLICATE KEY UPDATE estado='ERROR', error_mensaje=VALUES(error_mensaje),
                 fecha_fin=NOW()""",
            (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre,
             archivo_hash, tamano, error[:2000]),
        )


# ---------------------------------------------------------------- playwright
async def login_and_fetch_catalog(headless=True, max_pages=20, usuario=None, password=None,
                                  meses=None, tipo_ids=None):
    """Login headless y devuelve (context, catalog list).

    Si se pasan usuario/password, se usan esos (los del agente del backend);
    si no, se toma el primero de config.yaml.

    `meses` es una lista de (anio, mes) a consultar por separado (el portal
    filtra por mes); si es None se usa el listado sin filtro (meses recientes).
    """
    usuario = usuario or os.environ.get("CND_USER") or next(iter(AGENTES.values()))["usuario"]
    password = password or os.environ.get("CND_PASSWORD") or next(iter(AGENTES.values()))["password"]
    p = await async_playwright().start()
    browser = await p.chromium.launch(headless=headless)
    ctx = await browser.new_context(viewport={"width": 1366, "height": 900},
                                    accept_downloads=True)
    page = await ctx.new_page()
    page.set_default_timeout(60000)

    login_cfg = PORTAL["login"]
    print(f"[LOGIN] {PORTAL['login_url']}  (usuario={usuario})")
    await page.goto(PORTAL["login_url"], wait_until="domcontentloaded")
    await asyncio.sleep(3)
    await page.fill(login_cfg["username_selector"], usuario)
    await page.fill(login_cfg["password_selector"], password)
    await page.click(login_cfg["submit_selector"])
    await page.wait_for_load_state("networkidle")
    await asyncio.sleep(5)
    if await page.query_selector(login_cfg["username_selector"]):
        raise RuntimeError("Login fallo - sigue en pagina de login")
    print("[LOGIN] OK")

    # catalogo paginado (20 por pagina). Si se pasa `meses`, consulta mes por mes.
    # Si se pasan `tipo_ids`, consulta solo esos tipos (el portal filtra por tipo).
    catalog, seen = [], set()
    consultas = meses if meses else [(None, None)]
    tipos = tipo_ids if tipo_ids else [0]
    combos = [(a, m, t) for (a, m) in consultas for t in tipos]
    for anio, mes, tipo in combos:
        if meses or tipo:
            etiqueta = [] if not meses else [f"mes {anio}-{mes:02d}"]
            if tipo:
                etiqueta.append(f"tipo {tipo}")
            print(f"[CATALOGO] === {' / '.join(etiqueta)} ===")
        page_n, fallos = 1, 0
        while page_n <= max_pages:
            resp = await fetch_with_retry(ctx, list_url(page_n, anio, mes, tipo))
            if resp is None or resp.status != 200:
                fallos += 1
                print(f"[CATALOGO] pagina {page_n}: fallo ({fallos} consecutivo(s))")
                if fallos >= 3:
                    print("[CATALOGO] 3 fallos consecutivos, fin del mes.")
                    break
                page_n += 1
                continue
            fallos = 0
            data = await resp.json()
            if not data:
                break
            nuevos = 0
            for it in data:
                if it.get("id") and it["id"] not in seen:
                    seen.add(it["id"])
                    catalog.append(it)
                    nuevos += 1
            print(f"[CATALOGO] pagina {page_n}/{max_pages}: {len(data)} items "
                  f"({nuevos} nuevos, total {len(catalog)})")
            if nuevos == 0:
                break
            page_n += 1

    return p, browser, ctx, catalog


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="incluir Excel")
    ap.add_argument("--ext", default=None,
                    help="extensiones separadas por coma (def: csv,txt; se ignora si se usa --perfil)")
    ap.add_argument("--perfil", default="",
                    help="solo lo que usa la app: facturacion, sustento_unificado, "
                         "sustento_parcial o todo (varios separados por coma)")
    ap.add_argument("--limit", type=int, default=0, help="maximo de archivos (0=todos)")
    ap.add_argument("--pages", type=int, default=25, help="paginas del listado a escanear (20 items c/u)")
    ap.add_argument("--catalog-only", action="store_true")
    ap.add_argument("--raw-dir", default=None, help="carpeta para guardar los crudos (def: ./raw)")
    ap.add_argument("--no-incremental", action="store_true", help="re-descargar aunque ya exista")
    ap.add_argument("--headful", action="store_true", help="mostrar ventana (debug)")
    ap.add_argument("--user", default=None, help="usuario del portal (sobreescribe config.yaml)")
    ap.add_argument("--password", default=None, help="clave del portal (sobreescribe config.yaml)")
    ap.add_argument("--meses", type=int, default=0,
                    help="bajar solo los ultimos N meses (consulta el portal mes a mes)")
    ap.add_argument("--hasta-mes", default=None,
                    help="mes ancla AAAAMM para --meses (def: mes actual)")
    ap.add_argument("--tipos", default="",
                    help="filtrar por nombre de tipo (subcadenas separadas por coma)")
    ap.add_argument("--tipo-ids", default="",
                    help="filtrar por id de tipo en el portal (ids separados por coma)")
    ap.add_argument("--ajustes", action="store_true",
                    help="bajar SOLO los archivos de ajuste/reclamo (Aj1, Aj2..., Ajuste_*) "
                         "en cualquier formato, ignorando --ext")
    args = ap.parse_args()
    args.incremental = not args.no_incremental

    tipo_ids = [int(x) for x in args.tipo_ids.split(",") if x.strip()]
    tipos_filtro = [t.strip().lower() for t in args.tipos.split(",") if t.strip()]

    meses = None
    if args.meses:
        base = (datetime.strptime(args.hasta_mes, "%Y%m")
                if args.hasta_mes else datetime.now())
        y, m = base.year, base.month
        meses = []
        for _ in range(args.meses):
            meses.append((y, m))
            m -= 1
            if m == 0:
                m, y = 12, y - 1
        meses.reverse()
        print("[MESES] consultando:", ", ".join(f"{a}-{mm:02d}" for a, mm in meses))

    perfil_secs = [s.strip().lower() for s in args.perfil.split(",") if s.strip()]
    if args.all:
        wanted = None
    elif args.ext is not None:
        wanted = {e.strip().lower().lstrip(".") for e in args.ext.split(",") if e.strip()}
    elif perfil_secs:
        wanted = None  # el perfil ya fija los formatos por tipo
    else:
        wanted = {"csv", "txt"}
    if perfil_secs:
        print("[PERFIL]", ", ".join(perfil_secs))

    print("=" * 64)
    print("CND SYNC  |  headless  |  MariaDB:", f"{DB['host']}:{DB['port']}/{DB['database']}")
    print("=" * 64)

    p, browser, ctx, catalog = await login_and_fetch_catalog(headless=not args.headful,
                                                             max_pages=args.pages,
                                                             usuario=args.user,
                                                             password=args.password,
                                                             meses=meses,
                                                             tipo_ids=tipo_ids)

    # resumen de catalogo
    resumen = {}
    for it in catalog:
        tipo = it.get("tipo") or {}
        ext = fname_from_path((it.get("adjunto") or {}).get("path", "")).rsplit(".", 1)[-1].lower()
        resumen.setdefault(tipo.get("name", "?"), {}).setdefault(ext, 0)
        resumen[tipo.get("name", "?")][ext] += 1
    print("\n--- CATALOGO COMPLETO ---")
    for tipo, exts in sorted(resumen.items()):
        print(f"  {tipo}: {exts}")
    print(f"  TOTAL reportes: {len(catalog)}\n")

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    (ROOT / f"catalog_{stamp}.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[OK] catalogo guardado: catalog_{stamp}.json")

    if args.catalog_only:
        await ctx.close()
        await browser.close()
        await p.stop()
        return

    # seleccionar
    downloads = []
    for it in catalog:
        adj = it.get("adjunto") or {}
        if not adj.get("path"):
            continue
        nombre = fname_from_path(adj["path"])
        ext = nombre.rsplit(".", 1)[-1].lower() if "." in nombre else ""
        tipo = it.get("tipo") or {}
        tipo_dir = (tipo.get("directory") or tipo.get("name") or "OTROS")[:50]
        if args.ajustes:
            if not es_ajuste(nombre):
                continue
        elif wanted is not None and ext not in wanted:
            continue
        if tipos_filtro:
            nt = (tipo.get("name") or "").lower()
            if not any(t in nt for t in tipos_filtro):
                continue
        if not coincide_perfil(tipo_dir, nombre, ext, perfil_secs):
            continue
        downloads.append((it, nombre, ext))
    if args.limit:
        downloads = downloads[: args.limit]

    filtro_txt = "TODOS" if wanted is None else sorted(wanted)
    if perfil_secs:
        filtro_txt = f"perfil={'+'.join(perfil_secs)}"
    print(f"[DESCARGA] {len(downloads)} archivo(s) seleccionado(s) "
          f"(filtro: {filtro_txt})\n")

    raw_root = (ROOT / "raw") if not args.raw_dir else Path(args.raw_dir)

    conn = await connect_db()
    await ensure_schema(conn)

    ok = err = skip = 0
    for i, (it, nombre, ext) in enumerate(downloads, 1):
        rid = it["id"]
        tipo = (it.get("tipo") or {})
        tipo_dir = (tipo.get("directory") or tipo.get("name") or "OTROS")[:50]
        agente = (it.get("agente") or {})
        cliente = (agente.get("codigo") or "CND")[:20]
        cliente_nombre = (agente.get("nombre") or tipo.get("name") or "CND")[:100]
        periodo = periodo_of(it)
        url = f"{PORTAL_BASE}/Informe/Download/{rid}"
        origen = (it.get("adjunto") or {}).get("path")

        if args.incremental and await already_have(conn, cliente, tipo_dir, rid):
            print(f"  [{i}/{len(downloads)}] {nombre}  -> ya existe (skip)")
            skip += 1
            continue

        print(f"  [{i}/{len(downloads)}] {nombre}  ({tipo.get('name')})")
        try:
            resp = await fetch_with_retry(ctx, url, timeout=120000)
            if resp is None:
                raise RuntimeError("sin respuesta tras reintentos")
            body = await resp.body()
            if resp.status != 200 or not body:
                raise RuntimeError(f"HTTP {resp.status} / {len(body)} bytes")
            h = sha256(body)

            # guardar el CRUDO en disco (organizado)
            dest = raw_root / cliente / tipo_dir / periodo
            dest.mkdir(parents=True, exist_ok=True)
            local = dest / f"{rid}_{nombre}"
            local.write_bytes(body)

            data_json, cols, nrows, aviso = parse_content(ext, body)
            data_json = json.dumps(
                dict(json.loads(data_json), archivo_local=str(local)), ensure_ascii=False)
            await save_raw(conn, cliente_codigo=cliente, cliente_nombre=cliente_nombre,
                           periodo=periodo, reporte_tipo=tipo_dir, archivo_nombre=nombre,
                           archivo_hash=h, archivo_tamano=len(body), data_json=data_json,
                           campos=cols, origen=origen, reporte_id=rid)
            print(f"        OK  {len(body):,} bytes | {nrows} filas | cols: {cols[:8]}"
                  + (f" | aviso: {aviso}" if aviso else ""))
            print(f"        -> {local}")
            ok += 1
        except Exception as e:
            print(f"        ERROR: {e}")
            try:
                await log_error(conn, cliente_codigo=cliente, cliente_nombre=cliente_nombre,
                                periodo=periodo, reporte_tipo=tipo_dir, archivo_nombre=nombre,
                                archivo_hash="0" * 64, tamano=0, error=str(e))
            except Exception:
                pass
            err += 1

    # conteos finales
    async with conn.cursor(aiomysql.DictCursor) as cur:
        await cur.execute("SELECT COUNT(*) AS n FROM raw_data")
        nraw = (await cur.fetchone())["n"]
        await cur.execute("SELECT COUNT(*) AS n FROM scraping_log")
        nlog = (await cur.fetchone())["n"]
    conn.close()

    print("\n" + "=" * 64)
    print(f"RESULTADO: {ok} ok, {skip} omitidos (ya existian), {err} error(es)")
    print(f"MariaDB -> raw_data: {nraw} fila(s) | scraping_log: {nlog} fila(s)")
    print("=" * 64)

    await ctx.close()
    await browser.close()
    await p.stop()


if __name__ == "__main__":
    asyncio.run(main())
