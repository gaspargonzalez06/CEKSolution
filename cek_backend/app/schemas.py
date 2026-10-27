# -*- coding: utf-8 -*-
"""Esquemas Pydantic (entrada / salida de la API)."""
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --------------------------------------------------------------------------- #
# Autenticacion
# --------------------------------------------------------------------------- #
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    usuario: "UsuarioOut"


# --------------------------------------------------------------------------- #
# Usuarios
# --------------------------------------------------------------------------- #
class UsuarioBase(BaseModel):
    usuario: str = Field(min_length=3, max_length=50)
    nombre: str | None = None
    email: str | None = None
    rol: str = "cliente"
    activo: bool = True
    id_agente: int | None = None
    id_cliente: int | None = None


class UsuarioCreate(UsuarioBase):
    password: str = Field(min_length=4)


class UsuarioUpdate(BaseModel):
    nombre: str | None = None
    email: str | None = None
    rol: str | None = None
    activo: bool | None = None
    id_agente: int | None = None
    id_cliente: int | None = None
    password: str | None = Field(default=None, min_length=4)


class UsuarioOut(ORMModel):
    id: int
    usuario: str
    nombre: str | None = None
    email: str | None = None
    rol: str
    activo: bool
    id_agente: int | None = None
    id_cliente: int | None = None
    creado: datetime | None = None


class AccesosIn(BaseModel):
    """Acceso customizable de un usuario: agentes completos y/o clientes sueltos."""
    agentes: list[int] = []
    clientes: list[int] = []


class AccesosOut(BaseModel):
    id_usuario: int
    agentes: list[int] = []
    clientes: list[int] = []
    # clientes efectivos = asignados + los de sus agentes
    clientes_efectivos: list[int] = []


# --------------------------------------------------------------------------- #
# Credenciales del agente (para la automatizacion)
# --------------------------------------------------------------------------- #
class CredencialIn(BaseModel):
    usuario_portal: str | None = None
    password_portal: str | None = None
    url_portal: str | None = None
    activo: bool = True


class CredencialOut(ORMModel):
    id: int
    id_agente: int
    usuario_portal: str | None = None
    url_portal: str | None = None
    activo: bool
    ultimo_login: datetime | None = None
    # La contrasena NUNCA se devuelve


# --------------------------------------------------------------------------- #
# Agentes
# --------------------------------------------------------------------------- #
class AgenteBase(BaseModel):
    nombre: str | None = None
    codigo: str = Field(min_length=1, max_length=20)
    ruc: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    contacto: str | None = None
    alias: str | None = None
    email: str | None = None
    distribuidor: bool = False
    id_distribuidor: int | None = None
    nis: str | None = None
    generador: bool = False
    ley15: float | None = None
    banco: str | None = None
    tipo_cuenta: str | None = None
    numero_cuenta: str | None = None
    codigo_cnd: str | None = None
    gestionado: bool = False
    activo: bool = True


class AgenteCreate(AgenteBase):
    # Los agentes que se crean desde la app son, por defecto, gestionados por CEK.
    gestionado: bool = True
    credencial: CredencialIn | None = None


class AgenteUpdate(BaseModel):
    nombre: str | None = None
    codigo: str | None = None
    ruc: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    contacto: str | None = None
    alias: str | None = None
    email: str | None = None
    distribuidor: bool | None = None
    id_distribuidor: int | None = None
    nis: str | None = None
    generador: bool | None = None
    ley15: float | None = None
    banco: str | None = None
    tipo_cuenta: str | None = None
    numero_cuenta: str | None = None
    codigo_cnd: str | None = None
    gestionado: bool | None = None
    activo: bool | None = None
    credencial: CredencialIn | None = None


class AgenteOut(ORMModel):
    id: int
    nombre: str | None = None
    codigo: str
    ruc: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    contacto: str | None = None
    alias: str | None = None
    email: str | None = None
    distribuidor: bool
    id_distribuidor: int | None = None
    nis: str | None = None
    generador: bool
    ley15: float | None = None
    banco: str | None = None
    tipo_cuenta: str | None = None
    numero_cuenta: str | None = None
    codigo_cnd: str | None = None
    gestionado: bool = False
    activo: bool
    credencial: CredencialOut | None = None


# --------------------------------------------------------------------------- #
# Clientes
# --------------------------------------------------------------------------- #
class ClienteBase(BaseModel):
    nombre: str | None = None
    codigo: str = Field(min_length=1, max_length=20)
    ruc: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    contacto: str | None = None
    alias: str | None = None
    email: str | None = None
    id_distribuidor: int | None = None
    nis: str | None = None
    descuento: float | None = None
    costo_mercado: float | None = None
    activo: bool = True


class ClienteCreate(ClienteBase):
    pass


class ClienteUpdate(BaseModel):
    nombre: str | None = None
    codigo: str | None = None
    ruc: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    contacto: str | None = None
    alias: str | None = None
    email: str | None = None
    id_distribuidor: int | None = None
    nis: str | None = None
    descuento: float | None = None
    costo_mercado: float | None = None
    activo: bool | None = None


class ClienteOut(ORMModel, ClienteBase):
    id: int


class ClienteDetalle(ClienteOut):
    """Cliente + agente/contrato con el que realmente se le factura."""

    id_agente: int | None = None
    agente_codigo: str | None = None
    agente_nombre: str | None = None
    contrato: str | None = None
    tarifa: str | None = None


# --------------------------------------------------------------------------- #
# Contratos
# --------------------------------------------------------------------------- #
class ContratoBase(BaseModel):
    contrato: str | None = None
    id_agente: int
    id_cliente: int
    inicio: datetime | None = None
    final: datetime | None = None
    interes: float | None = None
    garantia: str | None = None
    indexacion: str | None = None
    medicion: str | None = None
    activo: bool = True


class ContratoCreate(ContratoBase):
    pass


class ContratoUpdate(BaseModel):
    contrato: str | None = None
    id_agente: int | None = None
    id_cliente: int | None = None
    inicio: datetime | None = None
    final: datetime | None = None
    interes: float | None = None
    garantia: str | None = None
    indexacion: str | None = None
    medicion: str | None = None
    activo: bool | None = None


class ContratoOut(ORMModel, ContratoBase):
    id: int


# --------------------------------------------------------------------------- #
# Precios por contrato
# --------------------------------------------------------------------------- #
class PrecioBase(BaseModel):
    id_contrato: int
    id_antiguo: int | None = None
    precio: float | None = None
    inicia: datetime | None = None
    termina: datetime | None = None
    tarifa: str | None = None


class PrecioCreate(PrecioBase):
    pass


class PrecioUpdate(BaseModel):
    id_contrato: int | None = None
    id_antiguo: int | None = None
    precio: float | None = None
    inicia: datetime | None = None
    termina: datetime | None = None
    tarifa: str | None = None


class PrecioOut(ORMModel, PrecioBase):
    id: int


class FacturaHistoricaOut(ORMModel):
    id: int
    generador: str | None = None
    cliente: str | None = None
    contrato: str | None = None
    id_contrato: int | None = None
    annio: int | None = None
    mes: int | None = None
    consumo: float | None = None
    precio: float | None = None
    valor: float | None = None
    costo: float | None = None
    descuento: float | None = None
    texto_otros_cargos: str | None = None
    monto_otros_cargos: float | None = None


# --------------------------------------------------------------------------- #
# Reclamaciones
# --------------------------------------------------------------------------- #
class ReclamacionBase(BaseModel):
    id_agente: int
    id_cliente: int | None = None
    id_contrato: int | None = None
    codigo: str | None = None
    tipo: str | None = None
    descripcion: str | None = None
    periodo: str | None = None
    monto: float | None = None
    estado: str = "identificada"
    fecha_hecho: datetime | None = None
    fecha_limite: datetime | None = None
    fecha_presentacion: datetime | None = None
    evidencia: str | None = None


class ReclamacionCreate(ReclamacionBase):
    pass


class ReclamacionUpdate(BaseModel):
    id_agente: int | None = None
    id_cliente: int | None = None
    id_contrato: int | None = None
    codigo: str | None = None
    tipo: str | None = None
    descripcion: str | None = None
    periodo: str | None = None
    monto: float | None = None
    estado: str | None = None
    fecha_hecho: datetime | None = None
    fecha_limite: datetime | None = None
    fecha_presentacion: datetime | None = None
    evidencia: str | None = None


class ReclamacionOut(ORMModel, ReclamacionBase):
    id: int
    creado: datetime | None = None
    actualizado: datetime | None = None


# --------------------------------------------------------------------------- #
# Seguimiento de reclamaciones
# --------------------------------------------------------------------------- #
class SeguimientoCreate(BaseModel):
    estado: str | None = None
    nota: str | None = None


class SeguimientoOut(ORMModel):
    id: int
    id_reclamacion: int
    fecha: datetime | None = None
    estado: str | None = None
    nota: str | None = None
    usuario: str | None = None


# --------------------------------------------------------------------------- #
# Ajustes / Reclamos CND (archivos Aj1, Aj2, ... del portal)
# --------------------------------------------------------------------------- #
class AjusteCNDOut(ORMModel):
    id: int
    periodo: str
    codigo: str | None = None
    nombre: str | None = None
    tipo: str | None = None
    cliente_codigo: str | None = None
    origen: str | None = None
    archivo_local: str | None = None
    reporte_id: int | None = None
    creado: datetime | None = None


class AjusteSyncResult(BaseModel):
    revisados: int
    nuevos: int
    ya_existian: int
    periodos: list[str]
    detalle: list[AjusteCNDOut]


# --------------------------------------------------------------------------- #
# Facturas
# --------------------------------------------------------------------------- #
class FacturaDetalleOut(ORMModel):
    id: int
    orden: int
    categoria: str | None = None
    descripcion: str
    consumo: str | None = None
    cantidad: float | None = None
    unidad: str | None = None
    monto: float | None = None
    es_total: bool


class OtroCargo(BaseModel):
    """Cargo adicional capturado a mano en la factura (nombre + monto)."""
    nombre: str = Field(min_length=1, max_length=120)
    monto: float


class FacturaGenerar(BaseModel):
    id_cliente: int
    periodo: str = Field(min_length=6, max_length=6)
    id_agente: int | None = None       # por defecto el agente del contrato
    id_contrato: int | None = None
    precio_kwh: float | None = None    # si no se indica, se toma de Precios (vigente)
    consumo_mwh: float | None = None   # si no se indica, se toma del cliente
    itbms_pct: float = 0.0
    dias_lectura: int | None = 30
    tarifa: str | None = None          # si no se indica, se toma de Precios (vigente)
    incluir_dte: bool = True           # sumar costos reales del mercado (DTE)
    dter_monto: float | None = None    # DTER del mes anterior (fn_DTER_Mes del sistema viejo)
    dter_periodo: str | None = None    # periodo del DTER; por defecto el mes anterior
    descuento: float | None = None     # descuento por pronto pago (monto; Facturas.Descuento)
    otros_cargos: list[OtroCargo] = []  # cargos adicionales (nombre + monto)
    observaciones: str | None = None
    graficas: str | None = None        # coma-separadas: diario,costo,historico


class FacturaGenerarLote(BaseModel):
    """Genera la factura del mismo periodo para los clientes de un agente.

    Es la pantalla de facturacion: se elige el agente y se emite una factura
    por cada uno de sus clientes con la MISMA logica que /generar.

    - id_agente: facturar todos los clientes del agente (via contratos /
      id_distribuidor).
    - id_clientes: subconjunto opcional de clientes de ese agente (por defecto,
      todos).
    """
    periodo: str = Field(min_length=6, max_length=6)
    id_agente: int | None = None      # todos los clientes del agente
    id_clientes: list[int] = []       # subconjunto (por defecto, todos del agente)
    incluir_dte: bool = True
    itbms_pct: float = 0.0
    dias_lectura: int | None = 30
    omitir_existentes: bool = True   # salta los que ya tienen factura del periodo
    graficas: str | None = None      # coma-separadas: diario,costo,historico


class FacturaUpdate(BaseModel):
    estado: str | None = None
    observaciones: str | None = None
    precio_kwh: float | None = None
    consumo_mwh: float | None = None
    itbms_pct: float | None = None
    fecha_vencimiento: datetime | None = None


class FacturaOut(ORMModel):
    id: int
    numero: str
    id_agente: int
    id_cliente: int
    id_contrato: int | None = None
    periodo: str
    tarifa: str | None = None
    moneda: str
    precio_kwh: float | None = None
    consumo_mwh: float | None = None
    dias_lectura: int | None = None
    subtotal: float
    itbms_pct: float
    itbms: float
    total: float
    estado: str
    fecha_emision: datetime | None = None
    fecha_vencimiento: datetime | None = None
    observaciones: str | None = None
    graficas: str | None = None
    creado: datetime | None = None
    cliente_nombre: str | None = None
    agente_nombre: str | None = None
    detalles: list[FacturaDetalleOut] = []


# Resolver referencias hacia adelante
Token.model_rebuild()
