@echo off
chcp 65001 >nul
title CND Sync - Reportes CND a MariaDB
cd /d "%~dp0"

echo ============================================================
echo  CND Sync - Login headless + descarga + MariaDB
echo ============================================================
echo.

REM --- Python ---
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python no encontrado. Instale Python 3.10+ de python.org
    pause
    exit /b 1
)

REM --- Dependencias ---
python -c "import playwright, pandas, aiomysql, yaml, openpyxl" >nul 2>&1
if errorlevel 1 (
    echo [SETUP] Instalando dependencias...
    pip install -q playwright pandas aiomysql pyyaml openpyxl
    python -m playwright install chromium
)

REM --- MariaDB (XAMPP) ---
tasklist /FI "IMAGENAME eq mysqld.exe" 2>nul | find /I "mysqld.exe" >nul
if errorlevel 1 (
    if exist "C:\xampp\mysql\bin\mysqld.exe" (
        echo [SETUP] Iniciando MariaDB (XAMPP)...
        start "" /B "C:\xampp\mysql\bin\mysqld.exe" --defaults-file="C:\xampp\mysql\bin\my.ini"
        timeout /t 6 >nul
    ) else (
        echo [AVISO] No encontre MariaDB en C:\xampp. Asegurese de que este corriendo.
    )
)

echo.
echo [RUN] Descargando reportes NO-Excel (csv, txt) e insertando en MariaDB...
echo.
python cnd_sync.py %*

echo.
echo ============================================================
echo  LISTO. Crudos en .\raw\   ^|   Datos en MariaDB (base 'cek')
echo ============================================================
pause
