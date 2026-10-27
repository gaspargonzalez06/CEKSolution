# CEK — Sistema de agentes, clientes y mercado eléctrico (Panamá)

Solución que **unifica la automatización de datos del CND con una app de gestión**
(usuarios, agentes, distribuidores, clientes, contratos, reclamaciones y dashboard).

```
AnalisisDescarga/
├─ CND_Scraper/        # Automatización (Playwright) + carga a MariaDB + análisis
├─ cek_backend/        # API (FastAPI + SQLAlchemy + MariaDB)
├─ cek_app/            # App Flutter (Web + móvil)
└─ CND_Flow_Explorer/  # Esquema de la base vieja (CEK / SQL Server)
```

## Componentes

### 1) Backend — `cek_backend/`
API REST en **FastAPI** que unifica todo:
- **Auth JWT** con roles: `admin`, `operador`, `cliente`, `agente`.
- **Agentes** (participantes del mercado) con **credenciales del portal CND cifradas** (Fernet) para la automatización.
- **Distribuidores** (agentes con flag `distribuidor` = agencias que venden luz).
- **Clientes** (cuelgan de un distribuidor), **Contratos** (agente ↔ cliente), **Reclamaciones** (plazo = hecho + 3 meses).
- **Dashboard** con resumen de entidades + data real del mercado (`sustento_horario`).
- **Automatización**: lanza el scraper con las credenciales guardadas del agente.

Arranque:
```bat
cek_backend\run.bat
```
- API: http://localhost:8000 · Docs: http://localhost:8000/docs
- Primer arranque crea el **admin** (`admin` / `admin123`, configurable en `.env`).

### 2) App — `cek_app/` (Flutter Web + móvil)
- Login, dashboard, y mantenimiento de **agentes** (con sus claves) y **usuarios**.
- Distribuidores, Clientes, Contratos, Reclamaciones y Automatización: módulos marcados "en construcción".
- La URL del backend se define con `--dart-define=API_BASE=...`.

Desarrollo (Chrome):
```bat
cd cek_app
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
```
Producción web:
```bat
flutter build web --dart-define=API_BASE=https://api.tudominio.com
```

### 3) Automatización — `CND_Scraper/`
- `cnd_sync.py`: login headless, descarga incremental (CSV/TXT/ZIP/PDF), guarda crudos y carga a MariaDB.
  Acepta `--user` / `--password` (o variables `CND_USER` / `CND_PASSWORD`) para usar las credenciales del agente.
- `extraer_sustento.py`: carga los `reporte_totales` a `sustento_horario`.
- `dashboard_sustentos.py`: genera el dashboard HTML de la evolución de parciales vs total.

## Modelo de datos (replica el esquema viejo + lo nuevo)

| Tabla | Descripción |
|---|---|
| `usuarios` | acceso y roles (admin/operador/cliente/agente) |
| `agentes` | participantes; flags `distribuidor` / `generador`; `codigo_cnd` liga con la data del mercado |
| `agente_credenciales` | usuario/clave del portal CND (cifrada) por agente |
| `clientes` | clientes (con `id_distribuidor`, NIS, etc.) |
| `contratos` | ligan agente ↔ cliente |
| `reclamaciones` | reclamos con fecha límite (hecho + 3 meses) |
| `sustento_horario` | data real del CND (parciales y totales por hora) |

## Puesta en marcha rápida
1. **MariaDB** (XAMPP) encendida en `127.0.0.1:3306`, base `cek`.
2. **Backend**: `cek_backend\run.bat`
3. **App**: `cd cek_app && flutter run -d chrome --dart-define=API_BASE=http://localhost:8000`
4. Entra con `admin` / `admin123`, crea un **agente** y guárda­le sus **credenciales del portal**.

## Roadmap
- [x] Backend base (usuarios, roles, agentes + claves, dashboard).
- [x] App Flutter (login, dashboard, agentes, usuarios).
- [x] Puente de automatización (scraper con credenciales del agente).
- [ ] Mantenimiento de distribuidores, clientes y contratos (pantallas).
- [ ] Detección automática de reclamaciones (~3 meses).
- [ ] Descarga de los **detalles** del CND (xlsx) para poblar clientes/contratos.
- [ ] Migración de la capa de datos a **SQL Server (CEK)**.
- [ ] Despliegue online (web + móvil) y automatización diaria.
