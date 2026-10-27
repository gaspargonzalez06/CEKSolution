# Levanta la aplicacion completa: backend (FastAPI) + frontend (Flutter web compilado).
#
# Requisitos previos:
#   - MariaDB/MySQL corriendo en el puerto 3306 con la base de datos "cek".
#   - Haber compilado el frontend al menos una vez:
#       cd cek_app ; flutter build web --dart-define=API_BASE=http://localhost:8000
#
# Uso:  .\iniciar.ps1

$raiz = $PSScriptRoot
$backend = Join-Path $raiz 'cek_backend'
$web = Join-Path $raiz 'cek_app\build\web'

if (-not (Test-Path $web)) {
    Write-Host "No existe $web. Compile el frontend primero:" -ForegroundColor Yellow
    Write-Host "  cd cek_app" -ForegroundColor Yellow
    Write-Host "  flutter build web --dart-define=API_BASE=http://localhost:8000" -ForegroundColor Yellow
}

Write-Host "Iniciando backend en http://127.0.0.1:8000 ..." -ForegroundColor Green
Start-Process powershell -ArgumentList @(
    '-NoExit', '-Command',
    "cd '$backend'; `$env:PYTHONIOENCODING='utf-8'; .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000"
)

Write-Host "Iniciando frontend en http://127.0.0.1:8080 ..." -ForegroundColor Green
Start-Process powershell -ArgumentList @(
    '-NoExit', '-Command',
    "cd '$web'; python -m http.server 8080 --bind 127.0.0.1"
)

Start-Sleep -Seconds 4
Write-Host "Abriendo la aplicacion..." -ForegroundColor Green
Start-Process 'http://localhost:8080'

Write-Host ""
Write-Host "Listo. Usuario por defecto: admin / admin123" -ForegroundColor Cyan
