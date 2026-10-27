# CEK API (backend)

Backend en **FastAPI + SQLAlchemy + MariaDB** que unifica:
- **Usuarios y roles** (admin, operador, cliente, agente) con login JWT.
- **Agentes** (participantes del mercado) con **credenciales del portal CND** guardadas y cifradas, para la automatización (scraper Playwright).
- **Distribuidores** (agentes con flag `distribuidor` = agencias que venden luz).
- **Clientes** (cuelgan de un distribuidor) y **Contratos** (ligan agente ↔ cliente).
- **Reclamaciones** (con fecha límite = hecho + 3 meses).
- **Dashboard** de resumen (entidades + data real del mercado desde `sustento_horario`).

## Arranque rápido

```bat
run.bat
```

Eso crea el entorno virtual, instala dependencias, copia `.env` y levanta la API.

- API: http://localhost:8000
- Documentación interactiva: http://localhost:8000/docs

Al primer arranque se crea el usuario **admin** (ver `.env`:
`ADMIN_USER` / `ADMIN_PASSWORD`, por defecto `admin` / `admin123`).

## Login

```bash
curl -X POST http://localhost:8000/auth/login \
  -d "username=admin&password=admin123"
```

Devuelve un `access_token` (JWT). En Swagger puedes usar el botón **Authorize**.

## Estructura

```
cek_backend/
  app/
    core/       config, database, security (hash+JWT), deps (roles), bootstrap
    models.py   tablas (esquema viejo + usuarios/credenciales/reclamaciones)
    schemas.py  entrada/salida de la API (Pydantic)
    routers/    auth, usuarios, agentes, distribuidores, clientes, contratos,
                reclamaciones, dashboard, automatizacion
    services/   crypto (cifrado Fernet) y automatizacion (puente al scraper)
    main.py     app FastAPI
  requirements.txt
  run.bat
  .env.example
```

## Seguridad

- Contraseñas con **PBKDF2-SHA256**.
- Tokens **JWT** (`JWT_SECRET`, `JWT_MINUTES`).
- Claves del portal de los agentes **cifradas con Fernet** (`FERNET_KEY`); nunca se
  devuelven por la API.
- Roles: `admin` y `operador` pueden administrar; `cliente` y `agente` solo consultan.

## Notas

- Hoy corre sobre **MariaDB** (`cek`). La capa SQLAlchemy es portable a **SQL Server (CEK)** después.
- La tabla `agentes` replicaba el esquema viejo y estaba vacía; al arrancar se recrea
  con las columnas nuevas (si tuviera datos, avisa y hay que migrar a mano).
- El puente a la automatización lanza `../CND_Scraper/cnd_sync.py` con las credenciales
  del agente (`--user`, `--password`).
