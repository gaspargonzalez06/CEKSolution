import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/comunes.dart';
import '../widgets/proceso_dialog.dart';

/// Descargas del CND: elegir agente + mes y lanzar el scraper, la
/// transformación/importación y el recálculo de resúmenes.
///
/// Es la pantalla "visible" del proceso: muestra el avance con porcentaje,
/// permite ocultar el diálogo y volver a abrirlo desde la tarjeta de progreso,
/// y guarda el historial de corridas para consultarlas después.
class DescargasScreen extends StatefulWidget {
  const DescargasScreen({super.key});

  @override
  State<DescargasScreen> createState() => _DescargasScreenState();
}

class _DescargasScreenState extends State<DescargasScreen> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  List<Agente> _agentes = [];
  List<Map<String, dynamic>> _historial = [];
  Map<String, dynamic>? _runActivo;
  Map<String, dynamic>? _plan;
  bool _cargando = true;
  bool _iniciando = false;
  String? _error;
  String? _codigo; // null = todos los agentes gestionados
  String _modo = 'completo';
  String _perfil = 'esencial';
  int _mesesAtras = 1;
  late int _anio;
  late int _mes;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    final prev = DateTime(hoy.year, hoy.month - 1, 1);
    _anio = prev.year;
    _mes = prev.month;
    _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _periodo => '$_anio${_mes.toString().padLeft(2, '0')}';

  List<int> get _anios {
    final hoy = DateTime.now().year;
    return [for (var a = hoy - 4; a <= hoy + 1; a++) a];
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final a = await Api.I.get('/agentes') as List;
      final h = await Api.I.get('/proceso/ejecuciones?limite=12') as List;
      Map<String, dynamic>? activo;
      for (final e in h) {
        final m = Map<String, dynamic>.from(e as Map);
        if ('${m['estado']}' == 'corriendo') {
          activo = m;
          break;
        }
      }
      Map<String, dynamic>? plan;
      try {
        plan = Map<String, dynamic>.from(await Api.I.get('/proceso/plan') as Map);
      } catch (_) {
        // El plan es informativo; si falla, la pantalla sigue funcionando.
      }
      if (!mounted) return;
      setState(() {
        _agentes = a.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
        _historial = h.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _runActivo = activo;
        _plan = plan;
      });
      if (activo != null) _programarPolling();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _programarPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refrescarActivo());
  }

  Future<void> _refrescarActivo() async {
    final id = _runActivo?['id'] as int?;
    if (id == null) return;
    try {
      final r = await Api.I.get('/proceso/ejecuciones/$id');
      if (!mounted) return;
      final run = Map<String, dynamic>.from(r as Map);
      setState(() => _runActivo = run);
      if ('${run['estado']}' != 'corriendo') {
        _timer?.cancel();
        _timer = null;
        _cargarHistorial();
      }
    } catch (_) {
      // se reintenta en el siguiente tick
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final h = await Api.I.get('/proceso/ejecuciones?limite=12') as List;
      if (!mounted) return;
      setState(() {
        _historial = h.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      // silencioso
    }
  }

  Future<void> _lanzar() async {
    if (_iniciando) return;
    setState(() => _iniciando = true);
    try {
      final r = await Api.I.post('/proceso/ejecutar', {
        'periodo': _periodo,
        'modo': _modo,
        'perfil': _perfil,
        'meses': _mesesAtras,
        if (_codigo != null) 'codigos': [_codigo],
      });
      final run = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      setState(() => _runActivo = run);
      _programarPolling();
      _verProgreso(run);
      _cargarHistorial();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo iniciar la descarga: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  void _verProgreso(Map<String, dynamic> run) {
    final id = run['id'] as int?;
    if (id == null) return;
    final codigo = run['periodo'] ?? _periodo;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcesoDialog(
        runId: id,
        titulo: 'Descarga CND · $codigo',
        alTerminar: () {
          _refrescarActivo();
          _cargarHistorial();
        },
      ),
    ).then((_) {
      _refrescarActivo();
      _cargarHistorial();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EncabezadoSeccion(
          titulo: 'Descargas CND',
          subtitulo: 'Descarga, transforma e importa un mes de un agente. '
              'También puedes relanzar la transformación sin volver a descargar.',
          icono: Icons.cloud_download_outlined,
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(child: _cuerpo()),
      ],
    );
  }

  Widget _cuerpo() {
    if (_cargando && _agentes.isEmpty && _historial.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _agentes.isEmpty) {
      return ErrorVista(error: _error!, alReintentar: _cargar);
    }
    final configurados = (_plan?['configurados'] as num?)?.toInt();
    final totalAgentes = (_plan?['total'] as num?)?.toInt();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _selectorCard(configurados, totalAgentes),
          const SizedBox(height: 14),
          if (_runActivo != null) ...[
            _progresoCard(_runActivo!),
            const SizedBox(height: 14),
          ],
          _historialCard(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selector agente + mes + modo
  // ---------------------------------------------------------------------------
  Widget _selectorCard(int? configurados, int? totalAgentes) {
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
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tema.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.download_for_offline_outlined,
                      color: tema.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Descargar un mes',
                          style: tema.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        'Elige el agente y el mes. Se ejecutan las etapas: '
                        'descargar del CND → transformar/importar → consolidar.',
                        style: tema.textTheme.bodySmall
                            ?.copyWith(color: tema.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (configurados != null && totalAgentes != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  EstadoChip(
                    '$configurados/$totalAgentes con credenciales',
                    configurados == totalAgentes
                        ? const Color(0xFF12B886)
                        : const Color(0xFFF0A020),
                  ),
                  if (configurados < totalAgentes)
                    Text(
                      'Los agentes sin credencial se omiten.',
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: tema.colorScheme.outline),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 290,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('agente-$_codigo'),
                    initialValue: _codigo,
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
                      for (final a in _agentes)
                        DropdownMenuItem<String?>(
                          value: a.codigo,
                          child: Text('${a.etiqueta} · ${a.codigo}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _codigo = v),
                  ),
                ),
                SizedBox(
                  width: 165,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('mes-$_mes'),
                    initialValue: _mes,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _mes = v);
                    },
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('anio-$_anio'),
                    initialValue: _anio,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Año'),
                    items: [
                      for (final a in _anios)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _anio = v);
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('meses-$_mesesAtras'),
                    initialValue: _mesesAtras,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Meses atrás'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 mes')),
                      DropdownMenuItem(value: 3, child: Text('3 meses')),
                      DropdownMenuItem(value: 6, child: Text('6 meses')),
                      DropdownMenuItem(value: 12, child: Text('12 meses')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _mesesAtras = v);
                    },
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    initialValue: _modo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Qué ejecutar'),
                    items: const [
                      DropdownMenuItem(
                          value: 'completo',
                          child: Text('Descargar + transformar')),
                      DropdownMenuItem(
                          value: 'descarga', child: Text('Solo descargar')),
                      DropdownMenuItem(
                          value: 'importar', child: Text('Solo transformar')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _modo = v);
                    },
                  ),
                ),
                SizedBox(
                  width: 310,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('perfil-$_perfil'),
                    initialValue: _perfil,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Qué descargar',
                      prefixIcon: Icon(Icons.filter_alt_outlined, size: 20),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'esencial',
                          child: Text('Esencial (lo que usa la app)')),
                      DropdownMenuItem(
                          value: 'facturacion',
                          child: Text('Solo facturación (mediciones/DTE)')),
                      DropdownMenuItem(
                          value: 'sustentos',
                          child: Text('Solo sustentos (mercado)')),
                      DropdownMenuItem(
                          value: 'todo',
                          child: Text('Todo (histórico completo)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _perfil = v);
                    },
                  ),
                ),
                FilledButton.icon(
                  onPressed: _iniciando || _runActivo != null ? null : _lanzar,
                  icon: _iniciando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download_outlined, size: 20),
                  label: Text(_runActivo != null
                      ? 'Proceso en curso…'
                      : _mesesAtras == 1
                          ? 'Descargar ${_meses[_mes - 1]} $_anio'
                          : 'Descargar $_mesesAtras meses hasta ${_meses[_mes - 1]} $_anio'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _textoPerfil(),
              style: tema.textTheme.bodySmall
                  ?.copyWith(color: tema.colorScheme.outline),
            ),
            if (_runActivo != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ya hay un proceso corriendo. Espera a que termine para lanzar otro.',
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: tema.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progreso de la corrida activa
  // ---------------------------------------------------------------------------
  Widget _progresoCard(Map<String, dynamic> run) {
    final tema = Theme.of(context);
    final p = Map<String, dynamic>.from((run['progreso'] as Map?) ?? {});
    final pct = (p['porcentaje'] as num?)?.toDouble() ?? 0;
    final paso = (p['paso'] as num?)?.toInt() ?? 0;
    final total = (p['total'] as num?)?.toInt() ?? 0;
    final etapa = '${p['etapa'] ?? 'preparando'}';
    final estado = '${run['estado'] ?? 'corriendo'}';
    final corriendo = estado == 'corriendo';
    final color = corriendo
        ? const Color(0xFF315C8A)
        : (estado == 'ok' ? const Color(0xFF12B886) : const Color(0xFFF0A020));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(corriendo ? Icons.sync : Icons.task_alt, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    corriendo
                        ? 'Proceso en curso · ${_nombreEtapa(etapa)}'
                        : 'Último proceso · ${_etiquetaEstado(estado)}',
                    style: tema.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${pct.toStringAsFixed(1)}%',
                    style: tema.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total > 0 ? (pct / 100).clamp(0.0, 1.0) : null,
                minHeight: 10,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$paso de $total pasos',
                    style: tema.textTheme.bodySmall
                        ?.copyWith(color: tema.colorScheme.outline)),
                if (run['periodo'] != null)
                  EstadoChip('Período ${run['periodo']}', const Color(0xFF315C8A)),
                if (run['modo'] != null)
                  EstadoChip('${run['modo']}', const Color(0xFF7C4DFF)),
                TextButton.icon(
                  onPressed: () => _verProgreso(run),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('Ver progreso'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Historial
  // ---------------------------------------------------------------------------
  Widget _historialCard() {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Últimas corridas',
                      style: tema.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: _cargarHistorial,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_historial.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text('Todavía no hay descargas registradas.',
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: tema.colorScheme.outline)),
                ),
              )
            else
              for (final run in _historial) _filaHistorial(run),
          ],
        ),
      ),
    );
  }

  Widget _filaHistorial(Map<String, dynamic> run) {
    final tema = Theme.of(context);
    final p = Map<String, dynamic>.from((run['progreso'] as Map?) ?? {});
    final pct = (p['porcentaje'] as num?)?.toDouble() ?? 0;
    final estado = '${run['estado'] ?? ''}';
    final color = estado == 'ok'
        ? const Color(0xFF12B886)
        : (estado == 'corriendo'
            ? const Color(0xFF315C8A)
            : (estado == 'parcial'
                ? const Color(0xFFF0A020)
                : const Color(0xFFD84A43)));
    final inicio = '${run['inicio'] ?? ''}'.replaceFirst('T', ' ');
    final fecha = inicio.length >= 16 ? inicio.substring(0, 16) : inicio;
    final agentes = ((run['agentes'] as List?) ?? []).length;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _verProgreso(run),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            Icon(
              estado == 'corriendo' ? Icons.sync : Icons.history,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${run['periodo'] ?? '—'} · ${run['modo'] ?? ''} · '
                    '$agentes agente(s)',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${fecha.isEmpty ? '' : '$fecha · '}'
                    '${p['paso'] ?? 0}/${p['total'] ?? 0} pasos · '
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 10.5, color: tema.colorScheme.outline),
                  ),
                ],
              ),
            ),
            EstadoChip(_etiquetaEstado(estado), color),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  bool get _esMesEnCurso {
    final hoy = DateTime.now();
    return _anio == hoy.year && _mes == hoy.month;
  }

  String _textoPerfil() {
    switch (_perfil) {
      case 'facturacion':
        return 'Solo baja mediciones (liquidación), DTE y DTER de los agentes. '
            'No toca sustentos del mercado.';
      case 'sustentos':
        return 'Solo baja los reporte_totales del mercado e importa '
            'sustento_horario. No baja archivos por agente.';
      case 'todo':
        return 'Baja todo lo que publique el CND (incluye formatos que la app '
            'no usa). Úsalo solo para algo puntual.';
      default:
        final rango = _mesesAtras > 1
            ? ' Se procesan $_mesesAtras meses hacia atrás.'
            : '';
        return 'Esencial baja solo lo que usa la app: mediciones/DTE/DTER de los '
            'agentes + los sustentos unificados del mes'
            '${_esMesEnCurso ? '. Como es el mes en curso, agrega también los '
                'parciales de sustentos' : ''}.$rango';
    }
  }

  String _nombreEtapa(String e) {
    switch (e) {
      case 'descargar':
        return 'descargando del CND';
      case 'transformar':
        return 'transformando e importando';
      case 'consolidar':
        return 'consolidando resúmenes';
      case 'finalizado':
        return 'finalizado';
      default:
        return 'preparando';
    }
  }

  String _etiquetaEstado(String e) {
    switch (e) {
      case 'corriendo':
        return 'En curso';
      case 'ok':
        return 'Completado';
      case 'parcial':
        return 'Con observaciones';
      case 'error':
        return 'Con error';
      default:
        return e;
    }
  }
}
