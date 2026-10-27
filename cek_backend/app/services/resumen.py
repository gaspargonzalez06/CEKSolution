# -*- coding: utf-8 -*-
"""Tablas resumen del mercado para que el dashboard responda rapido.

Se calculan una sola vez (tras cargar sustento_horario) en lugar de agregar
millones de filas en cada carga del panel. Guardan:
  - sustento_mercado_resumen : totales del ultimo reporte por periodo
  - sustento_agente_resumen  : consumo por agente (ultimo reporte por periodo)
  - sustento_version_resumen : totales por (periodo, version)
  - sustento_diahora_resumen : consumo por (periodo, version, dia, hora)
  - sustento_bri_resumen     : detalle diario de BRILLOSOL (monto ocasional)
"""
import logging

from sqlalchemy import text

from app.core.database import engine

log = logging.getLogger("cek.resumen")

# Periodo base de analisis (texto 'YYYYMM'); el router lo recalcula solo.
_DDL = [
    """
    CREATE TABLE IF NOT EXISTS sustento_mercado_resumen (
        periodo CHAR(6) NOT NULL,
        version_num INT NULL,
        fecha_pub DATETIME NULL,
        filas BIGINT NOT NULL DEFAULT 0,
        consumo DOUBLE NULL,
        energia_asignada DOUBLE NULL,
        ocasional_monto DOUBLE NULL,
        actualizado TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (periodo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS sustento_agente_resumen (
        periodo CHAR(6) NOT NULL,
        version_num INT NULL,
        agente VARCHAR(25) NOT NULL,
        consumo DOUBLE NULL,
        PRIMARY KEY (periodo, agente),
        KEY ix_resumen_agente (agente)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS sustento_version_resumen (
        periodo CHAR(6) NOT NULL,
        version_num INT NOT NULL,
        reporte_id BIGINT NULL,
        reporte_tipo VARCHAR(50) NULL,
        fecha_pub DATETIME NULL,
        dias INT NOT NULL DEFAULT 0,
        filas BIGINT NOT NULL DEFAULT 0,
        consumo DOUBLE NULL,
        energia_asignada DOUBLE NULL,
        perdida_consumo DOUBLE NULL,
        ocasional_monto DOUBLE NULL,
        es_total TINYINT NOT NULL DEFAULT 0,
        actualizado TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (periodo, version_num),
        KEY ix_version_tipo (reporte_tipo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS sustento_diahora_resumen (
        periodo CHAR(6) NOT NULL,
        version_num INT NOT NULL,
        fecha DATE NOT NULL,
        hora TINYINT NOT NULL,
        consumo DOUBLE NULL,
        PRIMARY KEY (periodo, version_num, fecha, hora)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS sustento_bri_resumen (
        periodo CHAR(6) NOT NULL,
        version_num INT NOT NULL,
        fecha DATE NOT NULL,
        ocasional_monto DOUBLE NULL,
        energia_asignada DOUBLE NULL,
        PRIMARY KEY (periodo, version_num, fecha)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
]

_INSERT_MERCADO = """
INSERT INTO sustento_mercado_resumen
    (periodo, version_num, fecha_pub, filas, consumo, energia_asignada, ocasional_monto)
SELECT s.periodo, s.version_num, MAX(s.fecha_pub), COUNT(*),
       ROUND(SUM(s.consumo), 1), ROUND(SUM(s.energia_asignada), 1),
       ROUND(SUM(s.ocasional_monto), 1)
FROM sustento_horario s
JOIN (SELECT periodo, MAX(version_num) AS v
        FROM sustento_horario GROUP BY periodo) m
  ON m.periodo = s.periodo AND m.v = s.version_num
GROUP BY s.periodo, s.version_num
"""

_INSERT_AGENTE = """
INSERT INTO sustento_agente_resumen (periodo, version_num, agente, consumo)
SELECT s.periodo, s.version_num, s.agente, ROUND(SUM(s.consumo), 1)
FROM sustento_horario s
JOIN (SELECT periodo, MAX(version_num) AS v
        FROM sustento_horario GROUP BY periodo) m
  ON m.periodo = s.periodo AND m.v = s.version_num
GROUP BY s.periodo, s.version_num, s.agente
"""

_INSERT_VERSION = """
INSERT INTO sustento_version_resumen
    (periodo, version_num, reporte_id, reporte_tipo, fecha_pub, dias, filas,
     consumo, energia_asignada, perdida_consumo, ocasional_monto, es_total)
SELECT s.periodo, s.version_num, s.reporte_id, t.reporte_tipo, MAX(s.fecha_pub),
       COUNT(DISTINCT s.fecha), COUNT(*),
       ROUND(SUM(s.consumo), 1), ROUND(SUM(s.energia_asignada), 1),
       ROUND(SUM(s.perdida_consumo), 1), ROUND(SUM(s.ocasional_monto), 1),
       MAX(CASE WHEN t.reporte_tipo = 'CND_DTE_SUSTENTOS' THEN 1 ELSE 0 END)
FROM sustento_horario s
LEFT JOIN (SELECT reporte_id, MAX(reporte_tipo) AS reporte_tipo
             FROM raw_data GROUP BY reporte_id) t
       ON t.reporte_id = s.reporte_id
GROUP BY s.periodo, s.version_num, s.reporte_id, t.reporte_tipo
"""

_INSERT_DIAHORA = """
INSERT INTO sustento_diahora_resumen (periodo, version_num, fecha, hora, consumo)
SELECT periodo, version_num, fecha, hora, ROUND(SUM(consumo), 4)
FROM sustento_horario
GROUP BY periodo, version_num, fecha, hora
"""

_INSERT_BRI = """
INSERT INTO sustento_bri_resumen (periodo, version_num, fecha, ocasional_monto, energia_asignada)
SELECT periodo, version_num, fecha,
       ROUND(SUM(ocasional_monto), 4), ROUND(SUM(energia_asignada), 4)
FROM sustento_horario
WHERE agente = 'BRILLOSOL'
GROUP BY periodo, version_num, fecha
"""


def asegurar_tablas(conn):
    for ddl in _DDL:
        conn.execute(text(ddl))


def esta_vacio(conn) -> bool:
    try:
        n = conn.execute(text("SELECT COUNT(*) FROM sustento_version_resumen")).scalar()
        return (n or 0) == 0
    except Exception:
        return True


def refrescar(conn):
    """Recalcula las tablas resumen (costoso; se ejecuta tras cargar sustento)."""
    asegurar_tablas(conn)
    for tabla, sql in (
        ("sustento_mercado_resumen", _INSERT_MERCADO),
        ("sustento_agente_resumen", _INSERT_AGENTE),
        ("sustento_version_resumen", _INSERT_VERSION),
        ("sustento_diahora_resumen", _INSERT_DIAHORA),
        ("sustento_bri_resumen", _INSERT_BRI),
    ):
        log.info("Recalculando %s…", tabla)
        conn.execute(text("DELETE FROM " + tabla))
        conn.execute(text(sql))


def refrescar_si_vacio():
    """Crea/actualiza las tablas resumen solo si estan vacias (seguro al arrancar)."""
    with engine.begin() as conn:
        asegurar_tablas(conn)
        if esta_vacio(conn):
            log.info("Generando tablas resumen del mercado (una sola vez)…")
            refrescar(conn)
            log.info("Tablas resumen listas.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    log.info("Recalculando tablas resumen del mercado…")
    with engine.begin() as conn:
        refrescar(conn)
    log.info("Listo.")
