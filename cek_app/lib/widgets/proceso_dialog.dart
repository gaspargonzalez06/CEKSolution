import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';

/// Lanza un proceso masivo (descarga CND + transformación + resumen) y muestra
/// una pantalla animada con las etapas en vivo.
///
/// Devuelve `true` si el proceso terminó sin errores graves.
Future<bool?> abrirProcesoDialog(
  BuildContext context, {
  required String titulo,
  required String periodo,
  List<String>? codigos,
  String modo = 'completo',
  int meses = 1,
  VoidCallback? alTerminar,
}) async {
  final Map<String, dynamic> res;
  try {
    final r = await Api.I.post('/proceso/ejecutar', {
      'modo': modo,
      'meses': meses,
      'periodo': periodo,
      if (codigos != null && codigos.isNotEmpty) 'codigos': codigos,
    });
    res = Map<String, dynamic>.from(r as Map);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo iniciar el proceso: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
    return false;
  }

  if (!context.mounted) return false;
  final runId = res['id'] as int?;
  if (runId == null) return false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProcesoDialog(
      runId: runId,
      titulo: titulo,
      alTerminar: alTerminar,
    ),
  );
}

/// Diálogo animado que sigue la corrida `runId` del backend.
///
/// Etapas: Descargar del CND → Transformar/importar → Consolidar resumen.
/// El avance (paso/total, porcentaje, etapa y tiempo estimado) lo calcula el
/// backend, de modo que la barra y el contador siempre coinciden.
class ProcesoDialog extends StatefulWidget {
  final int runId;
  final String titulo;
  final VoidCallback? alTerminar;

  const ProcesoDialog({
    super.key,
    required this.runId,
    required this.titulo,
    this.alTerminar,
  });

  @override
  State<ProcesoDialog> createState() => _ProcesoDialogState();
}

class _ProcesoDialogState extends State<ProcesoDialog>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _run;
  String? _error;
  Timer? _timer;
  late final AnimationController _pulso;
  bool _avisoTerminado = false;

  @override
  void initState() {
    super.initState();
    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulso.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await Api.I.get('/proceso/ejecuciones/${widget.runId}');
      if (!mounted) return;
      final run = Map<String, dynamic>.from(r as Map);
      setState(() {
        _run = run;
        _error = null;
      });
      if ('${run['estado']}' != 'corriendo') {
        _timer?.cancel();
        _timer = null;
        if (!_avisoTerminado) {
          _avisoTerminado = true;
          widget.alTerminar?.call();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _terminado => _run != null && _run!['estado'] != 'corriendo';

  Map<String, dynamic> get _progreso =>
      Map<String, dynamic>.from((_run?['progreso'] as Map?) ?? {});

  int get _pasosHechos => (_progreso['paso'] as num?)?.toInt() ?? 0;
  int get _totalPasos => (_progreso['total'] as num?)?.toInt() ?? 0;
  double get _porcentaje => (_progreso['porcentaje'] as num?)?.toDouble() ?? 0;
  int? get _restantes => (_progreso['segundos_restantes'] as num?)?.toInt();

  List<Map<String, dynamic>> get _detalle =>
      ((_run?['detalle'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => '${e['codigo'] ?? ''}' != '__plan__')
          .toList();

  /// Etapa 0 = descarga, 1 = transformación, 2 = resumen, 3 = terminado.
  int get _etapaActual {
    switch ('${_progreso['etapa'] ?? 'preparando'}') {
      case 'descargar':
        return 0;
      case 'transformar':
        return 1;
      case 'consolidar':
        return 2;
      case 'finalizado':
        return 3;
      default:
        // Respaldo por si el backend todavía no manda `progreso`.
        final d = _detalle;
        final agentes = d.where((x) =>
            !'${x['codigo'] ?? ''}'.startsWith('import:') &&
            x['codigo'] != 'resumen');
        final descargaLista = agentes.isNotEmpty &&
            agentes.every((x) => const [
                  'ok',
                  'error',
                  'sin_credencial',
                  'no_encontrado'
                ].contains('${x['descarga']}'));
        if (!descargaLista) return 0;
        final importes =
            d.where((x) => '${x['codigo'] ?? ''}'.startsWith('import:')).toList();
        final importListo = importes.isNotEmpty &&
            importes.every((x) => '${x['import']}' != 'pendiente');
        if (!importListo) return 1;
        return 2;
    }
  }

  String _fmtDuracion(int? segundos) {
    if (segundos == null || segundos < 0) return '';
    if (segundos < 60) return '${segundos}s';
    final min = (segundos / 60).ceil();
    if (min < 60) return '~$min min';
    return '~${(min / 60).toStringAsFixed(1)} h';
  }

  bool get _errorGrave {
    if (_run == null) return false;
    final estado = '${_run!['estado']}';
    if (estado == 'error') return true;
    if (estado == 'parcial') {
      return _detalle.any((x) =>
          '${x['descarga']}' == 'error' || '${x['import']}' == 'error');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final etapa = _terminado ? 3 : _etapaActual;
    final estado = '${_run?['estado'] ?? 'corriendo'}';
    final detalle = _detalle;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cabecera(tema, etapa, estado),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _etapas(tema, etapa, _errorGrave),
                    const SizedBox(height: 14),
                    _progresoBarra(tema),
                    if (detalle.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Detalle del proceso',
                          style: tema.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ..._filasDetalle(tema),
                    ],
                    if (_run?['mensaje'] != null &&
                        '${_run!['mensaje']}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _aviso(
                        tema,
                        Icons.info_outline,
                        tema.colorScheme.primary,
                        '${_run!['mensaje']}',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _aviso(tema, Icons.error_outline, tema.colorScheme.error,
                          'No se pudo leer el avance: $_error'),
                    ],
                    if (!_terminado) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Puedes ocultar esta ventana: el proceso sigue en el '
                        'servidor. Para volver a verlo, usa "Descargas CND" o '
                        'el botón "Ver progreso".',
                        style: tema.textTheme.bodySmall?.copyWith(
                            color: tema.colorScheme.outline, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              child: Row(
                children: [
                  if (!_terminado)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('Ocultar'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.alTerminar?.call();
                        Navigator.pop(context, estado == 'ok' || estado == 'parcial');
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cerrar'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _terminado
                        ? () {
                            widget.alTerminar?.call();
                            Navigator.pop(
                                context, estado == 'ok' || estado == 'parcial');
                          }
                        : null,
                    icon: Icon(_terminado ? Icons.check : Icons.hourglass_top),
                    label: Text(_terminado ? 'Listo' : 'Procesando…'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera(ThemeData tema, int etapa, String estado) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tema.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.cloud_sync_outlined,
                size: 24, color: tema.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  _terminado
                      ? (estado == 'ok'
                          ? 'Completado'
                          : (estado == 'parcial'
                              ? 'Completado con observaciones'
                              : 'Con error'))
                      : _totalPasos > 0
                          ? 'Paso $_pasosHechos de $_totalPasos · '
                              '${_porcentaje.toStringAsFixed(0)}% · ${_nombreEtapa(etapa)}'
                          : 'Iniciando · ${_nombreEtapa(etapa)}',
                  style: tema.textTheme.bodySmall
                      ?.copyWith(color: tema.colorScheme.outline),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _progresoBarra(ThemeData tema) {
    final pct = _terminado ? 100.0 : _porcentaje;
    final restante = _fmtDuracion(_restantes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _totalPasos > 0
                    ? '$_pasosHechos de $_totalPasos pasos completados'
                    : 'Iniciando proceso…',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tema.colorScheme.onSurface),
              ),
            ),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: tema.colorScheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _totalPasos > 0 ? (pct / 100).clamp(0.0, 1.0) : null,
            minHeight: 10,
            backgroundColor: tema.colorScheme.surfaceContainerHighest,
          ),
        ),
        if (!_terminado && restante.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Tiempo estimado restante: $restante',
              style: TextStyle(fontSize: 11, color: tema.colorScheme.outline),
            ),
          ),
      ],
    );
  }

  String _nombreEtapa(int e) {
    switch (e) {
      case 0:
        return 'descargando del CND';
      case 1:
        return 'transformando e importando';
      case 2:
        return 'consolidando resúmenes';
      default:
        return 'finalizado';
    }
  }

  Widget _etapas(ThemeData tema, int etapa, bool errorGrave) {
    const titulos = [
      ('Descargar', Icons.cloud_download_outlined),
      ('Transformar', Icons.transform_outlined),
      ('Consolidar', Icons.functions_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < titulos.length; i++) ...[
          Expanded(
            child: _paso(
              tema,
              i,
              titulos[i].$1,
              titulos[i].$2,
              activo: !_terminado && i == etapa,
              hecho: i < etapa || (_terminado && !errorGrave),
              error: _terminado && errorGrave && i == etapa,
            ),
          ),
          if (i < titulos.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right,
                  size: 18, color: tema.colorScheme.outline),
            ),
        ],
      ],
    );
  }

  Widget _paso(ThemeData tema, int i, String titulo, IconData icono,
      {required bool activo, required bool hecho, required bool error}) {
    final color = error
        ? tema.colorScheme.error
        : hecho
            ? const Color(0xFF12B886)
            : activo
                ? tema.colorScheme.primary
                : tema.colorScheme.outline;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: activo || hecho || error ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          children: [
            if (activo)
              AnimatedBuilder(
                animation: _pulso,
                builder: (_, _) => Transform.scale(
                  scale: 1 + _pulso.value * 0.14,
                  child: Icon(icono, color: color, size: 24),
                ),
              )
            else
              Icon(
                error
                    ? Icons.error_outline
                    : hecho
                        ? Icons.check_circle_outline
                        : icono,
                color: color,
                size: 24,
              ),
            const SizedBox(height: 6),
            Text(titulo,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _aviso(ThemeData tema, IconData icono, Color color, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    fontSize: 12.5, color: tema.colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }

  List<Widget> _filasDetalle(ThemeData tema) {
    final d = _detalle;
    final agentes = d
        .where((x) =>
            !'${x['codigo'] ?? ''}'.startsWith('import:') &&
            x['codigo'] != 'resumen')
        .toList();
    final pasos = d
        .where((x) =>
            '${x['codigo'] ?? ''}'.startsWith('import:') ||
            x['codigo'] == 'resumen')
        .toList();
    return [
      if (agentes.isNotEmpty) ...[
        Text('Agentes',
            style: tema.textTheme.labelSmall
                ?.copyWith(color: tema.colorScheme.outline)),
        for (final x in agentes) _fila(tema, x),
      ],
      if (pasos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Transformación',
            style: tema.textTheme.labelSmall
                ?.copyWith(color: tema.colorScheme.outline)),
        for (final x in pasos) _fila(tema, x),
      ],
    ];
  }

  Widget _fila(ThemeData tema, Map<String, dynamic> x) {
    final codigo = '${x['codigo'] ?? ''}';
    final esImport = codigo.startsWith('import:');
    final esResumen = codigo == 'resumen';
    final estado = esImport || esResumen
        ? '${x['import'] ?? 'pendiente'}'
        : '${x['descarga'] ?? 'pendiente'}';

    late final Color color;
    late final IconData icono;
    late final String etiqueta;
    switch (estado) {
      case 'ok':
        color = const Color(0xFF12B886);
        icono = Icons.check_circle_outline;
        etiqueta = 'Listo';
        break;
      case 'error':
        color = tema.colorScheme.error;
        icono = Icons.error_outline;
        etiqueta = 'Error';
        break;
      case 'corriendo':
        color = tema.colorScheme.primary;
        icono = Icons.sync;
        etiqueta = 'En curso';
        break;
      case 'sin_credencial':
        color = const Color(0xFFF0A020);
        icono = Icons.key_off_outlined;
        etiqueta = 'Sin credencial';
        break;
      case 'no_encontrado':
        color = const Color(0xFFF0A020);
        icono = Icons.search_off;
        etiqueta = 'No encontrado';
        break;
      default:
        color = tema.colorScheme.outline;
        icono = Icons.schedule;
        etiqueta = 'Pendiente';
    }

    final titulo = esResumen
        ? 'Consolidar resúmenes del mercado'
        : esImport
            ? 'Transformar ${codigo.substring(7)}'
            : '${x['nombre'] ?? codigo}';
    final subtitulo = esImport || esResumen ? null : codigo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (subtitulo != null)
                  Text(subtitulo,
                      style: TextStyle(
                          fontSize: 10.5, color: tema.colorScheme.outline)),
              ],
            ),
          ),
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
