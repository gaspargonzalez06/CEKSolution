"""
Transformers for parsing different file formats (Excel, CSV, TXT).
"""
import pandas as pd
import re
from typing import List, Dict, Any, Tuple
from datetime import datetime

# Spanish month names
MESES_ES = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
    "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
    "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12
}

# File parsers
def parse_excel(path: str) -> pd.DataFrame:
    return pd.read_excel(path, engine='openpyxl')

def parse_csv(path: str) -> pd.DataFrame:
    return pd.read_csv(path, encoding='utf-8', sep=None, engine='python')

def parse_txt(path: str) -> pd.DataFrame:
    return pd.read_csv(path, sep='\t', encoding='utf-8')

PARSERS = {
    '.xlsx': parse_excel,
    '.xls': parse_excel,
    '.csv': parse_csv,
    '.txt': parse_txt,
}


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize column names."""
    df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') 
                  for c in df.columns]
    return df


def get_parser(path: str):
    """Get appropriate parser for file extension."""
    suffix = Path(path).suffix.lower()
    return PARSERS.get(suffix, parse_csv)


def detect_file_type(path: str) -> str:
    """Detect file type from extension."""
    suffix = Path(path).suffix.lower()
    return {
        '.xlsx': 'excel',
        '.xls': 'excel',
        '.csv': 'csv',
        '.txt': 'txt',
    }.get(suffix, 'unknown')


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize column names."""
    df.columns = [c.strip().lower().replace(' ', '_').replace('.', '_').replace('-', '_') 
                  for c in df.columns]
    return df


def extract_period_from_filename(filename: str) -> tuple:
    """Extract year and month from filename."""
    # Try patterns like 202610, 2026-10, 2026_10, oct2026, oct-2026, etc.
    patterns = [
        r'(\d{4})[-_]?(\d{2})',  # 202610, 2026-10, 2026_10
        r'(\d{2})[-_]?(\d{4})',  # 10-2026, 10_2026
    ]
    
    for pattern in patterns:
        match = re.search(pattern, filename)
        if match:
            groups = match.groups()
            if len(groups) == 2:
                if len(groups[0]) == 4:
                    return int(groups[0]), int(groups[1])
                else:
                    return int(groups[1]), int(groups[0])
    
    # Try month names in Spanish
    for mes_nombre, mes_num in MESES_ES.items():
        if mes_nombre in filename.lower():
            # Look for year nearby
            year_match = re.search(r'(20\d{2})', filename)
            year = int(year_match.group(1)) if year_match else None
            if year:
                return year, mes_num
    
    return None, None


def parse_dte(df: pd.DataFrame, generador: str, periodo: str) -> list:
    """Transform DTE DataFrame to database records."""
    records = []
    for _, row in df.iterrows():
        try:
            # Normalize attribute
            attr = str(row.get('atributo', row.get('debito_credito', 'Credito'))).strip().lower()
            if 'cred' in attr:
                attr = 'Credito'
            elif 'deb' in attr:
                attr = 'Debito'
            else:
                attr = 'Credito'
            
            records.append({
                'key_file': str(row.get('key', row.get('key_file', '')))[:20],
                'annio': int(row.get('annio', row.get('anio', 0))),
                'mes': int(row.get('mes', 0)),
                'generador': generador,
                'cliente': str(row.get('cliente', row.get('cliente_codigo', ''))).strip(),
                'codigo_agente': str(row.get('codigo_agente', row.get('agente', ''))).strip(),
                'transaccion': str(row.get('transaccion', row.get('transaccion_descripcion', ''))).strip(),
                'tipo': str(row.get('tipo', row.get('type', 'Regular'))).strip(),
                'u_m': str(row.get('u_m', row.get('u/m', 'MWh'))).strip(),
                'cantidad': float(row.get('cantidad', row.get('cantidad_mwh', 0)) or 0),
                'atributo': str(row.get('atributo', row.get('debito_credito', 'Credito'))).strip().capitalize(),
                'valor': float(row.get('valor', row.get('monto', 0)) or 0),
                'archivo_origen': '',
            })
        except Exception as e:
            print(f"Error parsing DTE row: {e}")
            continue
    
    return records


def transform_dter(df: pd.DataFrame) -> list:
    """Transform DTER data."""
    records = []
    for _, row in df.iterrows():
        try:
            records.append({
                'annio': int(row.get('annio', row.get('anio', 0))),
                'mes': int(row.get('mes', 0)),
                'generador': str(row.get('generador', '')).strip(),
                'cliente': str(row.get('cliente', '')).strip(),
                'transaccion': str(row.get('transaccion', '')).strip(),
                'atributo': str(row.get('atributo', '')).strip().capitalize(),
                'valor': float(row.get('valor', 0) or 0),
            })
        except Exception as e:
            print(f"Error parsing DTER row: {e}")
            continue
    return records


def transform_liquidacion(df: pd.DataFrame) -> tuple:
    """Transform liquidación data into GenCosto, Ajustes, Mediciones."""
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
                'atributo': attr,
                'valor': valor,
            }
            
            trans_lower = trans.lower()
            if any(k in trans for k in ['costo', 'generacion', 'costo promedio', 'costo promedio']):
                gencosto.append({**base, 'generacion': 0, 'costo_promedio': valor})
            elif 'medicion' in trans or 'consumo' in trans or 'kwh' in trans:
                mediciones.append({
                    'periodo': '', 'fecha': None,
                    'generador': base['generador'],
                    'cliente': base['cliente'],
                    'consumo': valor
                })
            else:
                ajustes.append(base)
        except Exception as e:
            print(f"Error parsing liquidación row: {e}")
            continue
    
    return gencosto, ajustes, mediciones


def clean_value(val) -> any:
    """Clean and convert value for database."""
    if pd.isna(val) or val is None:
        return None
    if isinstance(val, (int, float, bool)):
        return val
    if isinstance(val, str):
        val = val.strip()
        # Try numeric
        try:
            if '.' in val:
                return float(val)
            return int(val)
        except:
            return val
    return str(val)


def parse_file(path: str) -> tuple:
    """Parse file and return (dataframe, file_type)."""
    path_obj = Path(path)
    parser = get_parser(path)
    df = parser(path)
    df = normalize_columns(df)
    file_type = detect_file_type(path)
    return df, file_type


def transform_data(df: pd.DataFrame, file_type: str, generador: str = None, periodo: str = None) -> list:
    """Transform dataframe based on file type."""
    df = normalize_columns(df)
    
    if 'dte' in str(df.columns).lower() or file_type in ['txt', 'csv']:
        return parse_dte(df, generador, periodo or '')
    elif 'dter' in str(df.columns).lower():
        return transform_dter(df)
    elif 'liquidacion' in str(df.columns).lower() or 'liquid' in str(df.columns).lower():
        return transform_liquidacion(df)
    else:
        # Generic - return all rows as dicts
        return df.to_dict('records')


# Spanish months
MESES_ES = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
    "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
    "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12
}


def extract_period_from_text(text: str) -> tuple:
    """Extract year and month from text with Spanish month names."""
    if not isinstance(text, str):
        return None, None
    
    text = text.lower()
    for mes_nombre, mes_num in MESES_ES.items():
        if mes_nombre in text:
            year_match = re.search(r'\b(20\d{2})\b', text)
            año = int(year_match.group(1)) if year_match else None
            return año, mes_num
    return None, None