import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/graficas.dart';
import 'analisis_clientes_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _cargando = true;
  String? _error;
  String? _periodo; // null = último período con datos
  String? _desde;
  String? _hasta;
  String _modo = 'mes'; // mes | rango
  String _filtroRol = 'todos'; // todos | generadores | distribuidores

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({String? periodo}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      String q = '';
      if (_modo == 'rango' && _desde != null && _hasta != null) {
        var a = _desde!;
        var b = _hasta!;
        if (a.compareTo(b) > 0) {
          final t = a;
          a = b;
          b = t;
        }
        q = '?desde=$a&hasta=$b';
      } else if (_periodo != null && _periodo!.isNotEmpty) {
        q = '?periodo=$_periodo';
      }
      final data = await Api.I.get('/dashboard/resumen$q');
      final k = Map<String, dynamic>.from(data['kpis'] ?? {});
      setState(() {
        _data = Map<String, dynamic>.from(data);
        // Sembrar los selectores del rango con el último período con datos.
        _desde ??= '${k['desde'] ?? k['periodo'] ?? ''}';
        _hasta ??= '${k['hasta'] ?? k['periodo'] ?? ''}';
        if (_desde!.isEmpty) _desde = null;
        if (_hasta!.isEmpty) _hasta = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorVista(error: _error!, alReintentar: _cargar);
    }
    return RefreshIndicator(onRefresh: _cargar, child: _contenido());
  }

  Widget _contenido() {
    final kpis = Map<String, dynamic>.from(_data!['kpis'] ?? {});
    final periodos = ((_data!['periodos'] as List?) ?? []).map((e) => '$e').toList();
    final mercado = ((_data!['mercado'] as List?) ?? []);
    final facturacion = ((_data!['facturacion'] as List?) ?? []);
    final agentesCards = ((_data!['agentes_cards'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final serieMercado = mercado
        .map((m) => PuntoSerie(
            _periodoDisplay('${m['periodo'] ?? ''}'),
            (m['consumo'] as num?)?.toDouble() ?? 0))
        .toList();
    final serieFact = facturacion
        .map((f) => PuntoSerie(
            _periodoDisplay('${f['periodo'] ?? ''}'),
            (f['total'] as num?)?.toDouble() ?? 0))
        .toList();

    final periodoActual = '${kpis['periodo'] ?? ''}';
    final nPeriodos = (kpis['n_periodos'] as num?)?.toInt() ?? 1;
    final etiquetaRango = nPeriodos > 1
        ? '${_periodoDisplay('${kpis['desde'] ?? ''}')} – ${_periodoDisplay('${kpis['hasta'] ?? ''}')}'
        : _periodoDisplay(periodoActual);
    final serieGlobal = ((_data!['serie_global'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final serieDiariaGlobal = ((_data!['serie_diaria_global'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _filtroPeriodo(periodos, kpis),
        _banner(kpis),
        _kpis(kpis),
        _graficaGlobal(serieGlobal, serieDiariaGlobal, periodoActual),
        _seccionAgentes(agentesCards, periodoActual, etiquetaRango,
            esRango: nPeriodos > 1),
        _consumoPorAgente(agentesCards, periodoActual, etiquetaRango,
            esRango: nPeriodos > 1),
        if (serieMercado.isNotEmpty || serieFact.isNotEmpty)
          _filaGraficas(serieMercado, serieFact),
        _seccionMercado(mercado),
      ],
    );
  }

  /// Grafica global de puntos: el consumo de TODA la operación (suma de los
  /// agentes gestionados), no por agente.  Con varios meses muestra la evolucion
  /// mensual; con un solo mes, los puntos diarios reales.
  Widget _graficaGlobal(
    List<Map<String, dynamic>> serieGlobal,
    List<Map<String, dynamic>> serieDiaria,
    String periodoActual,
  ) {
    if (serieGlobal.length > 1) {
      final etiquetas = serieGlobal
          .map((e) => _periodoDisplay('${e['periodo'] ?? ''}'))
          .toList();
      final valores =
          serieGlobal.map((e) => (e['mwh'] as num?)?.toDouble() ?? 0.0).toList();
      return _seccion(
        'Consumo global (puntos)',
        'Evolución mensual de toda la operación · agentes gestionados (MWh)',
        GraficaLineas(
          series: [
            SerieLinea(
              nombre: 'Consumo global',
              valores: valores,
              color: const Color(0xFF0B6E4F),
              area: true,
            ),
          ],
          etiquetasX: etiquetas,
          altura: 270,
          etiquetaCada: 1,
          mostrarPuntos: true,
          formatoValor: (v) => '${fmtNumero(v, decimales: 1)} MWh',
        ),
      );
    }
    if (serieDiaria.isEmpty) return const SizedBox.shrink();
    final etiquetas = serieDiaria.map((e) {
      final f = '${e['fecha'] ?? ''}';
      final dia = f.contains('-') ? f.split('-').last : f;
      return '${int.tryParse(dia) ?? dia}';
    }).toList();
    final valores =
        serieDiaria.map((e) => (e['kwh'] as num?)?.toDouble() ?? 0.0).toList();
    return _seccion(
      'Consumo global diario (puntos)',
      'Total de los agentes gestionados por día en ${_periodoDisplay(periodoActual)} (kWh)',
      GraficaLineas(
        series: [
          SerieLinea(
            nombre: 'Consumo global',
            valores: valores,
            color: const Color(0xFF0B6E4F),
            area: true,
          ),
        ],
        etiquetasX: etiquetas,
        altura: 260,
        etiquetaCada: 1,
        mostrarPuntos: true,
        formatoValor: (v) => '${fmtNumero(v, decimales: 0)} kWh',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filtro de período / rango
  // ---------------------------------------------------------------------------
  /// Al entrar en "Comparar rango", propone los últimos 3 meses disponibles
  /// (incluyendo el período actual) para que el gráfico no salga con un solo
  /// punto cuando Desde y Hasta coinciden.
  String _desdeSugerido(List<String> periodos, String hasta) {
    final i = periodos.indexOf(hasta);
    if (i >= 0 && i + 2 < periodos.length) return periodos[i + 2];
    return periodos.isNotEmpty ? periodos.last : hasta;
  }

  Widget _filtroPeriodo(List<String> periodos, Map<String, dynamic> kpis) {
    final tema = Theme.of(context);
    final actual = _periodo ?? '${kpis['periodo'] ?? ''}';
    final n = (kpis['n_periodos'] as num?)?.toInt() ?? 1;
    final esRango = _modo == 'rango';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'mes',
                    label: Text('Un mes'),
                    icon: Icon(Icons.event_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'rango',
                    label: Text('Comparar rango'),
                    icon: Icon(Icons.date_range_outlined, size: 16),
                  ),
                ],
                selected: {_modo},
                onSelectionChanged: (s) {
                  setState(() {
                    _modo = s.first;
                    if (s.first == 'rango') {
                      _hasta = actual;
                      _desde = _desdeSugerido(periodos, actual);
                    }
                  });
                  _cargar();
                },
              ),
              if (!esRango)
                _selectorPeriodo(
                  etiqueta: 'Período',
                  valor: _periodo,
                  periodos: periodos,
                  hint: 'Último con datos (${_periodoDisplay(actual)})',
                  onChanged: (v) {
                    setState(() => _periodo = v);
                    _cargar();
                  },
                )
              else ...[
                _selectorPeriodo(
                  etiqueta: 'Desde',
                  valor: _desde ?? actual,
                  periodos: periodos,
                  onChanged: (v) {
                    setState(() => _desde = v);
                    _cargar();
                  },
                ),
                _selectorPeriodo(
                  etiqueta: 'Hasta',
                  valor: _hasta ?? actual,
                  periodos: periodos,
                  onChanged: (v) {
                    setState(() => _hasta = v);
                    _cargar();
                  },
                ),
                IconButton.filledTonal(
                  tooltip: 'Restablecer rango',
                  onPressed: () {
                    setState(() {
                      _hasta = actual;
                      _desde = _desdeSugerido(periodos, actual);
                    });
                    _cargar();
                  },
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
              ],
              if (!esRango && _periodo != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() => _periodo = null);
                    _cargar();
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Volver al último'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            esRango
                ? 'Comparando ${_periodoDisplay(_desde ?? actual)} → ${_periodoDisplay(_hasta ?? actual)}'
                    '${n > 1 ? ' · $n meses' : ''}. Los totales suman el rango y el costo es el promedio.'
                : 'Los totales, tarjetas y gráficas se recalculan para el mes elegido.',
            style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _selectorPeriodo({
    required String etiqueta,
    required String? valor,
    required List<String> periodos,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    final tema = Theme.of(context);
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: tema.textTheme.labelSmall
                  ?.copyWith(color: tema.colorScheme.outline)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tema.colorScheme.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: periodos.contains(valor) ? valor : null,
                isExpanded: true,
                icon: const Icon(Icons.expand_more, size: 18),
                hint: Text(hint ?? etiqueta,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                items: [
                  for (final p in periodos)
                    DropdownMenuItem<String>(
                      value: p,
                      child: Text(_periodoDisplay(p)),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Banner
  // ---------------------------------------------------------------------------
  Widget _banner(Map<String, dynamic> kpis) {
    final usuario = Sesion.I.usuario;
    final nombre = usuario?.etiqueta ?? 'usuario';
    final listos = kpis['agentes_listos'] ?? 0;
    final total = kpis['agentes_total'] ?? 14;
    final variacion = (kpis['variacion_consumo_pct'] as num?)?.toDouble();
    final n = (kpis['n_periodos'] as num?)?.toInt() ?? 1;
    final etiquetaPeriodo = n > 1
        ? '${_periodoDisplay('${kpis['desde'] ?? ''}')} – ${_periodoDisplay('${kpis['hasta'] ?? ''}')}'
        : _periodoDisplay('${kpis['periodo'] ?? ''}');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF084C34), Color(0xFF0B6E4F)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF084C34).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.bolt, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hola, $nombre',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Panel general de la operación · $etiquetaPeriodo',
                        style: const TextStyle(
                            color: Color(0xFFE6F4EC), fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
                ),
                child: Text('$listos / $total agentes listos',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _chip(Icons.event_outlined, n > 1 ? 'Rango' : 'Período',
                  etiquetaPeriodo),
              _chip(Icons.bolt_outlined, 'Consumo',
                  '${fmtNumero(kpis['consumo_gestionado_mwh'] ?? 0, decimales: 1)} MWh'),
              _chip(Icons.trending_up_outlined, 'Costo medio',
                  _fmtBkWh(kpis['costo_medio_bskwh'] ?? 0)),
              _chip(Icons.payments_outlined, 'Facturado',
                  fmtMoneda((kpis['facturado_periodo'] ?? 0).toDouble())),
              _chip(Icons.groups_outlined, 'Clientes',
                  '${kpis['clientes_gestionados'] ?? 0}'),
              if (variacion != null)
                _chip(
                  variacion >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  n > 1 ? 'vs rango anterior' : 'vs mes anterior',
                  '${variacion >= 0 ? '+' : ''}${variacion.toStringAsFixed(1)}%',
                  color: variacion >= 0
                      ? const Color(0xFF8CF0C0)
                      : const Color(0xFFFFC9C6),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icono, String etiqueta, String valor,
      {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: color, size: 16),
          const SizedBox(width: 8),
          Text('$etiqueta: ',
              style: TextStyle(
                  color: color.withValues(alpha: 0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(valor,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // KPIs
  // ---------------------------------------------------------------------------
  Widget _kpis(Map<String, dynamic> kpis) {
    final listos = kpis['agentes_listos'] ?? 0;
    final total = kpis['agentes_total'] ?? 14;
    final n = (kpis['n_periodos'] as num?)?.toInt() ?? 1;
    final items = <Widget>[
      TarjetaKpi(
        titulo: 'Consumo gestionado',
        valor: '${fmtNumero(kpis['consumo_gestionado_mwh'] ?? 0, decimales: 1)} MWh',
        icono: Icons.bolt_outlined,
        color: const Color(0xFFF0A020),
        pie: n > 1 ? 'suma del rango' : 'mediciones del período',
      ),
      TarjetaKpi(
        titulo: 'Costo medio',
        valor: _fmtBkWh(kpis['costo_medio_bskwh'] ?? 0),
        icono: Icons.trending_up_outlined,
        color: const Color(0xFF12B886),
        pie: n > 1 ? 'promedio del rango' : 'promedio CMS',
      ),
      TarjetaKpi(
        titulo: n > 1 ? 'Facturado en el rango' : 'Facturado en el período',
        valor: fmtMoneda((kpis['facturado_periodo'] ?? 0).toDouble()),
        icono: Icons.payments_outlined,
        color: const Color(0xFF7C4DFF),
        pie: 'facturas no anuladas',
      ),
      TarjetaKpi(
        titulo: 'Agentes listos',
        valor: '$listos / $total',
        icono: Icons.verified_outlined,
        color: listos == total ? const Color(0xFF12B886) : const Color(0xFFF0A020),
        pie: n > 1 ? 'último mes del rango' : 'con datos completos',
      ),
      TarjetaKpi(
        titulo: 'Clientes con medición',
        valor: '${kpis['clientes_gestionados'] ?? 0}',
        icono: Icons.people_alt_outlined,
        color: const Color(0xFF315C8A),
        pie: n > 1 ? 'en el rango' : 'en el período',
      ),
      TarjetaKpi(
        titulo: n > 1 ? 'Días con datos' : 'Avance del mes',
        valor: '${kpis['dias_con_datos'] ?? 0} / ${kpis['dias_mes'] ?? 0} días',
        icono: Icons.event_available_outlined,
        color: const Color(0xFF0B6E4F),
        pie: n > 1 ? 'días cargados del rango' : 'días con datos cargados',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(
        builder: (context, c) {
          final n = c.maxWidth >= 1200
              ? 6
              : (c.maxWidth >= 900
                  ? 3
                  : (c.maxWidth >= 600 ? 2 : 1));
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 112,
            ),
            itemBuilder: (_, i) => items[i],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tarjetas de agentes
  // ---------------------------------------------------------------------------
  Widget _seccionAgentes(
      List<Map<String, dynamic>> agentes, String periodo, String etiquetaRango,
      {bool esRango = false}) {
    if (agentes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(
            'Agentes gestionados (${agentes.length})',
            esRango
                ? 'Consumo sumado de $etiquetaRango por agente. Al abrir una tarjeta verás el detalle del último mes ($periodo).'
                : 'Consumo de $etiquetaRango por agente. Toca una tarjeta para abrir su análisis de clientes.',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final ancho = c.maxWidth;
              final n = ancho >= 1180
                  ? 5
                  : (ancho >= 920
                      ? 4
                      : (ancho >= 660 ? 3 : (ancho >= 440 ? 2 : 1)));
              final cardWidth = (ancho - (n - 1) * 12) / n;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in agentes)
                    SizedBox(
                      width: cardWidth,
                      height: 150,
                      child: _tarjetaAgente(a, periodo),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tarjetaAgente(Map<String, dynamic> a, String periodo) {
    final esGenerador = a['generador'] == true || a['generador'] == 1;
    final color = esGenerador ? const Color(0xFF0B6E4F) : const Color(0xFF315C8A);
    final consumo = (a['consumo'] as num?)?.toDouble() ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirAnalisisAgente(a, periodo),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      esGenerador ? Icons.solar_power : Icons.storefront_outlined,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['nombre'] ?? a['codigo'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text('${a['codigo'] ?? ''}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(esGenerador ? 'Generador' : 'Distribuidor',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                  const Spacer(),
                  Text('${a['n_clientes'] ?? 0} clientes',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.bolt_outlined,
                      size: 16,
                      color: consumo > 0
                          ? const Color(0xFFF0A020)
                          : Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    consumo > 0
                        ? '${fmtNumero(consumo, decimales: 2)} MWh'
                        : 'Sin consumo',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: consumo > 0
                            ? const Color(0xFF9A5B00)
                            : Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirAnalisisAgente(Map<String, dynamic> a, String periodo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AnalisisClientesScreen(
        idAgenteInicial: a['id'] as int?,
        periodoInicial: periodo.isEmpty ? null : periodo,
        comoRuta: true,
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // Consumo por agente (barras horizontales, datos reales)
  // ---------------------------------------------------------------------------
  Widget _consumoPorAgente(
      List<Map<String, dynamic>> agentes, String periodo, String etiquetaRango,
      {bool esRango = false}) {
    final filtrados = agentes.where((a) {
      final gen = a['generador'] == true || a['generador'] == 1;
      final dist = a['distribuidor'] == true || a['distribuidor'] == 1;
      if (_filtroRol == 'generadores') return gen;
      if (_filtroRol == 'distribuidores') return dist;
      return true;
    }).where((a) => ((a['consumo'] as num?) ?? 0) > 0).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _tituloSeccion(
                  'Consumo por agente gestionado',
                  esRango
                      ? 'Solo agentes del sistema · suma de $etiquetaRango'
                      : 'Solo los agentes del sistema (no códigos sueltos del CND) · $etiquetaRango',
                ),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'todos', label: Text('Todos')),
                    ButtonSegment(value: 'generadores', label: Text('Generadores')),
                    ButtonSegment(
                        value: 'distribuidores', label: Text('Distribuidores')),
                  ],
                  selected: {_filtroRol},
                  onSelectionChanged: (s) =>
                      setState(() => _filtroRol = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtrados.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                    child: Text('Sin consumo registrado para este filtro/período')),
              )
            else
              ..._filasBarras(filtrados, periodo),
          ],
        ),
      ),
    );
  }

  List<Widget> _filasBarras(
      List<Map<String, dynamic>> agentes, String periodo) {
    final maximo = agentes
        .map((a) => (a['consumo'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (x, y) => y > x ? y : x);
    final techo = maximo <= 0 ? 1.0 : maximo;
    final theme = Theme.of(context);
    return [
      for (final a in agentes)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _abrirAnalisisAgente(a, periodo),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['nombre'] ?? a['codigo']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(
                          '${a['codigo']} · ${(a['generador'] == true || a['generador'] == 1) ? 'Generador' : 'Distribuidor'}',
                          style: TextStyle(
                              fontSize: 10, color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final valor = (a['consumo'] as num?)?.toDouble() ?? 0;
                      return Stack(
                        children: [
                          Container(
                            height: 18,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Container(
                            height: 18,
                            width: (c.maxWidth * (valor / techo))
                                .clamp(3.0, c.maxWidth),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF0B6E4F),
                                Color(0xFF12B886),
                              ]),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text(
                    '${fmtNumero((a['consumo'] as num?) ?? 0, decimales: 2)} MWh',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 17, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Gráficas generales
  // ---------------------------------------------------------------------------
  Widget _filaGraficas(List<PuntoSerie> serieMercado, List<PuntoSerie> serieFact) {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho >= 1000) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _tarjetaGrafica(
                'Consumo del mercado eléctrico',
                'Demanda total por período (MWh)',
                GraficaBarras(
                    serie: serieMercado, color: const Color(0xFF315C8A)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _tarjetaGrafica(
                'Facturación por período',
                'Total facturado (B/.)',
                GraficaBarras(
                  serie: serieFact,
                  color: const Color(0xFFF0A020),
                  formatoValor: (v) => v >= 1000
                      ? '${(v / 1000).toStringAsFixed(0)}k'
                      : v.toStringAsFixed(0),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _seccion('Consumo del mercado eléctrico', 'Demanda total por período (MWh)',
            GraficaBarras(serie: serieMercado, color: const Color(0xFF315C8A))),
        _seccion(
            'Facturación por período',
            'Total facturado (B/.)',
            GraficaBarras(
              serie: serieFact,
              color: const Color(0xFFF0A020),
              formatoValor: (v) => v >= 1000
                  ? '${(v / 1000).toStringAsFixed(0)}k'
                  : v.toStringAsFixed(0),
            )),
      ],
    );
  }

  Widget _tarjetaGrafica(String titulo, String subtitulo, Widget hijo) {
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(titulo, subtitulo),
          const SizedBox(height: 16),
          hijo,
        ],
      ),
    );
  }

  Widget _seccion(String titulo, String subtitulo, Widget hijo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: _tarjetaGrafica(titulo, subtitulo, hijo),
    );
  }

  Widget _tituloSeccion(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitulo,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mercado (tabla)
  // ---------------------------------------------------------------------------
  Widget _seccionMercado(List mercado) {
    if (mercado.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Tarjeta(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tituloSeccion('Mercado eléctrico (CND)',
                  'Consumo y liquidación publicados por período.'),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Sin datos de mercado cargados')),
              ),
            ],
          ),
        ),
      );
    }

    final ultimo = mercado.last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tituloSeccion(
              'Mercado eléctrico (CND)',
              'Consumo y liquidación que publica el CND. El "mercado ocasional" '
                  'es la energía comprada/vendida fuera de contrato.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _datoMercado('Último período', _periodoDisplay('${ultimo['periodo'] ?? ''}'),
                    Icons.event_outlined, const Color(0xFF315C8A)),
                _datoMercado(
                    'Consumo',
                    '${fmtNumero((ultimo['consumo'] as num?) ?? 0, decimales: 1)} MWh',
                    Icons.bolt_outlined,
                    const Color(0xFFF0A020)),
                _datoMercado(
                    'Energía asignada',
                    '${fmtNumero((ultimo['energia_asignada'] as num?) ?? 0, decimales: 1)} MWh',
                    Icons.assignment_turned_in_outlined,
                    const Color(0xFF12B886)),
                _datoMercado('Mercado ocasional',
                    fmtMoneda((ultimo['ocasional_monto'] as num?) ?? 0),
                    Icons.payments_outlined, const Color(0xFF7C4DFF)),
              ],
            ),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.7),
                ),
                columnSpacing: 28,
                horizontalMargin: 12,
                columns: const [
                  DataColumn(label: Text('Período')),
                  DataColumn(label: Text('Versión'), numeric: true),
                  DataColumn(label: Text('Filas'), numeric: true),
                  DataColumn(label: Text('Consumo (MWh)'), numeric: true),
                  DataColumn(label: Text('Energía asignada (MWh)'), numeric: true),
                  DataColumn(label: Text('Mercado ocasional'), numeric: true),
                ],
                rows: [
                  for (final m in mercado)
                    DataRow(cells: [
                      DataCell(Text(_periodoDisplay('${m['periodo'] ?? ''}'),
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text('v${m['version_num'] ?? 1}')),
                      DataCell(Text(fmtNumero((m['filas'] as num?) ?? 0))),
                      DataCell(Text(
                          fmtNumero((m['consumo'] as num?) ?? 0, decimales: 1))),
                      DataCell(Text(fmtNumero(
                          (m['energia_asignada'] as num?) ?? 0,
                          decimales: 1))),
                      DataCell(Text(
                          fmtMoneda((m['ocasional_monto'] as num?) ?? 0))),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datoMercado(String etiqueta, String valor, IconData icono, Color color) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor,
                      maxLines: 1,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------
  String _fmtBkWh(num v) {
    final s = v
        .toStringAsFixed(6)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return '$s B/./kWh';
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
