"""
Test de formatos para CND Scraper - BRILLOSOL
Descarga y analiza 10 archivos de diferentes formatos (Excel, CSV, TXT)
"""
import asyncio
import hashlib
import json
import os
import yaml
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from typing import Optional
from playwright.async_api import async_playwright, Page, Browser, BrowserContext, Download
import pandas as pd
import aiomysql
import hashlib
import json
import os

# Imports absolutos (no relativos)
from cnd_scraper.login import CNDLogin, LoginConfig
from cnd_scraper.scraper import CNDScraper, ScrapingConfig, ClientConfig
from cnd_scraper.db import MariaDBPool, ScrapingLogDB, init_database, DBConfig
from cnd_scraper.transformers import (
    parse_file, transform_data, detect_file_type,
    parse_file, transform_data, extract_period_from_filename,
    MESES_ES
)

# ============================================================
# CONFIG
# ============================================================
with open('config.yaml', 'r', encoding='utf-8') as f:
    CONFIG = yaml.safe_load(f)

DB_CONFIG = CONFIG['database']
PORTAL = CONFIG['portal']
SCRAPING = CONFIG['scraping']
AGENT = CONFIG['agentes']['BRILLOSOL']

DOWNLOAD_DIR = Path(SCRAPING['download_dir']) / 'BRILLOSOL'
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILES = SCRAPING['max_test_files']

# ============================================================
# DB
# ============================================================
class DBConfig:
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)


class MariaDBPool:
    def __init__(self, config: DBConfig):
        self.config = config
        self.pool = None
    
    async def connect(self):
        self.pool = await aiomysql.create_pool(
            host=self.config.host,
            port=self.config.port,
            user=self.config.user,
            password=self.config.password,
            db=self.config.database,
            charset='utf8mb4',
            autocommit=True,
            minsize=2,
            maxsize=10,
        )
    
    async def close(self):
        if self.pool:
            self.pool.close()
            await self.pool.wait_closed()
    
    @asynccontextmanager
    async def acquire(self):
        async with self.pool.acquire() as conn:
            async with conn.cursor(aiomysql.DictCursor) as cur:
                yield cur
    
    async def execute(self, query, params=None):
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return cur.rowcount
    
    async def fetchall(self, query, params=None):
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return await cur.fetchall()
    
    async def fetchone(self, query, params=None):
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return await cur.fetchone()


class ScrapingLogDB:
    def __init__(self, db_pool):
        self.db = db_pool
    
    async def is_processed(self, cliente_codigo, periodo, reporte_tipo, archivo_hash):
        query = """
        SELECT 1 FROM scraping_log 
        WHERE cliente_codigo = %s AND periodo = %s 
          AND reporte_tipo = %s AND archivo_hash = %s
          AND estado IN ('PROCESADO', 'NUEVO')
        """
        result = await self.db.fetchone(query, (cliente_codigo, periodo, reporte_tipo, archivo_hash))
        return result is not None
    
    async def log_start(self, cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre, archivo_hash, archivo_tamano=0):
        query = """
        INSERT INTO scraping_log 
        (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre, archivo_hash, archivo_tamano, estado)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'PROCESANDO')
        ON DUPLICATE KEY UPDATE estado = 'PROCESANDO', fecha_inicio = NOW(), fecha_fin = NULL
        """
        await self.db.execute(query, (cliente_codigo, cliente_nombre, periodo, reporte_tipo, archivo_nombre, archivo_hash, 0))
        return await self._get_last_id()
    
    async def _get_last_id(self):
        async with self.pool.acquire() as conn:
            async with conn.cursor(aiomysql.DictCursor) as cur:
                await cur.execute("SELECT LAST_INSERT_ID() as id")
                result = await cur.fetchone()
                return result['id'] if result else 0
    
    async def log_finish(self, log_id, estado, insertados=0, actualizados=0, error=None):
        query = """
        UPDATE scraping_log SET estado = %s, fecha_fin = NOW(),
            registros_insertados = %s, registros_actualizados = %s, error_mensaje = %s
        WHERE id = %s
        """
        await self.db.execute(query, (estado, insertados, actualizados, error, log_id))
    
    def file_hash(self, filepath):
        h = hashlib.sha256()
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                h.update(chunk)
        return h.hexdigest()


async def init_database(db_pool):
    schema_sql = """
    CREATE DATABASE IF NOT EXISTS cek CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    USE cek;
    
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
        INDEX idx_scraping_cliente_periodo (cliente_codigo, periodo),
        INDEX idx_scraping_estado (estado)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    
    CREATE TABLE IF NOT EXISTS dte (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        key_file VARCHAR(20), annio INT, mes INT,
        generador VARCHAR(20), cliente VARCHAR(20), codigo_agente VARCHAR(20),
        transaccion VARCHAR(100), tipo VARCHAR(50), u_m VARCHAR(10),
        cantidad DECIMAL(10,3), atributo VARCHAR(10), valor DECIMAL(9,2),
        periodo CHAR(6) GENERATED ALWAYS AS (CONCAT(annio, LPAD(mes,2,'0'))) STORED,
        archivo_origen VARCHAR(255), fecha_carga DATETIME DEFAULT CURRENT_TIMESTAMP,
        hash_fila CHAR(64) GENERATED ALWAYS AS (SHA2(CONCAT_WS('|', cliente, generador, periodo, transaccion, atributo, valor), 256)) STORED,
        UNIQUE KEY uk_dte_upsert (cliente, generador, periodo, transaccion, atributo, hash_fila),
        INDEX idx_dte_periodo (periodo), INDEX idx_dte_generador (generador)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """
    async with db_pool.acquire() as cur:
        for statement in schema_sql.strip().split(';'):
            stmt = statement.strip()
            if stmt:
                await cur.execute(stmt)
        print("[OK] Database schema initialized")


# ============================================================
# TRANSFORMERS (inline para evitar imports)
# ============================================================
def parse_excel(path):
    return pd.read_excel(path, engine='openpyxl')

def parse_csv(path):
    return pd.read_csv(path, encoding='utf-8', sep=None, engine='python')

def parse_txt(path):
    return pd.read_csv(path, sep='\t', encoding='utf-8')

PARSERS = {
    '.xlsx': parse_excel,
    '.xls': parse_excel,
    '.csv': parse_csv,
    '.txt': parse_txt,
}

def get_parser(path):
    suffix = Path(path).suffix.lower()
    return PARSERS.get(suffix, parse_csv)

def detect_file_type(path):
    suffix = Path(path).suffix.lower()
    return {
        '.xlsx': 'excel',
        '.xls': 'excel',
        '.csv': 'csv',
        '.txt': 'txt',
    }.get(suffix, 'unknown')

def normalize_columns(df):
    df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') for c in df.columns]
    return df

def parse_file(path):
    parser = get_parser(path)
    df = parser(path)
    df = normalize_columns(df)
    return df

def transform_data(df, file_type):
    df = normalize_columns(df)
    if file_type in ['excel', 'csv', 'txt']:
        return transform_dte(df)
    return df.to_dict('records')

def transform_dte(df):
    records = []
    for _, row in df.iterrows():
        attr = str(row.get('atributo', row.get('debito_credito', 'Credito'))).strip().lower()
        if 'cred' in attr: attr = 'Credito'
        elif 'deb' in attr: attr = 'Debito'
        else: attr = 'Credito'
        records.append({
            'key_file': str(row.get('key', ''))[:20],
            'annio': int(row.get('annio', row.get('anio', 0))),
            'mes': int(row.get('mes', 0)),
            'generador': row.get('generador', ''),
            'cliente': str(row.get('cliente', row.get('cliente_codigo', ''))).strip(),
            'codigo_agente': str(row.get('codigo_agente', row.get('agente', ''))).strip(),
            'transaccion': str(row.get('transaccion', row.get('transaccion_descripcion', ''))).strip(),
            'tipo': str(row.get('tipo', 'Regular')).strip(),
            'u_m': str(row.get('u_m', row.get('u/m', 'MWh'))).strip(),
            'cantidad': float(row.get('cantidad', row.get('cantidad_mwh', 0)) or 0),
            'atributo': attr.capitalize(),
            'valor': float(row.get('valor', row.get('monto', 0)) or 0),
            'archivo_origen': '',
        })
    return records


# ============================================================
# PIPELINE
# ============================================================
@dataclass
class ScrapingConfig:
    headless: bool = False
    timeout: int = 60000
    delay_ms: int = 2000
    download_dir: str = "./downloads"
    incremental: bool = True
    stop_on_known: bool = True
    max_test_files: int = 10


@dataclass
class ClientConfig:
    codigo: str
    nombre: str
    usuario: str
    password: str
    codigo_cnd: str = ""


class CNDPipeline:
    def __init__(self):
        self.config = None
        self.db_pool = None
    
    async def setup(self):
        self.db_pool = MariaDBPool(DBConfig(
            host='127.0.0.1', port=3306,
            user='root', password='', database='cek'
        ))
        await self.db_pool.connect()
        await init_database(self.db_pool)
    
    async def cleanup(self):
        if self.db_pool:
            await self.db_pool.close()
    
    async def run_test_formats(self, max_files=10):
        print(f"\n{'='*60}")
        print(f"TEST FORMATOS - BRILLOSOL")
        print(f"{'='*60}")
        
        async with CNDScraper(ScrapingConfig(), 
                              ClientConfig(codigo="BRILLOSOL", nombre="BRILLOSOL", 
                                           usuario="BRILLOSOL", password="bF50koniaR0="),
                              self.db_pool) as scraper:
            # 1. Login
            print("[LOGIN] Iniciando login...")
            if not await scraper.login("BRILLOSOL", "bF50koniaR0="):
                raise Exception("Login fallido")
            print("[OK] Login exitoso")
            
            # 2. Navigate to reports
            print("[NAV] Navegando a reportes...")
            if not await scraper.navigate_to_reportes():
                print("⚠️ No se pudo navegar a reportes, intentando URL directa...")
                await scraper.page.goto("https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND", wait_until='networkidle')
                await asyncio.sleep(3)
            
            # 3. Try to find and download test files
            print(f"\n[DOWNLOAD] Descargando hasta {10} archivos de prueba...")
            downloaded = await self._download_test_files(scraper, 10)
            
            if downloaded:
                print(f"\n[DOWNLOAD] Descargados {len(downloaded)} archivos")
                for file_path in downloaded:
                    print(f"\n[FILE] Procesando: {file_path.name}")
                    await self._process_downloaded_file(file_path)
            else:
                print("⚠️ No se pudieron descargar archivos automáticamente")
                print("💡 Navega manualmente en el navegador abierto y descarga archivos de prueba")
                print("   Luego presiona Enter para continuar...")
                input()
                await self._process_manual_downloads(scraper)
    
    async def _download_test_files(self, scraper, max_files):
        downloaded = []
        try:
            links = await scraper.page.query_selector_all('a[href*="download"], a[href*="Download"], a[href*="Descargar"], a[href*=".xlsx"], a[href*=".csv"], a[href*=".txt"], a[href*=".xls"]')
            print(f"[LINKS] Encontrados {len(links)} enlaces potenciales de descarga")
            
            for i, link in enumerate(links[:max_files]):
                try:
                    href = await link.get_attribute('href')
                    text = await link.inner_text()
                    if not href: continue
                    if href.startswith('/'):
                        href = f"https://sitioprivado.cnd.com.pa{href}"
                    elif not href.startswith('http'):
                        continue
                    
                    print(f"  [DOWNLOAD] Descargando {i+1}/{max_files}: {text[:50]}...")
                    async with scraper.page.expect_download() as download_info:
                        await link.click()
                    download = await download_info.value
                    filename = f"test_{download.suggested_filename}"
                    path = scraper.download_dir / filename
                    await download.save_as(path)
                    downloaded.append(path)
                    print(f"    [OK] Guardado: {path.name}")
                    if len(downloaded) >= 10: break
                except Exception as e:
                    print(f"    [ERROR] Error descargando: {e}")
        except Exception as e:
            print(f"Error buscando enlaces: {e}")
        return downloaded
    
    async def _process_manual_downloads(self, scraper):
        files = list(Path("./downloads/BRILLOSOL").glob("*"))
        if not files:
            print("No hay archivos en la carpeta de descargas")
            return
        print(f"\n[DIR] Procesando {len(files)} archivos en carpeta de descargas...")
        for f in files[:10]:
            await self._process_downloaded_file(f)
    
    async def _process_downloaded_file(self, file_path):
        print(f"\n[FILE] Procesando: {file_path.name}")
        try:
            file_type = self._detect_file_type(file_path)
            print(f"   Tipo detectado: {file_type}")
            df = parse_file(file_path)
            print(f"   Filas: {len(df)}, Columnas: {len(df.columns)}")
            print(f"   Columnas: {list(df.columns)[:10]}")
            records = transform_data(df, "excel" if file_path.suffix in ['.xlsx', '.xls'] else "csv" if file_path.suffix == '.csv' else "txt")
            print(f"   Registros transformados: {len(records)}")
            if records:
                print(f"   Primer registro: {records[0]}")
            await self._save_raw_analysis(file_path, records)
        except Exception as e:
            print(f"   [ERROR] Error procesando: {e}")
    
    async def _save_raw_analysis(self, file_path, records):
        analysis = {
            'file': str(file_path),
            'file_type': file_path.suffix.lower(),
            'size_bytes': file_path.stat().st_size,
            'records_count': len(records),
            'columns': list(records[0].keys()) if records else [],
            'sample_records': records[:3] if records else [],
            'timestamp': datetime.now().isoformat()
        }
        analysis_dir = Path("./analysis")
        analysis_dir.mkdir(exist_ok=True)
        output_file = analysis_dir / f"analysis_{file_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(analysis, f, ensure_ascii=False, indent=2, default=str)
        print(f"   [SAVE] Analisis guardado en: {output_file}")


# ============================================================
# SCRAPER
# ============================================================
class CNDScraper:
    def __init__(self, config, client, db_pool):
        self.config = config
        self.client = client
        self.db_pool = db_pool
        self.download_dir = Path(config.download_dir) / client.codigo
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.browser = None
        self.context = None
        self.page = None
    
    async def __aenter__(self):
        playwright = await async_playwright().start()
        self.browser = await playwright.chromium.launch(
            headless=False,
            args=['--disable-blink-features=AutomationControlled']
        )
        self.context = await self.browser.new_context(
            viewport={'width': 1366, 'height': 768},
            accept_downloads=True
        )
        self.page = await self.context.new_page()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.browser:
            await self.browser.close()
    
    async def login(self, username, password):
        print("[LOGIN] Navegando a https://sitiopublico.cnd.com.pa/privado/")
        await self.page.goto("https://sitiopublico.cnd.com.pa/privado/", wait_until='domcontentloaded')
        await asyncio.sleep(3)
        
        # Wait for the login form to be visible with extended timeout
        try:
            await self.page.wait_for_selector('#modlgn-username', timeout=30000, state='visible')
            print("[LOGIN] Formulario de login detectado")
        except Exception as e:
            print(f"[ERROR] No se encontró el campo de usuario #modlgn-username: {e}")
            content = await self.page.content()
            # Save debug HTML
            with open("debug_login_page.html", "w", encoding="utf-8") as f:
                f.write(content)
            print("[DEBUG] Guardado debug_login_page.html para inspección")
            if 'modlgn-username' not in content:
                print("[DEBUG] El campo modlgn-username NO está en la página")
            else:
                print("[DEBUG] El campo modlgn-username SÍ está en la página")
            # Try to find any input fields
            inputs = await self.page.query_selector_all('input')
            print(f"[DEBUG] Inputs encontrados: {len(inputs)}")
            for i, inp in enumerate(inputs[:5]):
                try:
                    id_attr = await inp.get_attribute('id')
                    name_attr = await inp.get_attribute('name')
                    type_attr = await inp.get_attribute('type')
                    print(f"  Input {i}: id={id_attr}, name={name_attr}, type={type_attr}")
                except: pass
            return False
        
        await self.page.fill('#modlgn-username', username)
        await self.page.fill('#modlgn-passwd', password)
        await self.page.click('button.login-button[type="submit"]')
        await self.page.wait_for_load_state('networkidle')
        await asyncio.sleep(5)
        try:
            await self.page.wait_for_selector('.dashboard, .welcome, .user-menu, .logout, .user-menu', timeout=15000)
            print("[OK] Login verificado")
            return True
        except:
            login_form = await self.page.query_selector('#modlgn-username')
            if login_form:
                print("[ERROR] Login falló - seguimos en página de login")
                return False
            return True
    
    async def navigate_to_reportes(self):
        try:
            await self.page.goto("https://sitioprivado.cnd.com.pa/Home/Dashboard", wait_until='networkidle')
            await asyncio.sleep(3)
            selectores = [
                'a:has-text("Informes")', 'button:has-text("Informes")',
                'a:has-text("Reportes")', 'a[href*="Informe"]',
                'a:has-text("DTE")', 'button:has-text("DTE")',
            ]
            for selector in selectores:
                try:
                    await self.page.wait_for_selector(selector, timeout=3000)
                    await self.page.click(selector)
                    await self.page.wait_for_load_state('networkidle')
                    await asyncio.sleep(2)
                    print(f"    [OK] Click en reportes: {selector}")
                    return True
                except: continue
            return False
        except Exception as e:
            print(f"Error navegando: {e}")
            return False
    
    def _get_parser(self, path):
        suffix = Path(path).suffix.lower()
        return PARSERS.get(suffix, parse_csv)
    
    def _detect_file_type(self, path):
        suffix = Path(path).suffix.lower()
        return {'.xlsx': 'excel', '.xls': 'excel', '.csv': 'csv', '.txt': 'txt'}.get(suffix, 'unknown')


# ============================================================
# MAIN
# ============================================================
async def main():
    print("=" * 60)
    print("CND SCRAPER - TEST FORMATOS BRILLOSOL")
    print("=" * 60)
    
    # DB
    db_pool = MariaDBPool(DBConfig(host='127.0.0.1', port=3306, user='root', password='', database='cek'))
    await db_pool.connect()
    await init_database(db_pool)
    
    try:
        # Scraper
        async with CNDScraper(
            ScrapingConfig(download_dir="./downloads", max_test_files=10),
            ClientConfig(codigo="BRILLOSOL", nombre="BRILLOSOL", usuario="BRILLOSOL", password="bF50koniaR0="),
            MariaDBPool(DBConfig(host='127.0.0.1', port=3306, user='root', password='', database='cek'))
        ) as scraper:
            # Login
            print("[LOGIN] Login...")
            if not await scraper.login("BRILLOSOL", "bF50koniaR0="):
                raise Exception("Login failed")
            print("[OK] Login OK")
            
            # Navegar
            print("[NAV] Navegando a reportes...")
            await scraper.navigate_to_reportes()
            
            # Descargar test
            print("[DOWNLOAD] Descargando archivos de prueba...")
            downloaded = []
            try:
                links = await scraper.page.query_selector_all('a[href*="download"], a[href*="Download"], a[href*="Descargar"], a[href*=".xlsx"], a[href*=".csv"], a[href*=".txt"], a[href*=".xls"]')
                print(f"[LINKS] {len(links)} enlaces encontrados")
                
                for i, link in enumerate(links[:10]):
                    try:
                        href = await link.get_attribute('href')
                        text = await link.inner_text()
                        if not href: continue
                        if href.startswith('/'): href = f"https://sitioprivado.cnd.com.pa{href}"
                        elif not href.startswith('http'): continue
                        
                        print(f"  [DOWNLOAD] {i+1}/10: {text[:50]}")
                        async with scraper.page.expect_download() as download_info:
                            await link.click()
                        download = await download_info.value
                        filename = f"test_{download.suggested_filename}"
                        path = Path("./downloads/BRILLOSOL") / filename
                        await download.save_as(path)
                        downloaded.append(path)
                        print(f"    [OK] {path.name}")
                        if len(downloaded) >= 10: break
                    except Exception as e:
                        print(f"    [ERROR] {e}")
            except Exception as e:
                print(f"Error: {e}")
            
            # Procesar descargados
            for f in downloaded:
                print(f"\n[FILE] Procesando: {f.name}")
                try:
                    df = parse_file(f)
                    records = transform_data(df, f.suffix.lower())
                    print(f"   Filas: {len(df)}, Registros: {len(records)}")
                    if records: print(f"   Sample: {records[0]}")
                except Exception as e:
                    print(f"   [ERROR] {e}")
    
    finally:
        pass

if __name__ == "__main__":
    asyncio.run(main())