# -*- coding: utf-8 -*-
"""Modelos de datos.

Replica el esquema viejo (CEK / SQL Server):
  - Agentes  -> participantes del mercado, con flags Distribuidor / Generador
  - Clientes -> cuelgan de un distribuidor (id_distribuidor)
  - Contratos-> ligan un agente con un cliente
Y agrega lo nuevo:
  - Usuarios / acceso (admin, operador, cliente, agente)
  - AgenteCredencial -> usuario y clave del portal CND (para la automatizacion)
  - Reclamaciones -> reclamos que pueden aparecer hasta 3 meses despues
"""
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    Computed,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, autoincrement=True)
    usuario = Column(String(50), unique=True, nullable=False, index=True)
    nombre = Column(String(150))
    email = Column(String(150))
    password_hash = Column(String(300), nullable=False)
    # admin | operador | cliente | agente
    rol = Column(String(20), nullable=False, default="cliente")
    activo = Column(Boolean, nullable=False, default=True)
    id_agente = Column(Integer, ForeignKey("agentes.id"), nullable=True)
    id_cliente = Column(Integer, ForeignKey("clientes.id"), nullable=True)
    creado = Column(DateTime, default=datetime.utcnow)
    actualizado = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class UsuarioAgente(Base):
    """Acceso del usuario a un agente (y por tanto a TODOS sus clientes).

    Permite que al crear el usuario se le asignen uno o varios agentes y, en
    consecuencia, vea el consumo y las facturas de sus clientes.
    """
    __tablename__ = "usuario_agentes"
    __table_args__ = (UniqueConstraint("id_usuario", "id_agente", name="uq_usuario_agente"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_usuario = Column(Integer, ForeignKey("usuarios.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    id_agente = Column(Integer, ForeignKey("agentes.id", ondelete="CASCADE"),
                       nullable=False, index=True)


class UsuarioCliente(Base):
    """Acceso del usuario a un cliente concreto (acceso customizable y fino)."""
    __tablename__ = "usuario_clientes"
    __table_args__ = (UniqueConstraint("id_usuario", "id_cliente", name="uq_usuario_cliente"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_usuario = Column(Integer, ForeignKey("usuarios.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    id_cliente = Column(Integer, ForeignKey("clientes.id", ondelete="CASCADE"),
                        nullable=False, index=True)


class Agente(Base):
    __tablename__ = "agentes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100))
    codigo = Column(String(20), unique=True, nullable=False, index=True)
    ruc = Column(String(30))
    direccion = Column(Text)
    telefono = Column(String(20))
    contacto = Column(String(50))
    alias = Column(String(20))
    logo = Column(String(50))
    email = Column(String(50))
    # Un agente puede ser distribuidor (vende luz) y/o generador
    distribuidor = Column(Boolean, nullable=False, default=False)
    id_distribuidor = Column(Integer, ForeignKey("agentes.id"), nullable=True)
    nis = Column(String(20))
    generador = Column(Boolean, nullable=False, default=False)
    ley15 = Column(Numeric(4, 2))
    banco = Column(String(50))
    tipo_cuenta = Column(String(20))
    numero_cuenta = Column(String(20))
    # Codigo con que aparece en la data del mercado (columna AGENTE de reporte_totales)
    codigo_cnd = Column(String(40), index=True)
    # True = agente gestionado por CEK (universo con credenciales del portal privado CND).
    # El resto de filas son contrapartes del mercado, utiles como referencia pero no se listan.
    gestionado = Column(Boolean, nullable=False, default=False)
    activo = Column(Boolean, nullable=False, default=True)
    creado = Column(DateTime, default=datetime.utcnow)
    actualizado = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    credencial = relationship(
        "AgenteCredencial",
        back_populates="agente",
        uselist=False,
        cascade="all, delete-orphan",
    )
    clientes = relationship("Cliente", back_populates="distribuidor", foreign_keys="Cliente.id_distribuidor")


class AgenteCredencial(Base):
    """Usuario / clave del portal CND que usa la automatizacion (Playwright)."""

    __tablename__ = "agente_credenciales"

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_agente = Column(
        Integer, ForeignKey("agentes.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    usuario_portal = Column(String(80))
    password_portal_enc = Column(String(500))
    url_portal = Column(String(200), default="https://sitiopublico.cnd.com.pa/privado/")
    activo = Column(Boolean, nullable=False, default=True)
    ultimo_login = Column(DateTime, nullable=True)
    creado = Column(DateTime, default=datetime.utcnow)
    actualizado = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    agente = relationship("Agente", back_populates="credencial")


class ProcesoEjecucion(Base):
    """Historial de corridas del proceso masivo (descarga + importacion CND).

    `detalle` guarda un JSON con el resultado por agente para que la app pueda
    mostrar el avance mientras corre (se actualiza en cada paso).
    """

    __tablename__ = "proceso_ejecuciones"

    id = Column(Integer, primary_key=True, autoincrement=True)
    periodo = Column(String(6), nullable=True)
    modo = Column(String(20), nullable=False, default="completo")
    estado = Column(String(20), nullable=False, default="corriendo")
    agentes = Column(Text)          # JSON: codigos solicitados
    detalle = Column(Text)          # JSON: resultado por agente/paso
    mensaje = Column(Text)
    inicio = Column(DateTime, default=datetime.utcnow)
    fin = Column(DateTime, nullable=True)


class Cliente(Base):
    __tablename__ = "clientes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100))
    codigo = Column(String(20), unique=True, nullable=False, index=True)
    ruc = Column(String(30))
    direccion = Column(Text)
    telefono = Column(String(20))
    contacto = Column(String(50))
    alias = Column(String(20))
    logo = Column(String(50))
    email = Column(String(50))
    id_distribuidor = Column(Integer, ForeignKey("agentes.id"), nullable=True)
    nis = Column(String(20))
    descuento = Column(Numeric(5, 2))
    costo_mercado = Column(Numeric(12, 2))
    activo = Column(Boolean, nullable=False, default=True)
    creado = Column(DateTime, default=datetime.utcnow)

    distribuidor = relationship("Agente", back_populates="clientes", foreign_keys=[id_distribuidor])
    contratos = relationship("Contrato", back_populates="cliente")


class Contrato(Base):
    __tablename__ = "contratos"

    id = Column(Integer, primary_key=True, autoincrement=True)
    contrato = Column(String(40), index=True)
    id_antiguo = Column(Integer, index=True)  # id del contrato en la base vieja (CEK)
    id_agente = Column(Integer, ForeignKey("agentes.id"), nullable=False)
    id_cliente = Column(Integer, ForeignKey("clientes.id"), nullable=False)
    inicio = Column(DateTime, nullable=True)
    final = Column(DateTime, nullable=True)
    interes = Column(Numeric(6, 2))
    garantia = Column(String(50))
    indexacion = Column(String(50))
    medicion = Column(String(50))
    activo = Column(Boolean, nullable=False, default=True)
    creado = Column(DateTime, default=datetime.utcnow)

    agente = relationship("Agente")
    cliente = relationship("Cliente", back_populates="contratos")
    reclamaciones = relationship("Reclamacion", back_populates="contrato")
    precios = relationship("Precio", back_populates="contrato", cascade="all, delete-orphan")


class Precio(Base):
    """Tarifa/precio de un contrato con vigencia (tabla Precios del sistema viejo).

    Un contrato puede tener varios precios a lo largo del tiempo; se toma el
    vigente segun la fecha de facturacion (Inicia <= periodo <= Termina).
    """

    __tablename__ = "precios"

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_contrato = Column(Integer, ForeignKey("contratos.id"), nullable=False, index=True)
    id_antiguo = Column(Integer, index=True)  # id de la fila en la tabla Precios vieja (CEK)
    precio = Column(Numeric(12, 4))
    inicia = Column(DateTime, nullable=True)
    termina = Column(DateTime, nullable=True)
    tarifa = Column(String(40))
    creado = Column(DateTime, default=datetime.utcnow)

    contrato = relationship("Contrato", back_populates="precios")


class Reclamacion(Base):
    """Reclamo de un agente. Puede identificarse hasta ~3 meses despues del hecho."""

    __tablename__ = "reclamaciones"

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_agente = Column(Integer, ForeignKey("agentes.id"), nullable=False)
    id_cliente = Column(Integer, ForeignKey("clientes.id"), nullable=True)
    id_contrato = Column(Integer, ForeignKey("contratos.id"), nullable=True)
    codigo = Column(String(40))
    tipo = Column(String(60))
    descripcion = Column(Text)
    periodo = Column(String(6), index=True)  # AAAAMM del hecho
    monto = Column(Numeric(14, 2))
    # identificada | en_revision | presentada | aceptada | rechazada
    estado = Column(String(20), nullable=False, default="identificada")
    fecha_hecho = Column(DateTime, nullable=True)
    fecha_limite = Column(DateTime, nullable=True)  # fecha_hecho + 3 meses
    fecha_presentacion = Column(DateTime, nullable=True)
    evidencia = Column(Text)
    creado = Column(DateTime, default=datetime.utcnow)
    actualizado = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    agente = relationship("Agente")
    cliente = relationship("Cliente")
    contrato = relationship("Contrato", back_populates="reclamaciones")
    seguimiento = relationship(
        "ReclamacionSeguimiento",
        back_populates="reclamacion",
        cascade="all, delete-orphan",
        order_by="ReclamacionSeguimiento.fecha",
    )


class ReclamacionSeguimiento(Base):
    """Bitácora / avance de una reclamación (seguimiento y trazabilidad).

    Cada cambio de estado y cada nota manual quedan registrados con fecha y
    usuario, de modo que el reclamo deja de ser un simple registro y pasa a
    tener seguimiento.
    """

    __tablename__ = "reclamacion_seguimiento"

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_reclamacion = Column(
        Integer, ForeignKey("reclamaciones.id", ondelete="CASCADE"), nullable=False, index=True
    )
    fecha = Column(DateTime, default=datetime.utcnow, nullable=False)
    estado = Column(String(20))   # estado al que se pasa (None si es solo una nota)
    nota = Column(Text)
    usuario = Column(String(80))  # quien registró el movimiento
    creado = Column(DateTime, default=datetime.utcnow)

    reclamacion = relationship("Reclamacion", back_populates="seguimiento")


class AjusteCND(Base):
    """Ajuste/reclamo publicado por el CND (archivos con sufijo Aj1, Aj2, ...).

    Cuando el CND atiende un reclamo, reemite el mes completo con el sufijo AjN
    (balance DTE, sustentos, liquidacion, totales por contrato, etc.). Esta tabla
    registra esos archivos y el mes (periodo) al que corresponden.
    """

    __tablename__ = "ajustes_cnd"

    id = Column(Integer, primary_key=True, autoincrement=True)
    periodo = Column(String(6), index=True, nullable=False)   # AAAAMM del mes ajustado
    codigo = Column(String(12), index=True)                   # AJ1, AJ2, AJUSTE1...
    nombre = Column(String(255))                              # nombre del archivo
    tipo = Column(String(60))                                 # tipo de reporte
    cliente_codigo = Column(String(20))
    origen = Column(String(400))                              # ruta en el portal
    archivo_local = Column(String(500))                       # ruta local del crudo
    reporte_id = Column(Integer, index=True)                  # id del reporte en el portal
    creado = Column(DateTime, default=datetime.utcnow)


class Factura(Base):
    """Factura mensual de un agente hacia un cliente (pagina 1) + grafica (pagina 2)."""

    __tablename__ = "facturas"

    id = Column(Integer, primary_key=True, autoincrement=True)
    numero = Column(String(30), unique=True, nullable=False, index=True)
    id_agente = Column(Integer, ForeignKey("agentes.id"), nullable=False)
    id_cliente = Column(Integer, ForeignKey("clientes.id"), nullable=False)
    id_contrato = Column(Integer, ForeignKey("contratos.id"), nullable=True)
    periodo = Column(String(6), nullable=False, index=True)  # AAAAMM
    tarifa = Column(String(20))
    moneda = Column(String(6), nullable=False, default="B/.")
    precio_kwh = Column(Numeric(10, 4))
    # 6 decimales: el sistema viejo calcula la energia con el consumo real medido
    # (Mediciones.Consumo decimal(10,6)) y solo lo muestra redondeado a 3.
    consumo_mwh = Column(Numeric(14, 6))
    dias_lectura = Column(Integer)
    subtotal = Column(Numeric(14, 2), nullable=False, default=0)
    itbms_pct = Column(Numeric(5, 2), nullable=False, default=0)
    itbms = Column(Numeric(14, 2), nullable=False, default=0)
    total = Column(Numeric(14, 2), nullable=False, default=0)
    # borrador | emitida | pagada | anulada
    estado = Column(String(20), nullable=False, default="emitida")
    fecha_emision = Column(DateTime, nullable=True)
    fecha_vencimiento = Column(DateTime, nullable=True)
    observaciones = Column(Text)
    # Gráficas a imprimir en la factura (coma-separadas): diario,costo,historico
    graficas = Column(String(60), nullable=True, default="diario")
    creado = Column(DateTime, default=datetime.utcnow)

    agente = relationship("Agente")
    cliente = relationship("Cliente")
    contrato = relationship("Contrato")
    detalles = relationship(
        "FacturaDetalle",
        back_populates="factura",
        cascade="all, delete-orphan",
        order_by="FacturaDetalle.orden",
    )


class FacturaDetalle(Base):
    """Lineas de la factura. Las filas 'categoria' (es_total=False) son subtitulos."""

    __tablename__ = "factura_detalle"

    id = Column(Integer, primary_key=True, autoincrement=True)
    id_factura = Column(Integer, ForeignKey("facturas.id", ondelete="CASCADE"), nullable=False)
    orden = Column(Integer, nullable=False, default=0)
    categoria = Column(String(80))          # encabezado de bloque (opcional)
    descripcion = Column(String(200), nullable=False)
    consumo = Column(String(40))            # etiqueta de la columna "Consumos"
    cantidad = Column(Numeric(16, 3))
    unidad = Column(String(10))
    monto = Column(Numeric(14, 2))
    es_total = Column(Boolean, nullable=False, default=True)

    factura = relationship("Factura", back_populates="detalles")


class FacturaHistorica(Base):
    """Factura del sistema viejo (tabla 'Facturas' de SQL Server / CEK).

    Se conserva tal cual como registro historico ('lo del sistema viejo es la ley'):
    consumo, precio, valor, costo, descuento y otros cargos del mes facturado.
    """

    __tablename__ = "facturas_historicas"

    id = Column(Integer, primary_key=True, autoincrement=True)
    generador = Column(String(60), index=True)      # codigo del agente generador
    cliente = Column(String(60), index=True)        # codigo del cliente
    contrato = Column(String(60), index=True)       # numero de contrato (texto viejo)
    id_contrato = Column(Integer, ForeignKey("contratos.id"), nullable=True, index=True)
    annio = Column(Integer, index=True)
    mes = Column(Integer, index=True)
    consumo = Column(Numeric(16, 3))
    precio = Column(Numeric(12, 4))
    valor = Column(Numeric(16, 2))
    costo = Column(Numeric(16, 2))
    descuento = Column(Numeric(16, 2))
    texto_otros_cargos = Column(String(255))
    monto_otros_cargos = Column(Numeric(16, 2))
    creado = Column(DateTime, default=datetime.utcnow)

    contrato_rel = relationship("Contrato")


class Dte(Base):
    """DTE del mercado (crudo CND: 'balance de transacciones').

    Es la tabla que leia el sistema viejo para los CARGOS DE MERCADO de la
    factura (fn_costos / fn_CostoMercado). Se carga desde los DTE Tabulares
    con `importar_dte.py`.

    Un renglon por (cliente, transaccion, tipo, atributo):
      - atributo = 'Debito' | 'Credito'
      - neto de la transaccion = SUM(Debito) - SUM(Credito)
    """
    __tablename__ = "dte"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    key_file = Column(String(20))
    annio = Column(Integer)
    mes = Column(Integer)
    generador = Column(String(20), index=True)
    cliente = Column(String(20), index=True)
    codigo_agente = Column(String(20))          # contraparte
    transaccion = Column(String(100))
    tipo = Column(String(50))                   # 'Regular' | 'Ajuste'
    u_m = Column(String(10))
    cantidad = Column(Numeric(10, 3))
    atributo = Column(String(10))
    valor = Column(Numeric(9, 2))
    periodo = Column(String(6), Computed("concat(`annio`,lpad(`mes`,2,'0'))", persisted=True))
    archivo_origen = Column(String(255))
    fecha_carga = Column(DateTime)
    hash_fila = Column(String(64), Computed(
        "sha2(concat_ws('|',`cliente`,`generador`,`periodo`,`transaccion`,`atributo`,`valor`),256)",
        persisted=True,
    ))


class Dter(Base):
    """DTER del generador (crudo CND: 'DTER Oficial', hoja DATOS INFORMATIVOS).

    Es la tabla que leia el sistema viejo para la linea 'DTER de <mes>'
    (fn_DTER_Mes). Se carga con `importar_dter.py`.
    """
    __tablename__ = "dter"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    annio = Column(Integer)
    mes = Column(Integer)
    generador = Column(String(20), index=True)
    cliente = Column(String(20), index=True)
    transaccion = Column(String(100))
    atributo = Column(String(10))               # 'Debito' | 'Credito'
    valor = Column(Numeric(9, 2))
    periodo = Column(String(6), Computed("concat(`annio`,lpad(`mes`,2,'0'))", persisted=True))
    archivo_origen = Column(String(255))
    fecha_carga = Column(DateTime)


class Medicion(Base):
    """Consumo mensual medido por cliente (crudo CND: Liquidacion, hoja MEDICIONES).

    Es la tabla que leia el sistema viejo para el CONSUMO del cliente
    (fn_historialconsumo): alimenta la linea "Energia en contratos" y el
    historico de Consumos de la factura. Se carga con `importar_mediciones.py`.

    Un renglon por (cliente, generador, periodo). El consumo va a 6 decimales:
    el sistema viejo calculaba la energia con el consumo real medido y solo lo
    mostraba truncado a 3 (ver Factura.consumo_mwh).
    """
    __tablename__ = "mediciones"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    annio = Column(Integer)
    mes = Column(Integer)
    generador = Column(String(20), index=True)
    cliente = Column(String(20), index=True)
    consumo = Column(Numeric(14, 6))
    periodo = Column(String(6), Computed("concat(`annio`,lpad(`mes`,2,'0'))", persisted=True))
    archivo_origen = Column(String(255))
    fecha_carga = Column(DateTime)


class Homologacion(Base):
    """Homologacion de transacciones del mercado (tabla homologacion del sistema viejo).

    Da la Agrupacion con la que se presentan las transacciones en el
    Reporte Comercial y su DTER (usp_reporte_comercial / usp_reporte_comercial_DTER).
    """

    __tablename__ = "homologacion"

    id = Column(Integer, primary_key=True, autoincrement=True)
    transaccion = Column(String(100), unique=True, nullable=False)
    agrupacion = Column(String(100), nullable=False, index=True)
    creado = Column(DateTime, default=datetime.utcnow)


class AjusteValor(Base):
    """Valores de los ajustes del mercado (tabla Ajustes del sistema viejo).

    Un renglon por ajuste publicado por el CND para el balance del
    generador: la contraparte (Agente), el atributo (Debito/Credito) y el
    Valor, con la Fecha del ajuste (asiento entre periodos). La usan el
    Desglose de costos (dcctr) y los ajustes del Reporte Comercial.
    """

    __tablename__ = "ajustes_valores"

    id = Column(Integer, primary_key=True, autoincrement=True)
    fecha = Column(Date, nullable=False)
    generador = Column(String(20), nullable=False, index=True)
    agente = Column(String(20), nullable=False, index=True)
    atributo = Column(String(10), nullable=False)  # 'Debito' | 'Credito'
    valor = Column(Numeric(14, 2), nullable=False)
    creado = Column(DateTime, default=datetime.utcnow)
