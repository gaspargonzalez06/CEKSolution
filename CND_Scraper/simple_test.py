#!/usr/bin/env python3
"""
CND Scraper Simple - Login robusto + descarga TODOS los formatos
Extrae links de la tabla Angular y descarga TODOS los formatos
"""
import asyncio
import os
import json
import hashlib
from datetime import datetime
from pathlib import Path
from playwright.async_api import async_playwright
import pandas as pd
import hashlib

# ============== CONFIG ==============
USERNAME = "BRILLOSOL"
PASSWORD = "bF50koniaR0="
LOGIN_URL = "https://sitiopublico.cnd.com.pa/privado/"
REPORTS_URL = "https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND"
DOWNLOAD_DIR = Path("./downloads/BRILLOSOL")
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
MAX_FILES = 10
HEADLESS = False  # True para producción, False para debug

# ============== FUNCIONES SIMPLES ==============
async def save_debug(page, name):
    """Guarda HTML para debug"""
    content = await page.content()
    Path(f"debug_{name}.html").write_text(content, encoding='utf-8')
    print(f"[DEBUG] Guardado debug_{name}.html ({len(content)} chars)")

def get_parser(path):
    suf = Path(path).suffix.lower()
    if suf in ['.xlsx', '.xls']: return pd.read_excel
    if suf == '.csv': return lambda p: pd.read_csv(path, encoding='utf-8', sep=None, engine='python')
    if suf == '.txt': return lambda p: pd.read_csv(path, sep='\t', encoding='utf-8')
    return pd.read_excel

def normalize_cols(df):
    df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') for c in df.columns]
    return df

def transform_dte(df):
    df = df.copy()
    df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') for c in df.columns]
    out = []
    for _, r in df.iterrows():
        attr = str(r.get('atributo', '')).strip().lower()
        attr = 'Credito' if 'cred' in attr else 'Debito' if 'deb' in attr else 'Credito'
        out.append({
            'generador': str(r.get('generador', '')).strip(),
            'cliente': str(r.get('cliente', '')).strip(),
            'transaccion': str(r.get('transaccion', '')).strip(),
            'atributo': attr,
            'cantidad': float(r.get('cantidad', 0) or 0),
            'valor': float(r.get('valor', 0) or 0),
        })
    return out

def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''): h.update(chunk)
    return h.hexdigest()


async def main():
    print("="*60)
    print("CND SCRAPER - EXTRACTOR DE TODOS LOS FORMATOS")
    print("="*60)
    
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False, args=['--disable-blink-features=AutomationControlled'])
        context = await browser.new_context(
            viewport={'width': 1366, 'height': 768},
            accept_downloads=True
        )
        page = await context.new_page()
        page.set_default_timeout(60000)
        
        try:
            # 1. LOGIN
            print("\n[1/3] LOGIN...")
            await page.goto("https://sitiopublico.cnd.com.pa/privado/", wait_until='domcontentloaded')
            await asyncio.sleep(3)
            
            # Debug: guardar HTML para ver qué hay
            content = await page.content()
            Path("debug_login.html").write_text(await page.content(), encoding='utf-8')
            print(f"[DEBUG] HTML guardado en debug_login.html ({len(content)} chars)")
            
            # Buscar campo usuario con reintentos
            found = False
            for attempt in range(3):
                try:
                    await page.wait_for_selector('#modlgn-username', timeout=10000, state='visible')
                    print("[OK] Campo usuario encontrado")
                    break
                except:
                    if attempt == 2:
                        content = await page.content()
                        Path("debug_page.html").write_text(await page.content(), encoding='utf-8')
                        print(f"[DEBUG] HTML guardado en debug_page.html")
                        if 'modlgn-username' in content:
                            print("[DEBUG] modlgn-username SÍ está en HTML")
                        else:
                            print("[DEBUG] modlgn-username NO está en HTML")
                            inputs = await page.query_selector_all('input')
                            print(f"[DEBUG] Inputs encontrados: {len(inputs)}")
                            for inp in (await page.query_selector_all('input'))[:5]:
                                try:
                                    print(f"  input: id={await inp.get_attribute('id')}, name={await inp.get_attribute('name')}, type={await inp.get_attribute('type')}")
                                except: pass
                        return
                    await asyncio.sleep(2)
            
            print("[LOGIN] Rellenando formulario...")
            await page.fill('#modlgn-username', 'BRILLOSOL')
            await page.fill('#modlgn-passwd', 'bF50koniaR0=')
            await page.click('button.login-button[type="submit"]')
            await page.wait_for_load_state('networkidle')
            await asyncio.sleep(5)
            
            # Verificar login
            if await page.query_selector('#modlgn-username'):
                print("[ERROR] Login falló - seguimos en login")
                return
            print("[OK] Login exitoso")
            
            # 2. IR A REPORTES
            print("\n[2/3] NAVEGANDO A REPORTES...")
            await page.goto("https://sitioprivado.cnd.com.pa/Informe/IndexOperativosComercialesCND", wait_until='networkidle')
            await asyncio.sleep(3)
            
            # 3. EXTRAER LINKS DE LA TABLA ANGULAR
            print(f"\n[3/3] EXTRAYENDO LINKS DE LA TABLA...")
            await asyncio.sleep(2)
            
            # Guardar HTML de la tabla para debug
            content = await page.content()
            Path("debug_reports.html").write_text(await page.content(), encoding='utf-8')
            print(f"[DEBUG] HTML de reportes guardado en debug_reports.html")
            
            # Buscar TODOS los links de descarga en la tabla
            # Los links están en <a> con href="/Informe/Download/XXXXX" dentro de la tabla ng-repeat
            download_links = await page.query_selector_all('a[href*="/Informe/Download/"]')
            print(f"[LINKS] Encontrados {len(download_links)} enlaces de descarga")
            
            if not download_links:
                # Intentar selectores más amplios
                all_links = await page.query_selector_all('a[href*="/Informe/Download/"]')
                print(f"[LINKS] Con selector amplio: {len(all_links)}")
                download_links = all_links
            
            # Si aún no hay, buscar en la tabla ng-repeat
            if not download_links:
                rows = await page.query_selector_all('tr[ng-repeat*="item in Page.definition.grid"]')
                print(f"[ROWS] Filas ng-repeat encontradas: {len(rows)}")
                for row in rows[:10]:
                    links_in_row = await row.query_selector_all('a[href*="/Informe/Download/"]')
                    for link in links_in_row:
                        download_links.append(link)
                print(f"[LINKS] Total desde filas: {len(download_links)}")
            
            print(f"[TOTAL] {len(download_links)} links de descarga encontrados")
            
            # Procesar cada link
            downloaded = []
            for i, link in enumerate(download_links[:10]):
                try:
                    href = await link.get_attribute('href')
                    text = await link.inner_text()
                    if not href: 
                        continue
                    if href.startswith('/'): 
                        href = f"https://sitioprivado.cnd.com.pa{href}"
                    elif not href.startswith('http'): 
                        continue
                    
                    # Obtener nombre del archivo del texto del link o del href
                    filename_from_text = text.strip() if text.strip() else ""
                    if not filename_from_text:
                        # Extraer del href
                        filename_from_text = href.split('/')[-1]
                    
                    print(f"  [{i+1}/10] {href}")
                    print(f"      Nombre: {filename_from_text}")
                    
                    # Descargar
                    async with page.expect_download() as dl_info:
                        await link.click()
                    download = await download_info.value
                    fname = f"test_{download.suggested_filename}"
                    path = Path("downloads/BRILLOSOL") / fname
                    await download.save_as(path)
                    print(f"    [OK] Guardado: {path.name}")
                    
                    # Analizar archivo
                    try:
                        ext = Path(path).suffix.lower()
                        if ext in ['.xlsx', '.xls']:
                            df = pd.read_excel(path, engine='openpyxl')
                        elif ext == '.csv':
                            df = pd.read_csv(path, encoding='utf-8', sep=None, engine='python')
                        elif ext == '.txt':
                            df = pd.read_csv(path, sep='\t', encoding='utf-8')
                        else:
                            print(f"    Tipo desconocido: {ext}")
                            continue
                        
                        df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') for c in df.columns]
                        print(f"    Filas: {len(df)}, Cols: {list(df.columns)[:15]}")
                        if len(df) > 0: 
                            print(f"   Sample: {df.iloc[0].to_dict()}")
                    except Exception as e:
                        print(f"    Parse error: {e}")
                        
                except Exception as e:
                    print(f"  [ERR] {e}")
            
            files = list(Path("downloads/BRILLOSOL").glob("*"))
            print(f"\n[OK] Completado. {len(list(Path('downloads/BRILLOSOL').glob('*')))} archivos en downloads/BRILLOSOL/")
            
        except Exception as e:
            print(f"[ERROR] {e}")
            import traceback; traceback.print_exc()
        finally:
            print("\nCerrando en 10s... (cerrar manual si quiere inspeccionar)")
            await asyncio.sleep(10)
            await browser.close()

if __name__ == "__main__":
    asyncio.run(main())