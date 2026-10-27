@echo off
REM ==== CEK API - arranque (Windows) ====
cd /d %~dp0

if not exist .venv (
    echo Creando entorno virtual...
    python -m venv .venv
)

call .venv\Scripts\activate.bat

echo Instalando dependencias...
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

if not exist .env (
    echo Creando .env a partir de .env.example...
    copy .env.example .env >nul
)

echo.
echo   API:   http://localhost:8000
echo   Docs:  http://localhost:8000/docs
echo.
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
