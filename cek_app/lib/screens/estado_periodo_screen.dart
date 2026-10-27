import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/proceso_dialog.dart';

/// Estado mensual de facturación: por agente y período, cuántos clientes ya
/// tienen la liquidación del CND (el documento que permite emitir la factura)
/// y cuántos siguen pendientes.  Ej: "de 15 agentes, 12 listos, faltan 3".
///
/// La liquidación se publica ~el día 6 del mes siguiente, así que por defecto
/// se muestra el mes anterior (el que normalmente se está facturando).
class EstadoPeriodoScreen extends StatefulWidget {
  const EstadoPeriodoScreen({super.key});

  @override
  State<EstadoPeriodoScreen> createState() => _EstadoPeriodoScreenState();
}

class _EstadoPeriodoScreenState extends State<EstadoPeriodoScreen> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  late int _anio;
  late int _mes;
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _datos;
  Map<String, dynamic>? _runActivo;
  String? _codigoSeleccionado;
  Timer? _timerProceso;

  @override
  void initState() {
    super.initState();
    // Por defecto: el mes anterior (la liquidación sale ~el día 6 del siguiente).
    final hoy = DateTime.now();
    final prev = DateTime(hoy.year, hoy.month - 1, 1);
    _anio = prev.year;
    _mes = prev.month;
    _cargar();
  }

  @override
  void dispose() {
    _timerProceso?.cancel();
    super.dispose();
  }

  /// Mantiene vivo el avance de la corrida activa: mientras haya una descarga
  /// en curso, refresca el banner cada pocos segundos.  Así, si el usuario
  /// oculta el diálogo, puede volver a ver el progreso (o reabrirlo) sin tener
  /// que pulsar "Actualizar".
  void _programarPoll() {
    _timerProceso?.cancel();
    if (_runActivo == null) return;
    _timerProceso = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final runs = await Api.I.get('/proceso/ejecuciones?limite=1') as List;
        if (!mounted) return;
        Map<String, dynamic>? activo;
        if (runs.isNotEmpty) {
          final m = Map<String, dynamic>.from(runs.first as Map);
          if ('${m['estado']}' == 'corriendo') activo = m;
        }
        setState(() => _runActivo = activo);
        if (activo == null) {
          _timerProceso?.cancel();
          _timerProceso = null;
          _cargar();
        }
      } catch (_) {
        // El progreso es informativo; el estado mensual sigue funcionando.
      }
    });
  }

  List<int> get _anios {
    final hoy = DateTime.now().year;
    return [for (var a = hoy - 3; a <= hoy + 1; a++) a];
  }

  String get _periodo => '$_anio${_mes.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await Api.I.get('/facturas/estado?periodo=$_periodo');
      Map<String, dynamic>? activo;
      try {
        final runs = await Api.I.get('/proceso/ejecuciones?limite=1') as List;
        if (runs.isNotEmpty) {
          final m = Map<String, dynamic>.from(runs.first as Map);
          if ('${m['estado']}' == 'corriendo') activo = m;
        }
      } catch (_) {
        // El progreso es informativo; el estado mensual sigue funcionando.
      }
      if (!mounted) return;
      setState(() {
        _datos = Map<String, dynamic>.from(r as Map);
        _runActivo = activo;
      });
      _programarPoll();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Color _colorEstado(bool listo, int listos) {
    if (listo) return const Color(0xFF12B886);
    if (listos > 0) return const Color(0xFFF0A020);
    return const Color(0xFF9AA5B1);
  }

  Future<void> _descargarMes(List<Map<String, dynamic>> agentes) async {
    final codigos = agentes
        .map((a) => '${a['codigo'] ?? ''}')
        .where((c) => c.isNotEmpty)
        .toList();
    await abrirProcesoDialog(
      context,
      titulo: 'Descargar y transformar $_periodo',
      periodo: _periodo,
      codigos: codigos.isEmpty ? null : codigos,
      modo: 'completo',
      alTerminar: _cargar,
    );
    // Aunque el usuario oculte el diálogo, se recarga el estado para dejar el
    // banner de progreso visible y reabrible.
    if (mounted) _cargar();
  }

  Future<void> _descargarAgente(Map<String, dynamic> a) async {
    final codigo = '${a['codigo'] ?? ''}';
    if (codigo.isEmpty) return;
    await abrirProcesoDialog(
      context,
      titulo: '${a['nombre'] ?? codigo} · $_periodo',
      periodo: _periodo,
      codigos: [codigo],
      modo: 'completo',
      alTerminar: _cargar,
    );
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EncabezadoSeccion(
          titulo: 'Estado mensual',
          subtitulo: 'Avance de la facturación por agente · período $_periodo',
          icono: Icons.event_available_outlined,
          acciones: [
            if (Sesion.I.puedeEditar)
              FilledButton.tonalIcon(
                onPressed: _cargando
                    ? null
                    : () {
                        final lista = ((_datos?['agentes'] as List?) ?? [])
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        _descargarMes(lista);
                      },
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Descargar mes'),
              ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 15, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Aquí sigues el avance de la facturación del mes. Si lanzas una '
                  'descarga, puedes ocultarla y volver a ver el progreso aquí. '
                  'Para varios meses e historial usa "Descargas CND".',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('mes$_mes'),
                  initialValue: _mes,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Mes', isDense: true),
                  items: [
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _mes = v);
                    _cargar();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('anio$_anio'),
                  initialValue: _anio,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Año', isDense: true),
                  items: [
                    for (final a in _anios) DropdownMenuItem(value: a, child: Text('$a')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _anio = v);
                    _cargar();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _cuerpo()),
      ],
    );
  }

  Widget _cuerpo() {
    if (_cargando && _datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _datos == null) {
      return ErrorVista(error: _error!, alReintentar: _cargar);
    }
    final datos = _datos;
    if (datos == null) return const SizedBox.shrink();

    final resumen = Map<String, dynamic>.from(datos['resumen'] as Map? ?? {});
    final agentes = ((datos['agentes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (_runActivo != null) ...[
            _bannerProceso(),
            const SizedBox(height: 14),
          ],
          _descargaRapida(agentes),
          const SizedBox(height: 14),
          _resumenCard(resumen),
          const SizedBox(height: 14),
          if (agentes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: EstadoVacio(
                mensaje: 'No hay agentes con clientes para este período',
                icono: Icons.event_busy_outlined,
              ),
            )
          else
            for (final a in agentes) ...[
              _agenteCard(a),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _bannerProceso() {
    final tema = Theme.of(context);
    final run = _runActivo!;
    final p = Map<String, dynamic>.from((run['progreso'] as Map?) ?? {});
    final pct = (p['porcentaje'] as num?)?.toDouble() ?? 0;
    final paso = (p['paso'] as num?)?.toInt() ?? 0;
    final total = (p['total'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.sync, color: Color(0xFF315C8A)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Descarga en curso · ${run['periodo'] ?? ''} · '
                    '${pct.toStringAsFixed(1)}%',
                    style: tema.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('$paso de $total pasos completados',
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: tema.colorScheme.outline)),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                final id = run['id'] as int?;
                if (id == null) return;
                showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProcesoDialog(
                    runId: id,
                    titulo: 'Descarga CND · ${run['periodo'] ?? ''}',
                    alTerminar: _cargar,
                  ),
                ).then((_) => _cargar());
              },
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('Ver progreso'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _descargaRapida(List<Map<String, dynamic>> agentes) {
    if (!Sesion.I.puedeEditar) return const SizedBox.shrink();
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tema.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.download_for_offline_outlined,
                      color: tema.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Descargar un agente · $_periodo',
                          style: tema.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        'Elige el agente y lanza el scraper. Verás el avance por '
                        'etapas y podrás ocultarlo y reabrirlo.',
                        style: tema.textTheme.bodySmall
                            ?.copyWith(color: tema.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('descarga-$_codigoSeleccionado-$_periodo'),
                    initialValue: _codigoSeleccionado,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Agente',
                      prefixIcon: Icon(Icons.groups_outlined, size: 20),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos los agentes gestionados'),
                      ),
                      for (final a in agentes)
                        DropdownMenuItem<String?>(
                          value: '${a['codigo'] ?? ''}',
                          child: Text(
                            '${a['nombre'] ?? a['codigo'] ?? ''} · ${a['codigo'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _codigoSeleccionado = v),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _cargando
                      ? null
                      : () => _descargarSeleccion(agentes),
                  icon: const Icon(Icons.cloud_download_outlined, size: 19),
                  label: const Text('Descargar y transformar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _descargarSeleccion(List<Map<String, dynamic>> agentes) async {
    final codigos = _codigoSeleccionado == null
        ? agentes
            .map((a) => '${a['codigo'] ?? ''}')
            .where((c) => c.isNotEmpty)
            .toList()
        : [_codigoSeleccionado!];
    await abrirProcesoDialog(
      context,
      titulo: _codigoSeleccionado == null
          ? 'Todos los agentes · $_periodo'
          : '$_codigoSeleccionado · $_periodo',
      periodo: _periodo,
      codigos: codigos.isEmpty ? null : codigos,
      modo: 'completo',
      alTerminar: _cargar,
    );
    if (mounted) _cargar();
  }

  Widget _resumenCard(Map<String, dynamic> r) {
    final total = (r['agentes_total'] as num?)?.toInt() ?? 0;
    final listos = (r['agentes_listos'] as num?)?.toInt() ?? 0;
    final pendientes = (r['agentes_pendientes'] as num?)?.toInt() ?? 0;
    final cTotal = (r['clientes_total'] as num?)?.toInt() ?? 0;
    final cListos = (r['clientes_listos'] as num?)?.toInt() ?? 0;
    final cPen = (r['clientes_pendientes'] as num?)?.toInt() ?? 0;
    final pctAgentes = (r['porcentaje_agentes'] as num?)?.toDouble() ??
        (total == 0 ? 0 : listos * 100 / total);
    final pctClientes = (r['porcentaje_clientes'] as num?)?.toDouble() ??
        (r['porcentaje'] as num?)?.toDouble() ??
        (cTotal == 0 ? 0 : cListos * 100 / cTotal);
    final color = listos == total && total > 0
        ? const Color(0xFF12B886)
        : (listos > 0 ? const Color(0xFFF0A020) : const Color(0xFF9AA5B1));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.fact_check_outlined, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Facturación de $_periodo',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '$listos de $total agentes listos'
                        '${pendientes > 0 ? ' · faltan $pendientes' : ' · todo listo'}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                Text('${pctAgentes.round()}%',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : listos / total,
                minHeight: 10,
                backgroundColor: color.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Porcentaje calculado sobre agentes listos ($listos de $total).',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                EstadoChip('$listos/$total agentes listos', const Color(0xFF315C8A)),
                EstadoChip('$cListos/$cTotal clientes', const Color(0xFF0B6E4F)),
                EstadoChip('${pctClientes.round()}% de clientes', const Color(0xFF12B886)),
                if (cPen > 0)
                  EstadoChip('$cPen clientes pendientes', const Color(0xFFF0A020)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _agenteCard(Map<String, dynamic> a) {
    final total = (a['clientes_total'] as num?)?.toInt() ?? 0;
    final listos = (a['clientes_listos'] as num?)?.toInt() ?? 0;
    final pendientes = (a['clientes_pendientes'] as num?)?.toInt() ?? 0;
    final listo = a['listo'] == true;
    final sinClientes = total == 0 || a['sin_clientes'] == true;
    final color = sinClientes
        ? const Color(0xFF9AA5B1)
        : _colorEstado(listo, listos);
    final clientes = ((a['clientes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(
            sinClientes
                ? Icons.group_off_outlined
                : (listo ? Icons.check : Icons.hourglass_bottom),
            color: color,
          ),
        ),
        title: Text('${a['nombre'] ?? a['codigo'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sinClientes
                ? 'Sin clientes cargados'
                : '$listos de $total clientes con liquidación'),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : listos / total,
                minHeight: 6,
                backgroundColor: color.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
        trailing: EstadoChip(
          sinClientes
              ? 'Sin clientes'
              : listo
                  ? 'Listo'
                  : (pendientes == total ? 'Sin liquidación' : 'En proceso'),
          color,
        ),
        children: [
          if (Sesion.I.puedeEditar)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Descarga el mes desde el portal CND, lo transforma e '
                      'importa, y recalcula los resúmenes.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => _descargarAgente(a),
                    icon:
                        const Icon(Icons.cloud_download_outlined, size: 17),
                    label: Text('Descargar $_periodo'),
                  ),
                ],
              ),
            ),
          if (sinClientes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Este agente todavía no tiene clientes/contratos cargados. '
                'Se llenarán cuando se descargue su información del CND.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          for (final c in clientes) _clienteFila(c),
        ],
      ),
    );
  }

  Widget _clienteFila(Map<String, dynamic> c) {
    final listo = c['listo'] == true;
    final med = c['medicion'] == true;
    final dte = c['dte'] == true;
    final fact = c['factura'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(listo ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: listo ? const Color(0xFF12B886) : Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${c['codigo'] ?? ''} · ${c['nombre'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (fact) const Padding(
            padding: EdgeInsets.only(left: 6),
            child: EstadoChip('Facturada', Color(0xFF315C8A)),
          ),
          if (med) const Padding(
            padding: EdgeInsets.only(left: 6),
            child: EstadoChip('Medición', Color(0xFF12B886)),
          ),
          if (dte) const Padding(
            padding: EdgeInsets.only(left: 6),
            child: EstadoChip('DTE', Color(0xFF7048E8)),
          ),
        ],
      ),
    );
  }
}
