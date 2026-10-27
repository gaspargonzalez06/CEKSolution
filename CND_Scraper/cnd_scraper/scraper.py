"""
Main scraper for CND portal with incremental download and processing.
"""
import asyncio
import hashlib
import os
import json
import re
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field
from typing import Optional
from playwright.async_api import async_playwright, Page, Browser, BrowserContext, Download
import pandas as pd
import aiomysql
import hashlib
import json
import os

from .login import CNDLogin, LoginConfig
from .db import MariaDBPool, ScrapingLogDB, init_database
from .transformers import (
    parse_file, transform_data, detect_file_type, 
    parse_file, transform_data, extract_period_from_filename,
    MESES_ES
)

# Spanish months for parsing
MESES_ES = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
    "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
    "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12
}


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


@dataclass
class ScrapingLog:
    cliente_codigo: str
    periodo: str
    reporte_tipo: str
    archivo_nombre: str
    archivo_hash: str
    archivo_url: str
    estado: str
    registros_nuevos: int = 0
    registros_actualizados: int = 0
    error_mensaje: str = ""
    fecha_inicio: datetime = field(default_factory=datetime.now)
    fecha_fin: Optional[datetime] = None


class CNDScraper:
    def __init__(self, config: ScrapingConfig, client: ClientConfig, db_pool):
        self.config = config
        self.client = client
        self.db_pool = db_pool
        self.log_db = ScrapingLogDB(db_pool)
        self.browser: Optional[Browser] = None
        self.context: Optional[BrowserContext] = None
        self.page: Optional[Page] = None
        self.download_dir = Path(config.download_dir) / client.codigo
        self.download_dir.mkdir(parents=True, exist_ok=True)
        
    async def __aenter__(self):
        playwright = await async_playwright().start()
        self.browser = await playwright.chromium.launch(
            headless=self.config.headless,
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
    
    async def login(self, username: str, password: str) -> bool:
        """Login using exact selectors."""
        login_config = LoginConfig()
        login = CNDLogin(self.page, login_config)
        return await login.login(username, password)
    
    async def navigate_to_reportes(self) -> bool:
        """Navigate to reports section."""
        try:
            # Navigate to dashboard
            await self.page.goto("https://sitioprivado.cnd.com.pa/Home/Dashboard", wait_until='networkidle')
            await asyncio.sleep(3)
            
            # Try multiple selectors for the reports button
            selectores_reportes = [
                'a:has-text("Informes")',
                'button:has-text("Informes")',
                'a:has-text("Reportes")',
                'button:has-text("Reportes")',
                'a[href*="Informe"]',
                'button:has-text("Consultar")',
                '[href*="IndexOperativosComerciales"]',
                'a:has-text("DTE")',
                'button:has-text("DTE")',
                'a:has-text("DTE")',
                'button:has-text("DTE Oficial")',
                'a:has-text("DTE Oficial")',
            ]
            
            for selector in selectores_reportes:
                try:
                    await self.page.wait_for_selector(selector, timeout=3000)
                    await self.page.click(selector)
                    await self.page.wait_for_load_state('networkidle')
                    await asyncio.sleep(2)
                    print(f"    [OK] Click en reportes con selector: {selector}")
                    return True
                except:
                    continue
            
            print("⚠️ No se encontró botón de reportes con selectores estándar")
            return False
            
        except Exception as e:
            print(f"Error navegando a reportes: {e}")
            return False
    
    async def get_available_reports(self, year: int, month: int) -> List[Dict]:
        """Get available reports for the period."""
        # This would need to be implemented based on the actual page structure
        # For now, return a placeholder
        return []
    
    async def get_available_files(self, report_type: str, year: int, month: int) -> List[Dict]:
        """Get available files for a report type."""
        # This needs to be implemented based on the actual page structure
        # For now, return empty list - will be implemented when we know the page structure
        return []
    
    async def download_file(self, url: str, filename: str) -> Optional[Path]:
        """Download a file."""
        try:
            async with self.page.expect_download() as download_info:
                await self.page.goto(url)
            download = await download_info.value
            path = self.download_dir / filename
            await download.save_as(path)
            return path
        except Exception as e:
            print(f"Error downloading {url}: {e}")
            return None
    
    def _file_hash(self, filepath: Path) -> str:
        """Calculate SHA256 hash of file."""
        h = hashlib.sha256()
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                h.update(chunk)
        return h.hexdigest()
    
    async def process_file(self, path: Path, reporte_tipo: str) -> List[Dict]:
        """Process a downloaded file and return records."""
        try:
            # Parse file
            parser = self._get_parser(path)
            df = parser(path)
            df = df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') for c in df.columns]
            
            # Transform based on report type
            if 'dte' in str(self.download_dir).lower() or 'dte' in reporte_tipo.lower():
                return self._transform_dte(df)
            elif 'dter' in str(self.download_dir).lower() or 'dter' in reporte_tipo.lower():
                return self._transform_dter(df)
            elif 'liquidacion' in str(self.download_dir).lower() or 'liquidacion' in str(self.download_dir).lower():
                return self._transform_liquidacion(df)
            else:
                return df.to_dict('records')
        except Exception as e:
            print(f"Error processing file {path}: {e}")
            return []
    
    def _transform_dte(self, df) -> list:
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
    
    def _transform_dter(self, df) -> list:
        records = []
        for _, row in df.iterrows():
            records.append({
                'annio': int(row.get('annio', row.get('anio', 0))),
                'mes': int(row.get('mes', 0)),
                'generador': str(row.get('generador', '')).strip(),
                'cliente': str(row.get('cliente', '')).strip(),
                'transaccion': str(row.get('transaccion', '')).strip(),
                'atributo': str(row.get('atributo', '')).strip().capitalize(),
                'valor': float(row.get('valor', 0) or 0),
            })
        return records
    
    def _transform_liquidacion(self, df) -> tuple:
        gencosto, ajustes, mediciones = [], [], []
        for _, row in df.iterrows():
            try:
                trans = str(row.get('transaccion', '')).lower()
                valor = float(row.get('valor', 0) or 0)
                attr = str(row.get('atributo', '')).strip().capitalize()
                
                base = {
                    'generador': str(row.get('generador', '')).strip(),
                    'cliente': str(row.get('cliente', '')).strip(),
                    'transaccion': str(row.get('transaccion', '')).strip(),
                    'atributo': str(row.get('atributo', '')).strip().capitalize(),
                    'valor': float(row.get('valor', 0) or 0),
                }
                
                trans_lower = trans.lower()
                if any(k in trans for k in ['costo', 'generacion', 'costo promedio']):
                    gencosto.append({**base, 'generacion': 0, 'costo_promedio': row.get('valor', 0)})
                elif 'medicion' in trans or 'consumo' in trans or 'kwh' in trans:
                    mediciones.append({**base, 'consumo': row.get('valor', 0)})
                else:
                    ajustes.append(base)
            except Exception as e:
                print(f"Error parsing liquidación row: {e}")
                continue
        return gencosto, ajustes, mediciones