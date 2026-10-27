@echo off
REM ============================================================
REM  CEK - Levanta el backend y la app web (desarrollo)
REM ============================================================
cd /d %~dp0

echo Iniciando BACKEND (FastAPI)...
start "CEK API" cmd /k "cek_backend\run.bat"

echo Esperando 5s a que arranque la API...
timeout /t 5 /nobreak >nul

echo Iniciando APP WEB (Flutter)...
start "CEK WEB" cmd /k "cd cek_app && flutter run -d chrome --dart-define=API_BASE=http://localhost:8000"

echo.
echo   API:  http://localhost:8000/docs
echo   App:  se abrira en Chrome (Flutter)
echo.
echo Usuario inicial: admin / admin123
pause
