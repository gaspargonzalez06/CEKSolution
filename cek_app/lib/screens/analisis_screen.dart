import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../widgets/comunes.dart';
import '../widgets/graficas.dart';

List<double?> _nums(dynamic l) {
  if (l is! List) return const [];
  return l.map((e) => (e as num?)?.toDouble()).toList();
}

/// Pantalla de analisis del mercado (portada del dashboard Python de CND).
class AnalisisScreen extends StatefulWidget {
  const AnalisisScreen({super.key});

  @override
  State<AnalisisScreen> createState() => _AnalisisScreenState();
}

class _AnalisisScreenState extends State<AnalisisScreen> {
  Map<String, dynamic>? _data;
  bool _cargando = true;
  String? _error;
  String _vista = 'ambos'; // ambos | curso | cerrado
  String _filtroVersion = 'todas'; // todas | parcial | final
  String? _desdeVersion;
  String? _hastaVersion;
  // Filtros del análisis (se envían al backend).
  String? _periodoSel;
  String? _agenteSel;
  int? _versionSel;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = <String>[];
      if (_periodoSel != null) params.add('periodo=$_periodoSel');
      if (_agenteSel != null) {
        params.add('agente=${Uri.encodeQueryComponent(_agenteSel!)}');
      }
      if (_versionSel != null) params.add('version=$_versionSel');
      final url =
          params.isEmpty ? '/analisis/sustentos' : '/analisis/sustentos?${params.join('&')}';
      final data = await Api.I.get(url);
      setState(() => _data = Map<String, dynamic>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    return RefreshIndicator(onRefresh: _cargar, child: _contenido());
  }

  Widget _contenido() {
    final d = _data!;
    final k = (d['kpis'] as Map).cast<String, dynamic>();
    final labelsCurso = ((d['labels_curso'] as List?) ?? []).map((e) => '$e').toList();
    final labelsCerr = ((d['labels_cerrado'] as List?) ?? []).map((e) => '$e').toList();
    final labelsHora = List.generate(24, (i) => '${i + 1}');

    final acum = (d['acum_serie'] as Map?) ?? {};
    final seriesAcum = <SerieLinea>[];
    var idx = 0;
    for (final e in acum.entries) {
      seriesAcum.add(SerieLinea(
        nombre: 'v${e.key}',
        valores: _nums(e.value),
        color: coloresSerie[idx % coloresSerie.length],
      ));
      idx++;
    }

    final ajusteMedidas = (d['ajuste_medidas'] as List?) ?? [];
    final medValores = ajusteMedidas.map((m) => (m['pct'] as num?)?.toDouble()).toList();
    final medColores = medValores
        .map((v) => (v ?? 0) >= 0 ? const Color(0xFF12B886) : const Color(0xFFD84A43))
        .toList();
    final medEtiquetas = ajusteMedidas
        .map((m) => _corto('${m['medida']}'))
        .toList();

    final top = ((d['top'] as List?) ?? [])
        .map((t) => ('${t['agente']}', (t['consumo'] as num?)?.toDouble() ?? 0))
        .toList();

    final versiones = (d['versiones'] as List?) ?? [];
    final agenteSerie = ((d['agente_serie'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Indicadores calculados solo con datos reales del mes en curso.
    final cursoVal = _nums(d['curso']).whereType<double>().toList();
    final diasCurso = cursoVal.length;
    final totalCur = cursoVal.fold<double>(0, (a, b) => a + b);
    final promCur = diasCurso > 0 ? totalCur / diasCurso : 0.0;
    final maxCur = cursoVal.isEmpty
        ? 0.0
        : cursoVal.reduce((a, b) => a > b ? a : b);
    final minCur = cursoVal.isEmpty
        ? 0.0
        : cursoVal.reduce((a, b) => a < b ? a : b);
    final difs = cursoVal.map((v) => v - promCur).toList();
    final varianza = difs.isEmpty
        ? 0.0
        : difs.map((v) => v * v).reduce((a, b) => a + b) / difs.length;
    final desv = varianza <= 0 ? 0.0 : math.sqrt(varianza);
    final volatilidad = promCur > 0 ? desv / promCur * 100 : 0.0;
    final diaMax = cursoVal.isEmpty
        ? 0
        : cursoVal.indexOf(maxCur) + 1;
    final topTotal = top.fold<double>(0, (a, b) => a + b.$2);
    final top5 = top.take(5).fold<double>(0, (a, b) => a + b.$2);
    final concentracion = topTotal > 0 ? top5 / topTotal * 100 : 0.0;

    final kpis = <Widget>[
      TarjetaKpi(
        titulo: 'Mes en curso · días',
        valor: '${k['dias_curso']} / ${d['dias_mes_curso']}',
        icono: Icons.calendar_today_outlined,
        color: const Color(0xFF315C8A),
        pie: 'progreso del mes',
      ),
      TarjetaKpi(
        titulo: 'Consumo acumulado',
        valor: '${fmtNumero((k['total_curso'] as num?) ?? 0, decimales: 0)} MWh',
        icono: Icons.bolt_outlined,
        color: const Color(0xFF0B6E4F),
        pie: 'promedio ${fmtNumero((k['prom_curso'] as num?) ?? 0, decimales: 0)} / día',
      ),
      TarjetaKpi(
        titulo: 'Proyección de cierre',
        valor: '${fmtNumero((k['proy_curso'] as num?) ?? 0, decimales: 0)} MWh',
        icono: Icons.trending_up_outlined,
        color: const Color(0xFFF0A020),
        pie: 'lineal según avance actual',
      ),
      TarjetaKpi(
        titulo: 'Mes cerrado · total',
        valor: '${fmtNumero((k['total_cerr'] as num?) ?? 0, decimales: 0)} MWh',
        icono: Icons.event_available_outlined,
        color: const Color(0xFF7C4DFF),
        pie: 'DTE Sustentos final',
      ),
      TarjetaKpi(
        titulo: 'Ajuste final del mes',
        valor: '+${fmtNumero((k['ajuste'] as num?) ?? 0, decimales: 0)}',
        icono: Icons.tune_outlined,
        color: const Color(0xFF12B886),
        pie: '+${(k['ajuste_pct'] ?? 0)}% vs último parcial',
      ),
      TarjetaKpi(
        titulo: 'BRILLOSOL · monto acum.',
        valor: fmtNumero((k['bri_total'] as num?) ?? 0, decimales: 0),
        icono: Icons.solar_power_outlined,
        color: const Color(0xFFD84A43),
        pie: 'proyección ${fmtNumero((k['bri_proy'] as num?) ?? 0, decimales: 0)}',
      ),
      TarjetaKpi(
        titulo: 'BRILLOSOL · mes cerrado',
        valor: fmtNumero((k['bri_cerr'] as num?) ?? 0, decimales: 0),
        icono: Icons.solar_power_outlined,
        color: const Color(0xFF39C5CF),
        pie: 'monto ocasional final',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        EncabezadoSeccion(
          titulo: 'Análisis de sustentos',
          subtitulo:
              'Preliminar vs DTE Sustentos · generado ${d['generado'] ?? ''} · mes ${_periodo(d['mes_curso'])}',
          icono: Icons.insights_outlined,
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        _filtrosVista(),
        _kpiGrid(kpis),
        _indicadoresCurso(
          dias: diasCurso,
          total: totalCur,
          promedio: promCur,
          maximo: maxCur,
          minimo: minCur,
          diaMax: diaMax,
          volatilidad: volatilidad,
          concentracion: concentracion,
          top5: top5,
          topTotal: topTotal,
        ),
        const SizedBox(height: 8),
        if (_vista != 'cerrado')
          _seccion(
            'Evolución diaria del sistema',
            'Mes en curso (barras) + proyección de cierre (barras tenues) vs mes cerrado (línea)',
            GraficaEvolucion(
              real: _nums(d['curso']),
              proyectado: _nums(d['proy_serie']),
              cerrado: _nums(d['cerr_total']),
              etiquetasX: labelsCurso,
              altura: 300,
            ),
          ),
        if (_vista != 'cerrado')
          _seccion(
            _agenteSel == null
                ? 'Top 12 agentes (mes en curso)'
                : 'Agente $_agenteSel · resumen del mes',
            _agenteSel == null
                ? 'Consumo acumulado por agente (MWh)'
                : 'Consumo acumulado del agente seleccionado (MWh)',
            BarrasHorizontales(
              items: top,
              color: const Color(0xFF12B886),
              formato: (v) => fmtNumero(v, decimales: 0),
            ),
          ),
        if (_vista != 'cerrado' && agenteSerie.isNotEmpty)
          _seccion(
            'Agente $_agenteSel · consumo por versión',
            'Cómo creció el mes en cada versión publicada (MWh)',
            GraficaBarrasFl(
              valores: agenteSerie
                  .map((e) => (e['consumo'] as num?)?.toDouble() ?? 0)
                  .toList(),
              etiquetasX:
                  agenteSerie.map((e) => 'v${e['version']}').toList(),
              color: const Color(0xFF315C8A),
              etiquetaCada: 1,
              altura: 220,
            ),
          ),
        if (_vista != 'cerrado')
          _seccion(
            '"Pintado" del mes por versión',
            'Consumo acumulado según cada parcial publicado (así crece el mes)',
            GraficaLineas(
              series: seriesAcum,
              etiquetasX: labelsCurso,
              altura: 300,
            ),
          ),
        if (_vista != 'curso')
          _seccion(
            'Parcial vs Total · mes cerrado',
            'Último parcial (ámbar) frente al total final (verde)',
            GraficaLineas(
              series: [
                SerieLinea(
                    nombre: 'Último parcial',
                    valores: _nums(d['cerr_parcial']),
                    color: const Color(0xFFF0A020)),
                SerieLinea(
                    nombre: 'Total (final)',
                    valores: _nums(d['cerr_total']),
                    color: const Color(0xFF12B886)),
              ],
              etiquetasX: labelsCerr,
              altura: 280,
            ),
          ),
        if (_vista != 'curso')
          _seccion(
            'Ajuste diario Δ · mes cerrado',
            'Diferencia por día entre el total y el último parcial (MWh)',
            GraficaBarrasFl(
              valores: _nums(d['ajuste_dia']),
              etiquetasX: labelsCerr,
              color: const Color(0xFFD84A43),
              permitirNegativos: true,
              altura: 220,
            ),
          ),
        if (_vista != 'curso')
          _seccion(
            'Ajuste final por medida',
            'Variación % (total vs último parcial)',
            GraficaBarrasFl(
              valores: medValores,
              etiquetasX: medEtiquetas,
              colores: medColores,
              etiquetaCada: 1,
              altura: 240,
            ),
          ),
        _seccion(
          'Perfil horario promedio',
          'Consumo por hora (1–24, MWh)',
          GraficaLineas(
            series: [
              if (_vista != 'cerrado')
                SerieLinea(
                    nombre: 'Mes en curso',
                    valores: _nums(d['perfil_curso']),
                    color: const Color(0xFF315C8A),
                    area: true),
              if (_vista != 'curso')
                SerieLinea(
                    nombre: 'Mes cerrado',
                    valores: _nums(d['perfil_cerrado']),
                    color: const Color(0xFF7C4DFF)),
            ],
            etiquetasX: labelsHora,
            etiquetaCada: 3,
            altura: 260,
          ),
        ),
        if (_vista != 'cerrado')
          _seccion(
            'BRILLOSOL · monto ocasional',
            'Monto por día del mes en curso (proyección de cierre)',
            GraficaBarrasFl(
              valores: _nums(d['bri_curso']),
              etiquetasX: labelsCurso,
              color: const Color(0xFFF0A020),
              altura: 240,
            ),
          ),
        _tablaVersiones(versiones),
      ],
    );
  }

  Widget _filtrosVista() {
    final d = _data ?? const <String, dynamic>{};
    final periodos =
        ((d['periodos'] as List?) ?? []).map((e) => '$e').toList();
    final agentes = ((d['agentes'] as List?) ?? []).map((e) => '$e').toList();
    final periodoActual = '${d['periodo'] ?? ''}';
    final versiones = ((d['versiones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((v) => '${v['periodo']}' == periodoActual)
        .map((v) => (v['version'] as num?)?.toInt())
        .whereType<int>()
        .toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 155,
            child: DropdownButtonFormField<String>(
              key: ValueKey('sus-periodo-$periodoActual-${periodos.length}'),
              initialValue: periodos.contains(periodoActual)
                  ? periodoActual
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Período',
                  prefixIcon: Icon(Icons.event_outlined, size: 19),
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                for (final p in periodos)
                  DropdownMenuItem(value: p, child: Text(_periodo(p))),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _periodoSel = v;
                  _versionSel = null; // las versiones cambian con el período
                });
                _cargar();
              },
            ),
          ),
          if (versiones.isNotEmpty)
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('sus-version-$periodoActual-${versiones.length}'),
                initialValue:
                    versiones.contains(_versionSel) ? _versionSel : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Versión',
                    prefixIcon: Icon(Icons.layers_outlined, size: 19),
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Última')),
                  for (final v in versiones)
                    DropdownMenuItem<int?>(value: v, child: Text('v$v')),
                ],
                onChanged: (v) {
                  setState(() => _versionSel = v);
                  _cargar();
                },
              ),
            ),
          SizedBox(
            width: 240,
            child: Autocomplete<String>(
              key: ValueKey('sus-agente-${_agenteSel ?? ''}'),
              initialValue: TextEditingValue(text: _agenteSel ?? ''),
              optionsBuilder: (t) {
                final q = t.text.trim().toUpperCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return agentes
                    .where((a) => a.toUpperCase().contains(q))
                    .take(25);
              },
              onSelected: (v) {
                setState(() => _agenteSel = v);
                _cargar();
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Agente (código)',
                    hintText: 'Todos',
                    prefixIcon: const Icon(Icons.groups_outlined, size: 19),
                    suffixIcon: (_agenteSel == null)
                        ? null
                        : IconButton(
                            tooltip: 'Ver todos los agentes',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              setState(() => _agenteSel = null);
                              _cargar();
                            },
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                );
              },
            ),
          ),
          Text('Vista',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'ambos', label: Text('Comparativo')),
              ButtonSegment(value: 'curso', label: Text('Mes en curso')),
              ButtonSegment(value: 'cerrado', label: Text('Mes cerrado')),
            ],
            selected: {_vista},
            onSelectionChanged: (s) => setState(() => _vista = s.first),
          ),
          Text(
            _vista == 'ambos'
                ? 'Preliminar vs total final'
                : (_vista == 'curso'
                    ? 'Solo indicadores del mes en curso'
                    : 'Solo indicadores del mes cerrado'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(List<Widget> kpis) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, c) {
          final n = (c.maxWidth ~/ 260).clamp(1, 6);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: kpis.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 104,
            ),
            itemBuilder: (_, i) => kpis[i],
          );
        },
      ),
    );
  }

  Widget _indicadoresCurso({
    required int dias,
    required double total,
    required double promedio,
    required double maximo,
    required double minimo,
    required int diaMax,
    required double volatilidad,
    required double concentracion,
    required double top5,
    required double topTotal,
  }) {
    final items = <Widget>[
      _indicador('Días con datos', '$dias', Icons.calendar_month_outlined,
          const Color(0xFF315C8A)),
      _indicador('Promedio diario', '${fmtNumero(promedio, decimales: 1)} MWh',
          Icons.show_chart_outlined, const Color(0xFF0B6E4F)),
      _indicador('Máximo diario', '${fmtNumero(maximo, decimales: 1)} MWh',
          Icons.arrow_upward, const Color(0xFFF0A020),
          pie: diaMax > 0 ? 'día $diaMax' : null),
      _indicador('Mínimo diario', '${fmtNumero(minimo, decimales: 1)} MWh',
          Icons.arrow_downward, const Color(0xFF7C4DFF)),
      _indicador('Volatilidad', '${volatilidad.toStringAsFixed(1)}%',
          Icons.multiline_chart, const Color(0xFFD84A43),
          pie: 'desv. / promedio'),
      _indicador('Concentración top 5', '${concentracion.toStringAsFixed(1)}%',
          Icons.pie_chart_outline, const Color(0xFF39C5CF),
          pie: '${fmtNumero(top5, decimales: 0)} de ${fmtNumero(topTotal, decimales: 0)} MWh'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Indicadores del mes en curso',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(
                'Calculados con los datos diarios reales cargados (no se estiman valores faltantes).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final n = c.maxWidth >= 1100
                    ? 6
                    : (c.maxWidth >= 780
                        ? 3
                        : (c.maxWidth >= 480 ? 2 : 1));
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: n,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 80,
                  ),
                  itemBuilder: (_, i) => items[i],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _indicador(String titulo, String valor, IconData icono, Color color,
      {String? pie}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ),
                if (pie != null)
                  Text(pie,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5,
                          color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, String subtitulo, Widget hijo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(subtitulo,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 16),
            hijo,
          ],
        ),
      ),
    );
  }

  Widget _tablaVersiones(List versiones) {
    final periodos = versiones
        .map((v) => '${v['periodo'] ?? ''}')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final filtradas = versiones.where((v) {
      final p = '${v['periodo'] ?? ''}';
      if (_desdeVersion != null && p.compareTo(_desdeVersion!) < 0) return false;
      if (_hastaVersion != null && p.compareTo(_hastaVersion!) > 0) return false;
      if (_filtroVersion == 'final') return v['es_total'] == true;
      if (_filtroVersion == 'parcial') return v['es_total'] != true;
      return true;
    }).toList()
      ..sort((a, b) {
        final pa = '${a['periodo'] ?? ''}';
        final pb = '${b['periodo'] ?? ''}';
        final c = pb.compareTo(pa);
        if (c != 0) return c;
        return ((b['version'] as num?) ?? 0)
            .compareTo((a['version'] as num?) ?? 0);
      });

    return _seccion(
      'Versiones publicadas (${filtradas.length} de ${versiones.length})',
      'Cada archivo descargado y cargado, ordenado del más reciente al más antiguo. '
          'Filtra por tipo y por rango de períodos.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in const [
                ('todas', 'Todas'),
                ('parcial', 'Parciales'),
                ('final', 'DTE Sustentos (final)'),
              ])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _filtroVersion == f.$1,
                  onSelected: (_) => setState(() => _filtroVersion = f.$1),
                ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('ver-desde-$_desdeVersion'),
                  initialValue:
                      periodos.contains(_desdeVersion) ? _desdeVersion : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Desde',
                    isDense: true,
                    prefixIcon: Icon(Icons.event_outlined, size: 18),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin límite')),
                    for (final p in periodos)
                      DropdownMenuItem<String?>(
                          value: p, child: Text(_periodo(p))),
                  ],
                  onChanged: (v) => setState(() => _desdeVersion = v),
                ),
              ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('ver-hasta-$_hastaVersion'),
                  initialValue:
                      periodos.contains(_hastaVersion) ? _hastaVersion : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hasta',
                    isDense: true,
                    prefixIcon: Icon(Icons.event_available_outlined, size: 18),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin límite')),
                    for (final p in periodos)
                      DropdownMenuItem<String?>(
                          value: p, child: Text(_periodo(p))),
                  ],
                  onChanged: (v) => setState(() => _hastaVersion = v),
                ),
              ),
              if (_desdeVersion != null || _hastaVersion != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _desdeVersion = null;
                    _hastaVersion = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                  label: const Text('Quitar rango'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtradas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Sin versiones para este filtro')),
            )
          else
            Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.7),
                  ),
                  dataRowColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                  ),
                  columnSpacing: 26,
                  horizontalMargin: 16,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 46,
                  columns: const [
                    DataColumn(label: Text('Período')),
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('Tipo')),
                    DataColumn(label: Text('Versión')),
                    DataColumn(label: Text('Publicado')),
                    DataColumn(label: Text('Días'), numeric: true),
                    DataColumn(label: Text('Filas'), numeric: true),
                    DataColumn(label: Text('Consumo (MWh)'), numeric: true),
                  ],
                  rows: [
                    for (final v in filtradas)
                      DataRow(cells: [
                        DataCell(Text(_periodo(v['periodo']),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('${v['reporte_id'] ?? ''}')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (v['es_total'] == true) ...[
                              const Icon(Icons.verified,
                                  size: 15, color: Color(0xFF12B886)),
                              const SizedBox(width: 4),
                            ],
                            Text(_tipoCorto('${v['reporte_tipo']}')),
                          ],
                        )),
                        DataCell(Text('v${v['version']}')),
                        DataCell(Text('${v['fecha_pub'] ?? ''}')),
                        DataCell(Text('${v['dias'] ?? ''}')),
                        DataCell(Text(fmtNumero((v['filas'] as num?) ?? 0))),
                        DataCell(Text(
                            fmtNumero((v['consumo'] as num?) ?? 0,
                                decimales: 1))),
                      ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _corto(String s) {
    if (s.length <= 12) return s;
    return '${s.substring(0, 11)}…';
  }

  static String _tipoCorto(String tipo) {
    const mapa = {
      'CND_DTE_SUSTENTOS': 'DTE Sustentos',
      'CND_PRELIMINAR_SUSTENTOS': 'Preliminar',
      'CND_DTE_TABULAR': 'DTE Tabular',
      'CND_DTE_FIRMADO': 'DTE Firmado',
      'CND_PRESMENSMERCADO': 'Mensaje mercado',
    };
    return mapa[tipo] ?? tipo;
  }

  String _periodo(dynamic p) {
    final s = (p ?? '').toString();
    if (s.length < 6) return s;
    const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    try {
      return '${meses[int.parse(s.substring(4, 6))]} ${s.substring(0, 4)}';
    } catch (_) {
      return s;
    }
  }
}
