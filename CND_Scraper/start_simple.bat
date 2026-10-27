@echo off
chcp 65001 >nul
title CND Scraper Simple - BRILLOSOL

echo ==========================================
echo  CND Scraper Simple - Test Formatos
echo ==========================================
echo.

echo [1/3] Verificando Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python no instalado. Instale Python 3.9+ de python.org
    pause
    exit /b 1
)
echo    Python OK

echo [2/3] Verificando dependencias...
python -c "import playwright, pandas, aiomysql, openpyxl, yaml" 2>nul
if errorlevel 1 (
    echo Instalando dependencias...
    pip install -q playwright pandas aiomysql openpyxl pyyaml
    playwright install chromium
)
echo    Dependencias OK

echo [3/3] Ejecutando scraper simple...
echo.
python simple_test.py

echo.
echo ==========================================
echo  TEST COMPLETADO
echo ==========================================
echo Revisa: .\downloads\BRILLOSOL\  y  .\debug_login.html
echo.
pause