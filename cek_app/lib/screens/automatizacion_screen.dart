import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/formulario.dart';

/// Proceso masivo: carga de credenciales de los 14 agentes, descarga del CND,
/// importacion a la base y recálculo de resumenes. Muestra el avance en vivo.
class AutomatizacionScreen extends StatefulWidget {
  const AutomatizacionScreen({super.key});

  @override
  State<AutomatizacionScreen> createState() => _AutomatizacionScreenState();
}

class _AutomatizacionScreenState extends State<AutomatizacionScreen> {
  // Deshabilitado por ahora: el login/sincronización individual por agente
  // todavía no es el flujo que se quiere. El proceso masivo (descarga +
  // importación + resumen) sigue disponible en esta misma pantalla.
  static const bool _mostrarSincronizacionIndividual = false;

  List<Agente> _agentes = [];
  bool _cargando = true;
  String? _error;
  int? _ejecutando; // sync individual en curso

  Map<String, dynamic>? _cred;
  List<String> _periodos = [];
  Map<String, dynamic>? _run;
  int? _runId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final a = await Api.I.get('/agentes') as List;
      final lista = a
          .map((e) => Agente.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      Map<String, dynamic>? cred;
      List<String> periodos = [];
      try {
        final c = await Api.I.get('/proceso/credenciales');
        cred = Map<String, dynamic>.from(c);
      } catch (_) {}
      try {
        final p = await Api.I.get('/proceso/periodos');
        periodos = ((p['periodos'] as List?) ?? []).map((e) => '$e').toList();
      } catch (_) {}
      Map<String, dynamic>? corriendo;
      try {
        final ejec = await Api.I.get('/proceso/ejecuciones?limite=5') as List;
        for (final e in ejec) {
          if (e['estado'] == 'corriendo') {
            corriendo = Map<String, dynamic>.from(e);
            break;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _agentes = lista;
        _cred = cred;
        _periodos = periodos;
        if (corriendo != null) _run = corriendo;
      });
      if (corriendo != null) _iniciarPolling(corriendo['id'] as int);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ------------------------------------------------------------------ //
  // Avance del proceso
  // ------------------------------------------------------------------ //
  void _iniciarPolling(int id) {
    _runId = id;
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_runId == null) return;
    try {
      final r = await Api.I.get('/proceso/ejecuciones/$_runId');
      if (!mounted) return;
      setState(() => _run = Map<String, dynamic>.from(r));
      if (_run!['estado'] != 'corriendo') {
        _timer?.cancel();
        _timer = null;
        _cargar();
      }
    } catch (_) {
      // se reintenta en el siguiente tick
    }
  }

  // ------------------------------------------------------------------ //
  // Acciones
  // ------------------------------------------------------------------ //
  Future<void> _abrirCredenciales() async {
    final ctrl = TextEditingController();
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialogo(
        icono: Icons.vpn_key_outlined,
        titulo: 'Credenciales del portal CND',
        subtitulo: 'Se guardan cifradas (Fernet). Nunca se vuelven a mostrar.',
        cuerpo: [
          SeccionFormulario(
            titulo: 'Agentes',
            icono: Icons.list_alt_outlined,
            descripcion:
                'Una por línea: CODIGO,usuario,password. También acepta espacios o punto y coma.',
            hijos: [
              TextField(
                controller: ctrl,
                minLines: 7,
                maxLines: 12,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'CSOLAR,CSOLAR,clave\n'
                      'DECASOLAR,DECASOLAR,clave2\n'
                      'OROSOL,OROSOL,clave3',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ],
        acciones: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
    final texto = ctrl.text.trim();
    ctrl.dispose();
    if (guardar != true || texto.isEmpty) return;
    try {
      final res = await Api.I.post('/proceso/credenciales', {'texto': texto});
      final errores = (res['errores'] as List?) ?? [];
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Guardadas ${res['ok']} credenciales'
          '${errores.isEmpty ? '' : ' · ${errores.length} con error'}',
        ),
        backgroundColor: errores.isEmpty
            ? null
            : Theme.of(context).colorScheme.error,
      ));
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _abrirEjecutar({String modo = 'completo'}) async {
    final esImportar = modo == 'importar';
    String periodo = '__ultimos__';
    int meses = 2;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => FormDialogo(
          icono: esImportar ? Icons.storage_outlined : Icons.cloud_download_outlined,
          titulo: esImportar ? 'Solo importar datos' : 'Ejecutar proceso masivo',
          subtitulo: esImportar
              ? 'Lee los crudos ya descargados, llena la base y recalcula resúmenes.'
              : 'Descarga del CND para los 14 agentes, importa y recalcula resúmenes.',
          cuerpo: [
            SeccionFormulario(
              titulo: 'Alcance',
              icono: Icons.tune,
              hijos: [
                DropdownButtonFormField<String>(
                  initialValue: periodo,
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '__ultimos__',
                      child: Text('Últimos meses (más reciente)'),
                    ),
                    for (final p in _periodos)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setLocal(() => periodo = v ?? '__ultimos__'),
                ),
                if (periodo == '__ultimos__') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: meses,
                    decoration: const InputDecoration(
                      labelText: 'Meses hacia atrás',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 mes')),
                      DropdownMenuItem(value: 2, child: Text('2 meses')),
                      DropdownMenuItem(value: 3, child: Text('3 meses')),
                      DropdownMenuItem(value: 6, child: Text('6 meses')),
                    ],
                    onChanged: (v) => setLocal(() => meses = v ?? 2),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  '${_agentes.length} agentes · '
                  '${_agentes.where((a) => a.tieneCredencial).length} con credencial. '
                  'Los que no tengan credencial se marcarán como pendientes.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.outline, fontSize: 12),
                ),
              ],
            ),
          ],
          acciones: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(esImportar ? Icons.play_arrow : Icons.cloud_download_outlined),
              label: Text(esImportar ? 'Importar' : 'Ejecutar'),
            ),
          ],
        ),
      ),
    );
    if (confirmar != true) return;
    try {
      final res = await Api.I.post('/proceso/ejecutar', {
        'modo': modo,
        'meses': meses,
        if (periodo != '__ultimos__') 'periodo': periodo,
        'codigos': _agentes.map((a) => a.codigo).toList(),
      });
      if (!mounted) return;
      setState(() => _run = {
            'id': res['id'],
            'estado': 'corriendo',
            'periodo': periodo == '__ultimos__' ? null : periodo,
            'modo': modo,
            'detalle': [],
            'agentes': _agentes.map((a) => a.codigo).toList(),
          });
      _iniciarPolling(res['id'] as int);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proceso iniciado (${res['agentes']} agentes)')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _verPlan(Agente a) async {
    try {
      final plan = await Api.I.get('/automatizacion/plan/${a.id}');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Plan de sincronización · ${a.etiqueta}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _linea('Configurado', '${plan['configurado']}'),
                _linea('Scraper existe', '${plan['existe_scraper']}'),
                _linea('Python', '${plan['python']}'),
                _linea('Scraper', '${plan['scraper']}'),
                const SizedBox(height: 8),
                const Text('Argumentos:', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('${plan['argumentos']}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _linea(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Future<void> _sincronizar(Agente a) async {
    setState(() => _ejecutando = a.id);
    try {
      final res = await Api.I.post('/automatizacion/sync/${a.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['ok'] == true
              ? 'Sincronización iniciada para ${a.etiqueta}'
              : 'No se pudo sincronizar: ${res['detalle'] ?? 'error'}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _ejecutando = null);
    }
  }

  // ------------------------------------------------------------------ //
  // UI
  // ------------------------------------------------------------------ //
  @override
  Widget build(BuildContext context) {
    if (_cargando && _agentes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);

    final configurados = _cred?['configurados'] ?? _agentes.where((a) => a.tieneCredencial).length;
    final pendientes = _cred?['pendientes'] ?? (_agentes.length - configurados);

    return Column(
      children: [
        const EncabezadoSeccion(
          titulo: 'Proceso masivo',
          subtitulo: 'Credenciales de los 14 agentes · descarga CND · importación · resúmenes',
          icono: Icons.cloud_sync_outlined,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: _tarjetaResumen(configurados, pendientes),
        ),
        if (_run != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _tarjetaProgreso(),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargar,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: _agentes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _tarjetaAgente(_agentes[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaResumen(int configurados, int pendientes) {
    final tema = Theme.of(context);
    final ok = pendientes == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: ok ? const Color(0xFF12B886) : const Color(0xFFF0A020),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? 'Los 14 agentes tienen credenciales'
                        : 'Faltan credenciales de $pendientes agentes',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _miniKpi('Agentes', '${_agentes.length}', Icons.groups_outlined),
                _miniKpi('Configurados', '$configurados', Icons.vpn_key_outlined,
                    color: const Color(0xFF12B886)),
                _miniKpi('Pendientes', '$pendientes', Icons.key_off_outlined,
                    color: const Color(0xFFF0A020)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _abrirCredenciales(),
                  icon: const Icon(Icons.vpn_key_outlined, size: 18),
                  label: const Text('Cargar credenciales'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _abrirEjecutar(modo: 'completo'),
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('Descargar + importar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _abrirEjecutar(modo: 'importar'),
                  icon: const Icon(Icons.storage_outlined, size: 18),
                  label: const Text('Solo importar'),
                ),
              ],
            ),
            if (!ok) ...[
              const SizedBox(height: 10),
              Text(
                'Pega la lista con el formato CODIGO,usuario,password. '
                'Se guardan cifradas y se usan para el proceso masivo.',
                style: TextStyle(fontSize: 12, color: tema.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniKpi(String titulo, String valor, IconData icono, {Color? color}) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: color ?? tema.colorScheme.primary),
          const SizedBox(width: 6),
          Text('$titulo ',
              style: TextStyle(fontSize: 12, color: tema.colorScheme.outline)),
          Text(valor, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _tarjetaProgreso() {
    final run = _run!;
    final detalle = ((run['detalle'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final estado = '${run['estado'] ?? 'corriendo'}';
    final corriendo = estado == 'corriendo';
    final agentes = ((run['agentes'] as List?) ?? []).length;
    final terminados = detalle
        .where((d) => d['descarga'] != 'pendiente' && d['descarga'] != 'corriendo')
        .length;
    final progreso = agentes == 0 ? null : (terminados / agentes).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (corriendo)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    estado == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
                    size: 18,
                    color: estado == 'ok'
                        ? const Color(0xFF12B886)
                        : const Color(0xFFE03131),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    corriendo
                        ? 'Procesando${run['periodo'] != null ? ' · ${run['periodo']}' : ''}…'
                        : 'Última ejecución: $estado'
                            '${run['periodo'] != null ? ' · ${run['periodo']}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('$terminados/${run['agentes'] is List ? (run['agentes'] as List).length : agentes}',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
            if (corriendo) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progreso),
            ],
            if (detalle.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: detalle.length,
                  itemBuilder: (_, i) => _filaDetalle(detalle[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaDetalle(Map<String, dynamic> d) {
    final descarga = '${d['descarga'] ?? ''}';
    final imp = '${d['import'] ?? ''}';
    final malo = descarga == 'error' || imp == 'error';
    final bien = descarga == 'ok' || imp == 'ok';
    final icono = malo
        ? Icons.error_outline
        : bien
            ? Icons.check_circle_outline
            : descarga == 'sin_credencial'
                ? Icons.key_off_outlined
                : Icons.schedule;
    final color = malo
        ? const Color(0xFFE03131)
        : bien
            ? const Color(0xFF12B886)
            : const Color(0xFFF0A020);
    final salida = '${d['salida'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['codigo'] ?? ''} · $descarga/$imp',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (salida.isNotEmpty)
                  Text(
                    salida.split('\n').take(2).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                        fontFamily: 'monospace'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaAgente(Agente a) {
    final configurado = a.tieneCredencial;
    final bloqueado = _ejecutando != null && _ejecutando != a.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      (configurado ? const Color(0xFF12B886) : const Color(0xFFF0A020))
                          .withValues(alpha: 0.15),
                  child: Icon(
                    configurado ? Icons.vpn_key : Icons.key_off_outlined,
                    color: configurado ? const Color(0xFF12B886) : const Color(0xFFF0A020),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.etiqueta,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        configurado
                            ? 'Portal: ${a.usuarioPortal ?? "configurado"}'
                            : 'Sin credenciales del portal',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                EstadoChip(a.tipo,
                    a.distribuidor ? const Color(0xFF315C8A) : const Color(0xFF0B6E4F)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _verPlan(a),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Ver plan'),
                ),
                const SizedBox(width: 8),
                if (Sesion.I.puedeEditar && _mostrarSincronizacionIndividual)
                  FilledButton.icon(
                    onPressed: (!configurado || bloqueado || _ejecutando == a.id)
                        ? null
                        : () => _sincronizar(a),
                    icon: _ejecutando == a.id
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Sincronizar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
