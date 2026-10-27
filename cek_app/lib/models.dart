// Modelos de datos de la app (espejo simple de la API).

class Usuario {
  final int id;
  final String usuario;
  final String? nombre;
  final String? email;
  final String rol;
  final bool activo;

  Usuario({
    required this.id,
    required this.usuario,
    this.nombre,
    this.email,
    required this.rol,
    required this.activo,
  });

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: j['id'] as int,
        usuario: j['usuario'] as String,
        nombre: j['nombre'] as String?,
        email: j['email'] as String?,
        rol: j['rol'] as String,
        activo: j['activo'] as bool? ?? true,
      );

  String get etiqueta => (nombre != null && nombre!.isNotEmpty) ? nombre! : usuario;
}

class Agente {
  final int id;
  final String codigo;
  final String? nombre;
  final String? codigoCnd;
  final String? ruc;
  final String? email;
  final String? telefono;
  final String? direccion;
  final bool distribuidor;
  final bool generador;
  final bool gestionado;
  final bool activo;
  final bool tieneCredencial;
  final String? usuarioPortal;

  Agente({
    required this.id,
    required this.codigo,
    this.nombre,
    this.codigoCnd,
    this.ruc,
    this.email,
    this.telefono,
    this.direccion,
    required this.distribuidor,
    required this.generador,
    this.gestionado = false,
    required this.activo,
    required this.tieneCredencial,
    this.usuarioPortal,
  });

  factory Agente.fromJson(Map<String, dynamic> j) => Agente(
        id: j['id'] as int,
        codigo: j['codigo'] as String? ?? '',
        nombre: j['nombre'] as String?,
        codigoCnd: j['codigo_cnd'] as String?,
        ruc: j['ruc'] as String?,
        email: j['email'] as String?,
        telefono: j['telefono'] as String?,
        direccion: j['direccion'] as String?,
        distribuidor: j['distribuidor'] as bool? ?? false,
        generador: j['generador'] as bool? ?? false,
        gestionado: j['gestionado'] as bool? ?? false,
        activo: j['activo'] as bool? ?? true,
        tieneCredencial: j['credencial'] != null,
        usuarioPortal: (j['credencial'] as Map?)?['usuario_portal'] as String?,
      );

  String get etiqueta => (nombre != null && nombre!.isNotEmpty) ? nombre! : codigo;

  String get tipo {
    final partes = <String>[];
    if (generador) partes.add('Generador');
    if (distribuidor) partes.add('Distribuidor');
    return partes.isEmpty ? 'Agente' : partes.join(' · ');
  }
}

class Cliente {
  final int id;
  final String codigo;
  final String? nombre;
  final String? ruc;
  final String? nis;
  final String? telefono;
  final String? direccion;
  final String? contacto;
  final String? email;
  final int? idDistribuidor;
  final int? idAgente;
  final String? agenteCodigo;
  final String? agenteNombre;
  final String? contrato;
  final String? tarifa;
  final bool activo;

  Cliente({
    required this.id,
    required this.codigo,
    this.nombre,
    this.ruc,
    this.nis,
    this.telefono,
    this.direccion,
    this.contacto,
    this.email,
    this.idDistribuidor,
    this.idAgente,
    this.agenteCodigo,
    this.agenteNombre,
    this.contrato,
    this.tarifa,
    required this.activo,
  });

  factory Cliente.fromJson(Map<String, dynamic> j) => Cliente(
        id: j['id'] as int,
        codigo: j['codigo'] as String? ?? '',
        nombre: j['nombre'] as String?,
        ruc: j['ruc'] as String?,
        nis: j['nis'] as String?,
        telefono: j['telefono'] as String?,
        direccion: j['direccion'] as String?,
        contacto: j['contacto'] as String?,
        email: j['email'] as String?,
        idDistribuidor: j['id_distribuidor'] as int?,
        idAgente: j['id_agente'] as int?,
        agenteCodigo: j['agente_codigo'] as String?,
        agenteNombre: j['agente_nombre'] as String?,
        contrato: j['contrato'] as String?,
        tarifa: j['tarifa'] as String?,
        activo: j['activo'] as bool? ?? true,
      );

  String get etiqueta => (nombre != null && nombre!.isNotEmpty) ? nombre! : codigo;
}

class Contrato {
  final int id;
  final String? contrato;
  final int idAgente;
  final int idCliente;
  final String? inicio;
  final String? fin;
  final double? interes;
  final String? garantia;
  final String? indexacion;
  final String? medicion;
  final bool activo;

  Contrato({
    required this.id,
    this.contrato,
    required this.idAgente,
    required this.idCliente,
    this.inicio,
    this.fin,
    this.interes,
    this.garantia,
    this.indexacion,
    this.medicion,
    required this.activo,
  });

  factory Contrato.fromJson(Map<String, dynamic> j) => Contrato(
        id: j['id'] as int,
        contrato: j['contrato'] as String?,
        idAgente: j['id_agente'] as int,
        idCliente: j['id_cliente'] as int,
        inicio: j['inicio'] as String?,
        fin: j['final'] as String?,
        interes: (j['interes'] as num?)?.toDouble(),
        garantia: j['garantia'] as String?,
        indexacion: j['indexacion'] as String?,
        medicion: j['medicion'] as String?,
        activo: j['activo'] as bool? ?? true,
      );
}

class Precio {
  final int id;
  final int idContrato;
  final int? idAntiguo;
  final double? precio;
  final String? inicia;
  final String? termina;
  final String? tarifa;

  Precio({
    required this.id,
    required this.idContrato,
    this.idAntiguo,
    this.precio,
    this.inicia,
    this.termina,
    this.tarifa,
  });

  factory Precio.fromJson(Map<String, dynamic> j) => Precio(
        id: j['id'] as int,
        idContrato: j['id_contrato'] as int,
        idAntiguo: j['id_antiguo'] as int?,
        precio: (j['precio'] as num?)?.toDouble(),
        inicia: j['inicia'] as String?,
        termina: j['termina'] as String?,
        tarifa: j['tarifa'] as String?,
      );
}

/// Factura del sistema viejo (tabla Facturas de CEK). Solo lectura.
class FacturaHistorica {
  final int id;
  final String? generador;
  final String? cliente;
  final String? contrato;
  final int? idContrato;
  final int? annio;
  final int? mes;
  final double? consumo;
  final double? precio;
  final double? valor;
  final double? costo;
  final double? descuento;
  final String? textoOtrosCargos;
  final double? montoOtrosCargos;

  FacturaHistorica({
    required this.id,
    this.generador,
    this.cliente,
    this.contrato,
    this.idContrato,
    this.annio,
    this.mes,
    this.consumo,
    this.precio,
    this.valor,
    this.costo,
    this.descuento,
    this.textoOtrosCargos,
    this.montoOtrosCargos,
  });

  String get periodo =>
      '${annio ?? ''}-${(mes ?? 0).toString().padLeft(2, '0')}';

  factory FacturaHistorica.fromJson(Map<String, dynamic> j) => FacturaHistorica(
        id: j['id'] as int,
        generador: j['generador'] as String?,
        cliente: j['cliente'] as String?,
        contrato: j['contrato'] as String?,
        idContrato: j['id_contrato'] as int?,
        annio: j['annio'] as int?,
        mes: j['mes'] as int?,
        consumo: (j['consumo'] as num?)?.toDouble(),
        precio: (j['precio'] as num?)?.toDouble(),
        valor: (j['valor'] as num?)?.toDouble(),
        costo: (j['costo'] as num?)?.toDouble(),
        descuento: (j['descuento'] as num?)?.toDouble(),
        textoOtrosCargos: j['texto_otros_cargos'] as String?,
        montoOtrosCargos: (j['monto_otros_cargos'] as num?)?.toDouble(),
      );
}

class Reclamacion {
  final int id;
  final int idAgente;
  final int? idCliente;
  final String? codigo;
  final String? tipo;
  final String? descripcion;
  final String? periodo;
  final double? monto;
  final String estado;
  final String? fechaHecho;
  final String? fechaLimite;
  final String? fechaPresentacion;
  final String? evidencia;
  final String? creado;
  final String? actualizado;

  Reclamacion({
    required this.id,
    required this.idAgente,
    this.idCliente,
    this.codigo,
    this.tipo,
    this.descripcion,
    this.periodo,
    this.monto,
    required this.estado,
    this.fechaHecho,
    this.fechaLimite,
    this.fechaPresentacion,
    this.evidencia,
    this.creado,
    this.actualizado,
  });

  factory Reclamacion.fromJson(Map<String, dynamic> j) => Reclamacion(
        id: j['id'] as int,
        idAgente: j['id_agente'] as int,
        idCliente: j['id_cliente'] as int?,
        codigo: j['codigo'] as String?,
        tipo: j['tipo'] as String?,
        descripcion: j['descripcion'] as String?,
        periodo: j['periodo'] as String?,
        monto: (j['monto'] as num?)?.toDouble(),
        estado: j['estado'] as String? ?? 'identificada',
        fechaHecho: j['fecha_hecho'] as String?,
        fechaLimite: j['fecha_limite'] as String?,
        fechaPresentacion: j['fecha_presentacion'] as String?,
        evidencia: j['evidencia'] as String?,
        creado: j['creado'] as String?,
        actualizado: j['actualizado'] as String?,
      );
}

/// Movimiento de la bitácora (seguimiento) de una reclamación.
class Seguimiento {
  final int id;
  final int idReclamacion;
  final String? fecha;
  final String? estado;
  final String? nota;
  final String? usuario;

  Seguimiento({
    required this.id,
    required this.idReclamacion,
    this.fecha,
    this.estado,
    this.nota,
    this.usuario,
  });

  factory Seguimiento.fromJson(Map<String, dynamic> j) => Seguimiento(
        id: j['id'] as int,
        idReclamacion: j['id_reclamacion'] as int,
        fecha: j['fecha'] as String?,
        estado: j['estado'] as String?,
        nota: j['nota'] as String?,
        usuario: j['usuario'] as String?,
      );
}

class AjusteCND {
  final int id;
  final String periodo;
  final String? codigo;
  final String? nombre;
  final String? tipo;
  final String? clienteCodigo;
  final String? origen;
  final String? archivoLocal;
  final int? reporteId;

  AjusteCND({
    required this.id,
    required this.periodo,
    this.codigo,
    this.nombre,
    this.tipo,
    this.clienteCodigo,
    this.origen,
    this.archivoLocal,
    this.reporteId,
  });

  factory AjusteCND.fromJson(Map<String, dynamic> j) => AjusteCND(
        id: j['id'] as int,
        periodo: j['periodo'] as String? ?? '',
        codigo: j['codigo'] as String?,
        nombre: j['nombre'] as String?,
        tipo: j['tipo'] as String?,
        clienteCodigo: j['cliente_codigo'] as String?,
        origen: j['origen'] as String?,
        archivoLocal: j['archivo_local'] as String?,
        reporteId: j['reporte_id'] as int?,
      );
}

class FacturaDetalle {
  final int id;
  final int orden;
  final String? categoria;
  final String descripcion;
  final String? consumo;
  final double? cantidad;
  final String? unidad;
  final double? monto;
  final bool esTotal;

  FacturaDetalle({
    required this.id,
    required this.orden,
    this.categoria,
    required this.descripcion,
    this.consumo,
    this.cantidad,
    this.unidad,
    this.monto,
    required this.esTotal,
  });

  factory FacturaDetalle.fromJson(Map<String, dynamic> j) => FacturaDetalle(
        id: j['id'] as int? ?? 0,
        orden: j['orden'] as int? ?? 0,
        categoria: j['categoria'] as String?,
        descripcion: j['descripcion'] as String,
        consumo: j['consumo'] as String?,
        cantidad: (j['cantidad'] as num?)?.toDouble(),
        unidad: j['unidad'] as String?,
        monto: (j['monto'] as num?)?.toDouble(),
        esTotal: j['es_total'] as bool? ?? true,
      );
}

class Factura {
  final int id;
  final String numero;
  final int idAgente;
  final int idCliente;
  final String periodo;
  final String? tarifa;
  final double? precioKwh;
  final double? consumoMwh;
  final double subtotal;
  final double itbmsPct;
  final double itbms;
  final double total;
  final String estado;
  final String? clienteNombre;
  final String? agenteNombre;
  final String? graficas;
  final List<FacturaDetalle> detalles;

  Factura({
    required this.id,
    required this.numero,
    required this.idAgente,
    required this.idCliente,
    required this.periodo,
    this.tarifa,
    this.precioKwh,
    this.consumoMwh,
    required this.subtotal,
    required this.itbmsPct,
    required this.itbms,
    required this.total,
    required this.estado,
    this.clienteNombre,
    this.agenteNombre,
    this.graficas,
    this.detalles = const [],
  });

  factory Factura.fromJson(Map<String, dynamic> j) => Factura(
        id: j['id'] as int,
        numero: j['numero'] as String,
        idAgente: j['id_agente'] as int,
        idCliente: j['id_cliente'] as int,
        periodo: j['periodo'] as String,
        tarifa: j['tarifa'] as String?,
        precioKwh: (j['precio_kwh'] as num?)?.toDouble(),
        consumoMwh: (j['consumo_mwh'] as num?)?.toDouble(),
        subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
        itbmsPct: (j['itbms_pct'] as num?)?.toDouble() ?? 0,
        itbms: (j['itbms'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        estado: j['estado'] as String? ?? 'emitida',
        clienteNombre: j['cliente_nombre'] as String?,
        agenteNombre: j['agente_nombre'] as String?,
        graficas: j['graficas'] as String?,
        detalles: ((j['detalles'] as List?) ?? [])
            .map((e) => FacturaDetalle.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Punto de una serie para graficas (etiqueta + valor).
class PuntoSerie {
  final String etiqueta;
  final double valor;
  PuntoSerie(this.etiqueta, this.valor);
}

/// Grafica de consumo de la factura (diario / historico / costo).
class GraficoConsumo {
  final String tipo;
  final String titulo;
  final String subtitulo;
  final String cliente;
  final String codigo;
  final String periodo;
  final String rango;
  final String unidad;
  final String? unidadDerecha;
  final List<String> ejeX;
  final List<double?> valores;
  final List<double?>? linea;
  final String? nombreSerie;
  final String? nombreLinea;

  GraficoConsumo({
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    required this.cliente,
    required this.codigo,
    required this.periodo,
    required this.rango,
    required this.unidad,
    this.unidadDerecha,
    required this.ejeX,
    required this.valores,
    this.linea,
    this.nombreSerie,
    this.nombreLinea,
  });

  factory GraficoConsumo.fromJson(Map<String, dynamic> j) {
    final series = (j['series'] as List?) ?? const [];
    final s0 = series.isNotEmpty ? Map<String, dynamic>.from(series.first as Map) : <String, dynamic>{};
    final ln = j['linea'] is Map ? Map<String, dynamic>.from(j['linea'] as Map) : null;
    return GraficoConsumo(
      tipo: j['tipo'] as String? ?? 'diario',
      titulo: j['titulo'] as String? ?? 'Consumo',
      subtitulo: j['subtitulo'] as String? ?? '',
      cliente: j['cliente'] as String? ?? '',
      codigo: j['codigo'] as String? ?? '',
      periodo: j['periodo'] as String? ?? '',
      rango: j['rango'] as String? ?? '',
      unidad: j['unidad'] as String? ?? 'kWh',
      unidadDerecha: j['unidad_derecha'] as String?,
      ejeX: ((j['eje_x'] as List?) ?? const []).map((e) => '$e').toList(),
      valores: ((s0['valores'] as List?) ?? const [])
          .map((e) => e == null ? null : (e as num).toDouble())
          .toList(),
      nombreSerie: s0['nombre'] as String?,
      linea: ln == null
          ? null
          : ((ln['valores'] as List?) ?? const [])
              .map((e) => e == null ? null : (e as num).toDouble())
              .toList(),
      nombreLinea: ln?['nombre'] as String?,
    );
  }

  bool get tieneLinea => linea != null && linea!.any((v) => v != null);
}
