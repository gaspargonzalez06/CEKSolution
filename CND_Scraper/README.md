# CND Sync — descarga reportes del portal CND a MariaDB

Scraper **headless** (sin ventanas) que inicia sesión en el portal privado del CND,
recorre el listado de reportes, descarga los archivos, guarda el **crudo** y registra
todo en **MariaDB**.

## Qué hace

1. **Login headless** con Playwright en `https://sitiopublico.cnd.com.pa/privado/`.
2. **Catálogo** vía la API JSON del portal (`/Informe/GetListOperativosComerciales`),
   paginada (20 ítems/página). Detecta **todos** los tipos de reporte, no solo la página 1.
3. **Descarga** los formatos que le indiques. Por defecto **NO baja Excel** (`csv, txt`).
4. Guarda el **archivo crudo** en `./raw/<cliente>/<tipo>/<periodo>/` y en MariaDB
   guarda metadatos + columnas + una **muestra** (evita llenar la BD con archivos de 23 MB).
5. **Incremental**: no vuelve a bajar lo que ya está en `raw_data` (por `reporte_id`).

## Uso

```powershell
# Recomendado: doble clic en INICIAR.bat
# o directamente:
python cnd_sync.py                       # csv, txt (no excel)   <- por defecto
python cnd_sync.py --all                 # todo (incluye xlsx/xls/xlsm)
python cnd_sync.py --ext csv,txt,zip,pdf # formatos específicos
python cnd_sync.py --pages 60            # más historial (20 por página)
python cnd_sync.py --limit 10            # máximo 10 archivos
python cnd_sync.py --catalog-only        # solo listar, no descargar
python cnd_sync.py --no-incremental      # re-descargar aunque ya exista
```

## Formatos que publica el CND (relevados del portal)

| Reporte | Formatos |
|---|---|
| DTE Tabular | **txt**, xlsx |
| DTE Sustentos | xlsx, xls, pdf, **csv** |
| Preliminar Sustentos | xlsx, **csv** |
| Incumplimientos de Reglamento de Transmisión | **txt**, xls |
| Bases de Datos PSSE | **zip** |
| DTE Firmado / Informe de Vertimientos / Presentación Reunión | pdf |
| Liquidación / Mediciones / Totales por Contrato / Detalle Pérdidas | xlsx |

Los formatos útiles **sin Excel** son: **csv** (`reporte_totales_YYYY_MM.csv`),
**txt** (`0926_balance_transacciones_dte_*.txt`) y **zip** (bases PSSE).

## Base de datos (MariaDB — XAMPP)

- Host `127.0.0.1:3306`, usuario `root`, sin contraseña, base `cek`.
- Tablas:
  - `raw_data`: una fila por archivo → `data_json` (metadatos + columnas + muestra),
    `archivo_origen` (ruta en el servidor), `reporte_id`, `archivo_hash`, tamaño, período.
  - `scraping_log`: bitácora por archivo (estado, fecha, reporte_id).
- Consulta rápida:
  ```sql
  SELECT reporte_tipo, COUNT(*) n, SUM(archivo_tamano) bytes
  FROM cek.raw_data GROUP BY reporte_tipo;
  ```

## Requisitos

`playwright pandas aiomysql pyyaml openpyxl`  (ver `requirements.txt`).
`INICIAR.bat` los instala solo.

## Notas

- El portal tiene **mucho historial**: `--pages` limita cuánto se escanea (30 páginas = 600 reportes).
- Los CSV de energía (`reporte_totales_*.csv`) pesan ~8–23 MB cada uno.
- El archivo crudo queda en `./raw/` para poder inspeccionarlo; en la BD solo va una muestra.
- Para SQL Server (CEK) más adelante: se reemplaza la capa de inserción en `cnd_sync.py`
  (funciones `connect_db`, `ensure_schema`, `save_raw`), el resto es portable.
