"""
Database module for MariaDB connection pool and operations.
"""
import asyncio
import hashlib
import json
import os
from datetime import datetime
from typing import List, Dict, Any, Optional
from contextlib import asynccontextmanager
from dataclasses import dataclass

import aiomysql


@dataclass
class DBConfig:
    host: str = "127.0.0.1"
    port: int = 3306
    user: str = "root"
    password: str = ""
    database: str = "cek"
    minsize: int = 2
    maxsize: int = 10


class MariaDBPool:
    """MariaDB connection pool with async support."""
    
    def __init__(self, config: DBConfig):
        self.config = config
        self.pool: Optional[aiomysql.Pool] = None
    
    async def connect(self):
        """Initialize connection pool."""
        self.pool = await aiomysql.create_pool(
            host=self.config.host,
            port=self.config.port,
            user=self.config.user,
            password=self.config.password,
            db=self.config.database,
            charset='utf8mb4',
            autocommit=True,
            minsize=self.config.minsize,
            maxsize=self.config.maxsize,
        )
    
    async def close(self):
        if self.pool:
            self.pool.close()
            await self.pool.wait_closed()
    
    @asynccontextmanager
    async def acquire(self):
        async with self.pool.acquire() as conn:
            async with conn.cursor(aiomysql.DictCursor) as cur:
                yield cur
    
    async def execute(self, query: str, params: tuple = None) -> int:
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return cur.rowcount
    
    async def fetchall(self, query: str, params: tuple = None) -> List[Dict]:
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return await cur.fetchall()
    
    async def fetchone(self, query: str, params: tuple = None) -> Optional[Dict]:
        async with self.acquire() as cur:
            await cur.execute(query, params)
            return await cur.fetchone()


class ScrapingLogDB:
    """Manages scraping log for incremental processing."""
    
    def __init__(self, db_pool):
        self.db = db_pool
    
    async def is_processed(self, cliente_codigo: str, periodo: str, 
                           reporte_tipo: str, archivo_hash: str) -> bool:
        """Check if file was already processed."""
        query = """
        SELECT 1 FROM scraping_log 
        WHERE cliente_codigo = %s AND periodo = %s 
          AND reporte_tipo = %s AND archivo_hash = %s
          AND estado IN ('PROCESADO', 'NUEVO')
        """
        result = await self.db.fetchone(query, (cliente_codigo, periodo, reporte_tipo, archivo_hash))
        return result is not None
    
    async def log_start(self, cliente_codigo: str, cliente_nombre: str,
                        periodo: str, reporte_tipo: str, 
                        archivo_nombre: str, archivo_hash: str,
                        archivo_tamano: int = 0) -> int:
        """Log start of processing."""
        query = """
        INSERT INTO scraping_log 
        (cliente_codigo, cliente_nombre, periodo, reporte_tipo, 
         archivo_nombre, archivo_hash, archivo_tamano, estado)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'PROCESANDO')
        ON DUPLICATE KEY UPDATE 
            estado = 'PROCESANDO', fecha_inicio = NOW(), fecha_fin = NULL
        """
        await self.db.execute(query, (
            cliente_codigo, cliente_nombre, periodo, reporte_tipo,
            archivo_nombre, archivo_hash, 0
        ))
        return await self._get_last_id()
    
    async def _get_last_id(self) -> int:
        async with self.db.acquire() as cur:
            await cur.execute("SELECT LAST_INSERT_ID() as id")
            result = await cur.fetchone()
            return result['id'] if result else 0
    
    async def log_finish(self, log_id: int, estado: str, 
                         insertados: int = 0, actualizados: int = 0,
                         error: str = None):
        """Log completion of processing."""
        query = """
        UPDATE scraping_log 
        SET estado = %s, fecha_fin = NOW(),
            registros_insertados = %s, registros_actualizados = %s,
            error_mensaje = %s
        WHERE id = %s
        """
        await self.db.execute(query, (estado, insertados, 0, error, log_id))
    
    def file_hash(self, filepath: str) -> str:
        """Calculate SHA256 hash of file."""
        h = hashlib.sha256()
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                h.update(chunk)
        return h.hexdigest()


async def init_database(db_pool):
    """Initialize database schema."""
    schema_sql = """
    CREATE DATABASE IF NOT EXISTS cek CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    USE cek;
    
    CREATE TABLE IF NOT EXISTS scraping_log (
        id BIGINT NOT NULL AUTO_INCREMENT,
        cliente_codigo VARCHAR(20) NOT NULL,
        cliente_nombre VARCHAR(100) DEFAULT NULL,
        periodo CHAR(6) NOT NULL,
        reporte_tipo VARCHAR(50) NOT NULL,
        archivo_nombre VARCHAR(255) NOT NULL,
        archivo_hash CHAR(64) NOT NULL,
        archivo_tamano BIGINT DEFAULT NULL,
        estado ENUM('PENDIENTE','PROCESANDO','PROCESADO','ERROR','SALTADO') DEFAULT 'PENDIENTE',
        registros_nuevos INT DEFAULT 0,
        registros_actualizados INT DEFAULT 0,
        error_mensaje TEXT DEFAULT NULL,
        fecha_inicio DATETIME DEFAULT CURRENT_TIMESTAMP,
        fecha_fin DATETIME DEFAULT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uk_scraping_log (cliente_codigo, periodo, reporte_tipo, archivo_hash),
        INDEX idx_scraping_cliente_periodo (cliente_codigo, periodo),
        INDEX idx_scraping_estado (estado)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    
    CREATE TABLE IF NOT EXISTS raw_data (
        id BIGINT NOT NULL AUTO_INCREMENT,
        cliente_codigo VARCHAR(20) NOT NULL,
        periodo CHAR(6) NOT NULL,
        reporte_tipo VARCHAR(50) NOT NULL,
        archivo_nombre VARCHAR(255) NOT NULL,
        archivo_hash CHAR(64) NOT NULL,
        archivo_tamano BIGINT DEFAULT NULL,
        data_json LONGTEXT NOT NULL,
        campos_detectados JSON DEFAULT NULL,
        archivo_origen VARCHAR(255) DEFAULT NULL,
        fecha_carga DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uk_raw_data (cliente_codigo, periodo, reporte_tipo, archivo_hash),
        INDEX idx_raw_cliente_periodo (cliente_codigo, periodo),
        INDEX idx_raw_tipo (reporte_tipo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    
    CREATE TABLE IF NOT EXISTS dte (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        key_file VARCHAR(20), annio INT, mes INT,
        generador VARCHAR(20), cliente VARCHAR(20), codigo_agente VARCHAR(20),
        transaccion VARCHAR(100), tipo VARCHAR(50), u_m VARCHAR(10),
        cantidad DECIMAL(10,3), atributo VARCHAR(10), valor DECIMAL(9,2),
        periodo CHAR(6) GENERATED ALWAYS AS (CONCAT(annio, LPAD(mes,2,'0'))) STORED,
        archivo_origen VARCHAR(255), fecha_carga DATETIME DEFAULT CURRENT_TIMESTAMP,
        hash_fila CHAR(64) GENERATED ALWAYS AS (SHA2(CONCAT_WS('|', cliente, generador, periodo, transaccion, atributo, valor), 256)) STORED,
        UNIQUE KEY uk_dte_upsert (cliente, generador, periodo, transaccion, atributo, hash_fila),
        INDEX idx_dte_periodo (periodo), INDEX idx_dte_generador (generador)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """
    async with db_pool.acquire() as cur:
        for statement in schema_sql.strip().split(';'):
            stmt = statement.strip()
            if stmt:
                await cur.execute(statement)
        print("[OK] Database schema initialized")