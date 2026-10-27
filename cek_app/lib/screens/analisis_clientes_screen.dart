import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/abrir_url.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/graficas.dart';

/// Análisis de consumo por agente y mes.
///
/// Se elige un agente (o "Todos") y un período; la pantalla muestra el consumo
/// de TODOS sus clientes, con proyección del mes, variación contra el mes
/// anterior, contrato/tarifa, factura descargable y detalle histórico.
///
/// La fuente es la tabla `mediciones` (la misma de la columna "Consumos" de la
/// factura) y `mediciones_diarias` para la proyección. No se inventan valores.
class AnalisisClientesScreen extends StatefulWidget {
  final int? idAgenteInicial;
  final String? periodoInicial;

  /// `true` cuando se abre como ruta independiente (desde el dashboard, un
  /// agente o la ficha de un cliente): agrega Scaffold/AppBar para que respete
  /// el tema (incluido el modo oscuro) y tenga botón de regreso.
  final bool comoRuta;

  const AnalisisClientesScreen({
    super.key,
    this.idAgenteInicial,
    this.periodoInicial,
    this.comoRuta = false,
  });

  @override
  State<AnalisisClientesScreen> createState() => _AnalisisClientesScreenState();
}

class _AnalisisClientesScreenState extends State<AnalisisClientesScreen> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  List<Agente> _agentes = [];
  int? _idAgente;
  int? _idCliente;
  // Clientes del agente seleccionado (o todos).  Se conservan aunque se elija
  // un cliente concreto, para no perder las opciones del selector.
  List<Map<String, dynamic>> _clientesOpciones = [];
  late int _anio;
  late int _mes;
  Map<String, dynamic>? _data;
  bool _cargando = true;
  String? _error;
  final _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _idAgente = widget.idAgenteInicial;
    final p = widget.periodoInicial;
    if (p != null && p.length >= 6) {
      _anio = int.tryParse(p.substring(0, 4)) ?? DateTime.now().year;
      _mes = int.tryParse(p.substring(4, 6)) ?? DateTime.now().month;
    } else {
      final hoy = DateTime.now();
      _anio = hoy.year;
      _mes = hoy.month;
    }
    _iniciar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  String get _periodo => '$_anio${_mes.toString().padLeft(2, '0')}';

  bool get _restringido => !Sesion.I.puedeEditar;

  bool get _soloCliente => _idCliente != null;

  /// URL del análisis respetando la jerarquía: todos -> agente -> cliente.
  String _query({bool sinPeriodo = false}) {
    final b = StringBuffer('/analisis/clientes?periodo=');
    if (!sinPeriodo) b.write(_periodo);
    if (_idAgente != null) b.write('&id_agente=$_idAgente');
    if (_idCliente != null) b.write('&id_cliente=$_idCliente');
    return b.toString();
  }

  /// Guarda las opciones del selector de clientes (solo cuando no hay cliente
  /// concreto, porque en ese caso el backend devuelve únicamente ese cliente).
  void _guardarOpciones(Map<String, dynamic> d) {
    if (_idCliente != null) return;
    _clientesOpciones = ((d['clientes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _iniciar() async {
    if (!_restringido) {
      try {
        final a = await Api.I.get('/agentes') as List;
        if (mounted) {
          setState(() => _agentes = a
              .map((e) => Agente.fromJson(Map<String, dynamic>.from(e)))
              .toList());
        }
      } catch (_) {
        // Si fallan los agentes igual se puede analizar "Todos".
      }
    }

    // Sin período explícito, dejar que el backend elija el último mes con
    // consumo real y sincronizar los selectores con ese período.
    if (widget.periodoInicial == null) {
      setState(() {
        _cargando = true;
        _error = null;
      });
      try {
        final r = await Api.I.get(_query(sinPeriodo: true));
        final d = Map<String, dynamic>.from(r as Map);
        final p = '${d['periodo'] ?? ''}';
        if (mounted) {
          setState(() {
            _data = d;
            _guardarOpciones(d);
            if (p.length >= 6) {
              _anio = int.tryParse(p.substring(0, 4)) ?? _anio;
              _mes = int.tryParse(p.substring(4, 6)) ?? _mes;
            }
            _cargando = false;
          });
        }
        return;
      } catch (_) {
        // Si falla, se intenta el mes calendario como respaldo.
      }
    }
    await _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await Api.I.get(_query());
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(r);
          _guardarOpciones(_data!);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _clientesFiltrados {
    final todos = ((_data?['clientes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final q = _busqueda.text.trim().toLowerCase();
    if (q.isEmpty) return todos;
    return todos.where((c) {
      final texto = '${c['nombre'] ?? ''} ${c['codigo'] ?? ''} '
              '${c['agente_nombre'] ?? ''} ${c['agente_codigo'] ?? ''} '
              '${c['contrato'] ?? ''}'
          .toLowerCase();
      return texto.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final contenido = Column(
      children: [
        EncabezadoSeccion(
          titulo: _restringido ? 'Mi consumo' : 'Análisis de clientes',
          subtitulo: d == null
              ? 'Consumo mensual, proyección y facturas por cliente'
              : '${d['n_clientes']} clientes · '
                  '${fmtNumero((d['total_mwh'] as num?) ?? 0, decimales: 2)} MWh · '
                  '${d['n_facturas']} facturas (${fmtMoneda((d['total_facturado'] as num?) ?? 0)})',
          icono: Icons.query_stats_outlined,
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        _filtros(),
        Expanded(child: _cuerpo()),
      ],
    );
    if (!widget.comoRuta) return contenido;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(_restringido ? 'Mi consumo' : 'Análisis de clientes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: contenido,
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!_restringido)
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int?>(
                initialValue: _idAgente,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Agente',
                    prefixIcon: Icon(Icons.groups_outlined),
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Todos los agentes')),
                  for (final a in _agentes)
                    DropdownMenuItem<int?>(
                        value: a.id,
                        child: Text('${a.codigo} · ${a.etiqueta}',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() {
                    _idAgente = v;
                    _idCliente = null;
                  });
                  _cargar();
                },
              ),
            ),
          SizedBox(
            width: 280,
            child: Builder(builder: (_) {
              final hayCli = _clientesOpciones.any(
                  (c) => (c['id_cliente'] as num?)?.toInt() == _idCliente);
              return DropdownButtonFormField<int?>(
                key: ValueKey(
                    'cli-$_idAgente-$_idCliente-${_clientesOpciones.length}'),
                initialValue: (_idCliente != null && hayCli) ? _idCliente : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Cliente',
                    prefixIcon: Icon(Icons.people_alt_outlined),
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Todos los clientes')),
                  for (final c in _clientesOpciones)
                    if ((c['id_cliente'] as num?)?.toInt() != null)
                      DropdownMenuItem<int?>(
                          value: (c['id_cliente'] as num).toInt(),
                          child: Text('${c['nombre'] ?? c['codigo']}',
                              overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _idCliente = v);
                  _cargar();
                },
              );
            }),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int>(
              initialValue: _mes,
              decoration: const InputDecoration(
                  labelText: 'Mes',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
              ],
              onChanged: (v) {
                setState(() => _mes = v ?? _mes);
                _cargar();
              },
            ),
          ),
          SizedBox(
            width: 108,
            child: DropdownButtonFormField<int>(
              initialValue: _anio,
              decoration: const InputDecoration(
                  labelText: 'Año',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                for (var a = DateTime.now().year - 3;
                    a <= DateTime.now().year + 1;
                    a++)
                  DropdownMenuItem(value: a, child: Text('$a')),
              ],
              onChanged: (v) {
                setState(() => _anio = v ?? _anio);
                _cargar();
              },
            ),
          ),
          SizedBox(
            width: 250,
            child: TextField(
              controller: _busqueda,
              decoration: InputDecoration(
                labelText: 'Buscar cliente',
                hintText: 'Nombre, código, agente o contrato',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _busqueda.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analisisAgente(
      Map<String, dynamic> d, List<Map<String, dynamic>> clientes) {
    final total = (d['total_mwh'] as num?)?.toDouble() ?? 0;
    final proy = (d['total_proyectado_mwh'] as num?)?.toDouble() ?? 0;
    final facturado = (d['total_facturado'] as num?)?.toDouble() ?? 0;
    final nClientes = (d['n_clientes'] as num?)?.toInt() ?? 0;
    final conFactura = clientes.where((c) => c['factura'] != null).length;
    final sinConsumo = clientes
        .where((c) => ((c['consumo_mwh'] as num?) ?? 0) <= 0)
        .length;
    final variaciones = clientes
        .map((c) => (c['variacion_pct'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final varProm = variaciones.isEmpty
        ? null
        : variaciones.reduce((a, b) => a + b) / variaciones.length;

    final orden = [...clientes]..sort((a, b) =>
        ((b['consumo_mwh'] as num?) ?? 0)
            .compareTo((a['consumo_mwh'] as num?) ?? 0));
    final top5 = orden
        .take(5)
        .fold<double>(0, (s, c) => s + ((c['consumo_mwh'] as num?) ?? 0));
    final concentracion = total > 0 ? top5 / total * 100 : 0.0;
    final avance = proy > 0 ? total / proy * 100 : 0.0;

    String titulo;
    if (_soloCliente && clientes.isNotEmpty) {
      titulo = '${clientes.first['nombre'] ?? clientes.first['codigo']} · '
          '${_periodoDisplay(_periodo)}';
    } else {
      String? nombreAgente;
      if (_idAgente != null) {
        for (final a in _agentes) {
          if (a.id == _idAgente) {
            nombreAgente = a.etiqueta;
            break;
          }
        }
      }
      titulo =
          '${nombreAgente ?? 'Todos los agentes'} · ${_periodoDisplay(_periodo)}';
    }

    final kpis = <Widget>[
      TarjetaKpi(
        titulo: 'Consumo del período',
        valor: '${fmtNumero(total, decimales: 2)} MWh',
        icono: Icons.bolt_outlined,
        color: const Color(0xFFF0A020),
        pie: _periodoDisplay(_periodo),
      ),
      TarjetaKpi(
        titulo: 'Proyección de cierre',
        valor: '${fmtNumero(proy, decimales: 2)} MWh',
        icono: Icons.trending_up_outlined,
        color: const Color(0xFF12B886),
        pie: 'según días con datos',
      ),
      TarjetaKpi(
        titulo: 'Facturado',
        valor: fmtMoneda(facturado),
        icono: Icons.payments_outlined,
        color: const Color(0xFF7C4DFF),
        pie: '$conFactura de $nClientes con factura',
      ),
      if (!_soloCliente)
        TarjetaKpi(
          titulo: 'Clientes',
          valor: '$nClientes',
          icono: Icons.people_alt_outlined,
          color: const Color(0xFF315C8A),
          pie: '$sinConsumo sin consumo',
        ),
      TarjetaKpi(
        titulo: _soloCliente ? 'Variación' : 'Variación promedio',
        valor: varProm == null
            ? '—'
            : '${varProm >= 0 ? '+' : ''}${varProm.toStringAsFixed(1)}%',
        icono: varProm != null && varProm < 0
            ? Icons.arrow_downward
            : Icons.arrow_upward,
        color: varProm != null && varProm < 0
            ? const Color(0xFFD84A43)
            : const Color(0xFF0B6E4F),
        pie: _soloCliente ? 'vs mes anterior' : 'vs mes anterior (promedio)',
      ),
      if (!_soloCliente)
        TarjetaKpi(
          titulo: 'Concentración top 5',
          valor: '${concentracion.toStringAsFixed(1)}%',
          icono: Icons.pie_chart_outline,
          color: const Color(0xFF39C5CF),
          pie: '${fmtNumero(top5, decimales: 1)} de '
              '${fmtNumero(total, decimales: 1)} MWh',
        ),
      if (proy > 0)
        TarjetaKpi(
          titulo: 'Avance vs proyección',
          valor: '${avance.toStringAsFixed(1)}%',
          icono: Icons.speed_outlined,
          color: const Color(0xFFD97706),
          pie: 'consumo actual / cierre estimado',
        ),
      if (!_soloCliente)
        TarjetaKpi(
          titulo: 'Promedio por cliente',
          valor: nClientes == 0
              ? '—'
              : '${fmtNumero(total / nClientes, decimales: 2)} MWh',
          icono: Icons.analytics_outlined,
          color: const Color(0xFF7048E8),
          pie: 'consumo del período',
        ),
    ];

    // Serie histórica agregada de todos los clientes del agente.
    final porPeriodo = <String, double>{};
    final etiquetaPorPeriodo = <String, String>{};
    for (final c in clientes) {
      for (final raw in ((c['serie'] as List?) ?? [])) {
        final s = Map<String, dynamic>.from(raw as Map);
        final p = '${s['periodo'] ?? ''}';
        if (p.isEmpty) continue;
        porPeriodo[p] =
            (porPeriodo[p] ?? 0) + ((s['kwh'] as num?)?.toDouble() ?? 0);
        etiquetaPorPeriodo[p] = '${s['etiqueta'] ?? p}';
      }
    }
    final periodos = porPeriodo.keys.toList()..sort();
    final ultimos = periodos.length > 12
        ? periodos.sublist(periodos.length - 12)
        : periodos;
    final etiquetas = ultimos.map((p) => etiquetaPorPeriodo[p] ?? p).toList();
    final valores = ultimos.map((p) => porPeriodo[p] ?? 0).toList();

    final topClientes = orden
        .take(10)
        .map((c) => (
              '${c['nombre'] ?? c['codigo']}',
              ((c['consumo_mwh'] as num?) ?? 0).toDouble(),
            ))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            _soloCliente
                ? 'Detalle del cliente seleccionado. '
                    '${sinConsumo > 0 ? 'Sin consumo medido en el período.' : 'Con consumo medido.'}'
                : 'El top 5 concentra ${concentracion.toStringAsFixed(1)}% del consumo. '
                    '$sinConsumo cliente(s) sin consumo y ${nClientes - conFactura} sin factura.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final n = c.maxWidth >= 1200
                  ? 4
                  : (c.maxWidth >= 860
                      ? 3
                      : (c.maxWidth >= 520 ? 2 : 1));
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kpis.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: n,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 112,
                ),
                itemBuilder: (_, i) => kpis[i],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final graficaClientes = Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _soloCliente
                            ? 'Consumo del cliente'
                            : 'Consumo por cliente (top 10)',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('MWh del período seleccionado',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.outline)),
                    const SizedBox(height: 10),
                    BarrasHorizontales(
                      items: topClientes,
                      color: const Color(0xFF0B6E4F),
                      formato: (v) => v.toStringAsFixed(2),
                    ),
                  ],
                ),
              );
              final graficaHistorica = Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Evolución mensual',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Consumo total del agente (kWh)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.outline)),
                    const SizedBox(height: 10),
                    if (valores.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Sin historial de consumo')),
                      )
                    else
                      GraficaLineas(
                        series: [
                          SerieLinea(
                            nombre: 'Consumo',
                            valores: valores,
                            color: const Color(0xFF315C8A),
                            area: true,
                          ),
                        ],
                        etiquetasX: etiquetas,
                        altura: 210,
                        etiquetaCada: 2,
                        mostrarPuntos: true,
                        formatoValor: (v) =>
                            '${fmtNumero(v, decimales: 0)} kWh',
                      ),
                  ],
                ),
              );
              if (c.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: graficaClientes),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: graficaHistorica),
                  ],
                );
              }
              return Column(
                children: [
                  graficaClientes,
                  const SizedBox(height: 12),
                  graficaHistorica,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final todos = ((d['clientes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final clientes = _clientesFiltrados;
    final analisis = _analisisAgente(d, todos);

    if (clientes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            analisis,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: EstadoVacio(
                mensaje: _busqueda.text.trim().isEmpty
                    ? 'Sin clientes para este agente/período'
                    : 'Ningún cliente coincide con la búsqueda',
                icono: Icons.people_outline,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: clientes.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return analisis;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _tarjetaCliente(clientes[i - 1], i),
          );
        },
      ),
    );
  }

  Widget _tarjetaCliente(Map<String, dynamic> c, int n) {
    final serie = ((c['serie'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final visibles = serie.length > 8 ? serie.sublist(serie.length - 8) : serie;
    final valores =
        visibles.map((s) => (s['kwh'] as num?)?.toDouble() ?? 0.0).toList();
    final etiquetas = visibles.map((s) => '${s['etiqueta'] ?? ''}').toList();
    final fac = c['factura'] is Map
        ? Map<String, dynamic>.from(c['factura'] as Map)
        : null;
    final consumo = (c['consumo_mwh'] as num?)?.toDouble() ?? 0;
    final proy = (c['proyeccion_mwh'] as num?)?.toDouble();
    final variacion = (c['variacion_pct'] as num?)?.toDouble();
    final agente = c['agente_nombre'] ?? c['agente_codigo'];
    final contrato = c['contrato'];
    final tarifa = c['tarifa'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _verCliente(c),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      child: Text('$n', style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['nombre'] ?? c['codigo']}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            '${c['codigo']} · ${fmtNumero(consumo, decimales: 3)} MWh'
                            '${agente != null ? ' · $agente' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    if (fac != null)
                      _chipFactura(
                          '${fac['numero']} · ${fmtMoneda((fac['total'] as num?) ?? 0)}',
                          const Color(0xFF12B886))
                    else
                      _chipFactura('sin factura', const Color(0xFFF0A020)),
                  ],
                ),
                if (contrato != null || tarifa != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (contrato != null)
                        _datoChip(Icons.description_outlined, 'Contrato $contrato'),
                      if (tarifa != null)
                        _datoChip(Icons.sell_outlined, 'Tarifa $tarifa'),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _datoChip(Icons.bolt_outlined,
                        '${fmtNumero(consumo, decimales: 2)} MWh'),
                    if (proy != null && proy > 0)
                      _datoChip(Icons.trending_up_outlined,
                          'Proyección ${fmtNumero(proy, decimales: 2)} MWh',
                          color: const Color(0xFF12B886)),
                    if (variacion != null)
                      _datoChip(
                        variacion >= 0
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        '${variacion >= 0 ? '+' : ''}${variacion.toStringAsFixed(1)}% vs mes anterior',
                        color: variacion >= 0
                            ? const Color(0xFF0B6E4F)
                            : const Color(0xFFD84A43),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (valores.isNotEmpty)
                  GraficaBarrasFl(
                    valores: valores,
                    etiquetasX: etiquetas,
                    altura: 140,
                    etiquetaCada: 1,
                    color: const Color(0xFF0B6E4F),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sin consumo registrado'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    if (fac != null)
                      OutlinedButton.icon(
                        onPressed: () =>
                            _abrirFactura((fac['id'] as num).toInt()),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Descargar factura'),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _verCliente(c),
                      icon: const Icon(Icons.insights_outlined, size: 18),
                      label: const Text('Ver análisis'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipFactura(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _datoChip(IconData icono, String texto, {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: c),
          const SizedBox(width: 5),
          Text(texto, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }

  void _abrirFactura(int id) {
    abrirEnNavegador('${AppConfig.apiBase}/facturas/$id/html');
  }

  void _verCliente(Map<String, dynamic> c) {
    final serie = ((c['serie'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final valores = serie.map((s) => (s['kwh'] as num?)?.toDouble() ?? 0.0).toList();
    final etiquetas = serie.map((s) => '${s['etiqueta'] ?? ''}').toList();
    final facs = ((c['facturas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final proy = (c['proyeccion_mwh'] as num?)?.toDouble();
    final contrato = c['contrato'];
    final tarifa = c['tarifa'];
    final agente = c['agente_nombre'] ?? c['agente_codigo'];

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['nombre'] ?? c['codigo']}',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                              '${c['codigo']} · período ${_periodoDisplay(_periodo)} · '
                              '${fmtNumero((c['consumo_mwh'] as num?) ?? 0, decimales: 3)} MWh'
                              '${agente != null ? ' · $agente' : ''}',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color:
                                          Theme.of(ctx).colorScheme.outline)),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (proy != null && proy > 0)
                          _datoChip(Icons.trending_up_outlined,
                              'Proyección de cierre: ${fmtNumero(proy, decimales: 3)} MWh',
                              color: const Color(0xFF12B886)),
                        if (contrato != null)
                          _datoChip(Icons.description_outlined,
                              'Contrato: $contrato'),
                        if (tarifa != null)
                          _datoChip(Icons.sell_outlined, 'Tarifa: $tarifa'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('Historial de consumo (kWh)',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    if (valores.isNotEmpty)
                      GraficaBarrasFl(
                        valores: valores,
                        etiquetasX: etiquetas,
                        altura: 260,
                        etiquetaCada: 1,
                        color: const Color(0xFF0B6E4F),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Sin consumo registrado'),
                      ),
                    const SizedBox(height: 18),
                    Text('Facturas emitidas',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (facs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Este cliente no tiene facturas emitidas'),
                      )
                    else
                      for (final f in facs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text('${f['numero']} · ${f['periodo']}'),
                          subtitle: Text(
                              '${fmtMoneda((f['total'] as num?) ?? 0)} · ${f['estado']}'),
                          trailing: IconButton(
                            tooltip: 'Descargar / imprimir',
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            onPressed: () =>
                                _abrirFactura((f['id'] as num).toInt()),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodoDisplay(String p) {
    if (p.isEmpty) return '—';
    const meses = [
      '',
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    try {
      return '${meses[int.parse(p.substring(4, 6))]} ${p.substring(0, 4)}';
    } catch (_) {
      return p;
    }
  }
}
