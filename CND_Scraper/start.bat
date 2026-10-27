@echo off
chcp 65001 >nul
title CND Scraper - BRILLOSOL Test Formatos

echo ==========================================
echo  CND Scraper - Test Formatos BRILLOSOL
echo ==========================================
echo.

:: ==========================================
:: 1. VERIFICAR/INSTALAR PYTHON
:: ==========================================
echo [1/6] Verificando Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python no esta instalado.
    echo Descargue e instale Python 3.9+ desde https://python.org
    echo Asegurese de marcar "Add Python to PATH" durante la instalacion.
    pause
    exit /b 1
)
echo    Python OK

:: ==========================================
:: 2. VERIFICAR/INSTALAR DEPENDENCIAS PYTHON
:: ==========================================
echo [2/6] Verificando dependencias Python...
python -c "import aiomysql, playwright, pandas, openpyxl, yaml" 2>nul
if errorlevel 1 (
    echo    Instalando dependencias Python...
    pip install --quiet --upgrade pip
    pip install --quiet -r requirements.txt
    if errorlevel 1 (
        echo ERROR instalando dependencias Python
        pause
        exit /b 1
    )
    echo    Dependencias Python instaladas
) else (
    echo    Dependencias Python OK
)

:: ==========================================
:: 3. VERIFICAR/INSTALAR PLAYWRIGHT + CHROMIUM
:: ==========================================
echo [3/6] Verificando Playwright + Chromium...
python -c "from playwright.async_api import async_playwright" 2>nul
if errorlevel 1 (
    echo    Instalando Playwright...
    pip install --quiet playwright
)
playwright install chromium 2>nul
if errorlevel 1 (
    echo    Instalando Chromium...
    playwright install chromium
)
echo    Playwright + Chromium OK

:: ==========================================
:: 4. VERIFICAR/INICIAR MARIADB
:: ==========================================
echo [4/6] Verificando MariaDB...
tasklist /FI "IMAGENAME eq mysqld.exe" | find "mysqld.exe" >nul
if errorlevel 1 (
    echo    MariaDB no esta corriendo. Iniciando...
    cd c:\xampp\mysql\bin
    start "" /b mysqld.exe --defaults-file=c:\xampp\mysql\bin\my.ini
    timeout /t 5 >nul
    tasklist /FI "IMAGENAME eq mysqld.exe" | find "mysqld.exe" >nul
    if errorlevel 1 (
        echo ERROR: No se pudo iniciar MariaDB
        echo Verifique que XAMPP esta instalado en c:\xampp
        pause
        exit /b 1
    )
    echo    MariaDB iniciado correctamente
) else (
    echo    MariaDB ya esta corriendo
)

:: Verificar puerto 3306
timeout /t 2 >nul
netstat -an | findstr :3306 >nul
if errorlevel 1 (
    echo WARNING: Puerto 3306 no parece estar escuchando
    echo Intentando conectar de todas formas...
)

:: ==========================================
:: 5. VERIFICAR CONFIG.YAML
:: ==========================================
echo [5/6] Verificando configuracion...
if not exist config.yaml (
    echo ERROR: No existe config.yaml
    echo Asegurese de ejecutar este script desde la carpeta del proyecto
    pause
    exit /b 1
)
echo    config.yaml OK

:: ==========================================
:: 6. EJECUTAR TEST DE FORMATOS
:: ==========================================
echo [6/6] Ejecutando test de formatos (10 archivos)...
echo.
echo ==========================================
echo  INICIANDO TEST DE FORMATOS
echo ==========================================
echo.

python test_formats.py

echo.
echo ==========================================
echo  TEST COMPLETADO
echo ==========================================
echo.
echo Resultados en: .\analysis\
echo Logs en consola arriba
echo.
pause