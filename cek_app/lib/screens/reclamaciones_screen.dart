import 'package:flutter/material.dart';

import '../models.dart';
import '../services/abrir_url.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/formulario.dart';

const _estados = ['identificada', 'en_revision', 'presentada', 'aceptada', 'rechazada'];

const _colores = {
  'identificada': Color(0xFFF0A020),
  'en_revision': Color(0xFF315C8A),
  'presentada': Color(0xFF7C4DFF),
  'aceptada': Color(0xFF12B886),
  'rechazada': Color(0xFFD84A43),
};

String _etiquetaEstado(String e) => e.replaceAll('_', ' ');

class ReclamacionesScreen extends StatefulWidget {
  const ReclamacionesScreen({super.key});

  @override
  State<ReclamacionesScreen> createState() => _ReclamacionesScreenState();
}

class _ReclamacionesScreenState extends State<ReclamacionesScreen> {
  List<Reclamacion> _items = [];
  List<Agente> _agentes = [];
  List<Cliente> _clientes = [];
  bool _cargando = true;
  String? _error;
  String? _filtroEstado;
  int? _filtroAgente;
  int? _filtroCliente;
  DateTime? _desdeFiltro;
  DateTime? _hastaFiltro;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = <String>[];
      if (_filtroEstado != null) params.add('estado=$_filtroEstado');
      if (_filtroAgente != null) params.add('id_agente=$_filtroAgente');
      if (_filtroCliente != null) params.add('id_cliente=$_filtroCliente');
      if (_desdeFiltro != null) params.add('desde=${_iso(_desdeFiltro!)}');
      if (_hastaFiltro != null) params.add('hasta=${_iso(_hastaFiltro!)}');
      final q = params.isEmpty ? '' : '?${params.join('&')}';
      final r = await Api.I.get('/reclamaciones$q') as List;
      final a = await Api.I.get('/agentes') as List;
      final c = await Api.I.get('/clientes') as List;
      setState(() {
        _items = r.map((e) => Reclamacion.fromJson(Map<String, dynamic>.from(e))).toList();
        _agentes = a.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
        _clientes = c.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirFecha({required bool desde}) async {
    final ahora = DateTime.now();
    final actual = desde ? _desdeFiltro : _hastaFiltro;
    final d = await showDatePicker(
      context: context,
      initialDate: actual ?? ahora,
      firstDate: DateTime(2020),
      lastDate: DateTime(ahora.year + 2, 12, 31),
      helpText: desde ? 'Fecha desde' : 'Fecha hasta',
    );
    if (d == null) return;
    setState(() {
      if (desde) {
        _desdeFiltro = d;
        if (_hastaFiltro != null && _hastaFiltro!.isBefore(d)) _hastaFiltro = d;
      } else {
        _hastaFiltro = d;
        if (_desdeFiltro != null && _desdeFiltro!.isAfter(d)) _desdeFiltro = d;
      }
    });
    _cargar();
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroEstado = null;
      _filtroAgente = null;
      _filtroCliente = null;
      _desdeFiltro = null;
      _hastaFiltro = null;
    });
    _cargar();
  }

  Agente? _agente(int id) {
    for (final a in _agentes) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _etiquetaCliente(int? id) {
    if (id == null) return '';
    for (final c in _clientes) {
      if (c.id == id) return c.etiqueta;
    }
    return 'Cliente $id';
  }

  Future<void> _nuevo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ReclamacionFormDialog(agentes: _agentes, clientes: _clientes),
    );
    if (ok == true) _cargar();
  }

  Future<void> _editar(Reclamacion r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ReclamacionFormDialog(
        reclamacion: r,
        agentes: _agentes,
        clientes: _clientes,
      ),
    );
    if (ok == true) _cargar();
  }

  Future<void> _detalle(Reclamacion r) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReclamacionDetalleDialog(
        reclamacion: r,
        agentes: _agentes,
        clientes: _clientes,
      ),
    );
    if (mounted) _cargar();
  }

  Future<void> _eliminar(Reclamacion r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar reclamación'),
        content: Text('¿Eliminar la reclamación #${r.id}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/reclamaciones/${r.id}');
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const EncabezadoSeccion(
              titulo: 'Reclamaciones',
              subtitulo: 'Todas las reclamaciones (filtra por agente, cliente, fechas y estado) '
                  'y ajustes publicados por el CND (AJ1/AJ2…)',
              icono: Icons.gavel_outlined,
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Reclamaciones', icon: Icon(Icons.gavel_outlined)),
                Tab(text: 'Ajustes CND (AJ1)', icon: Icon(Icons.tune)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _tabReclamos(),
                  const AjustesCNDTab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: Sesion.I.puedeEditar
            ? FloatingActionButton.extended(
                onPressed: _nuevo,
                icon: const Icon(Icons.add),
                label: const Text('Nueva reclamación'),
              )
            : null,
      ),
    );
  }

  Widget _tabReclamos() {
    if (_cargando && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);

    final clientesFiltrados = _filtroAgente == null
        ? _clientes
        : _clientes.where((c) => c.idAgente == _filtroAgente).toList();
    final hayFiltros = _filtroEstado != null ||
        _filtroAgente != null ||
        _filtroCliente != null ||
        _desdeFiltro != null ||
        _hastaFiltro != null;
    final desdeTxt = _desdeFiltro == null ? 'Desde' : 'Desde ${_fechaCorta(_desdeFiltro!)}';
    final hastaTxt = _hastaFiltro == null ? 'Hasta' : 'Hasta ${_fechaCorta(_hastaFiltro!)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey('agente-$_filtroAgente'),
                      initialValue: _filtroAgente,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Agente',
                        isDense: true,
                        prefixIcon: Icon(Icons.groups_outlined, size: 19),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Todos los agentes')),
                        for (final a in _agentes)
                          DropdownMenuItem<int?>(
                              value: a.id, child: Text(a.etiqueta)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _filtroAgente = v;
                          if (v != null &&
                              _filtroCliente != null &&
                              !_clientes.any((c) =>
                                  c.id == _filtroCliente && c.idAgente == v)) {
                            _filtroCliente = null;
                          }
                        });
                        _cargar();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey('cliente-$_filtroAgente-$_filtroCliente'),
                      initialValue: clientesFiltrados.any((c) => c.id == _filtroCliente)
                          ? _filtroCliente
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Cliente',
                        isDense: true,
                        prefixIcon: Icon(Icons.people_alt_outlined, size: 19),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Todos los clientes')),
                        for (final c in clientesFiltrados)
                          DropdownMenuItem<int?>(
                            value: c.id,
                            child: Text('${c.codigo} · ${c.etiqueta}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _filtroCliente = v);
                        _cargar();
                      },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _elegirFecha(desde: true),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(desdeTxt),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _elegirFecha(desde: false),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text(hastaTxt),
                  ),
                  if (hayFiltros)
                    TextButton.icon(
                      onPressed: _limpiarFiltros,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Limpiar filtros'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todos los estados'),
                    selected: _filtroEstado == null,
                    onSelected: (_) {
                      setState(() => _filtroEstado = null);
                      _cargar();
                    },
                  ),
                  for (final e in _estados)
                    ChoiceChip(
                      label: Text(_etiquetaEstado(e)),
                      selected: _filtroEstado == e,
                      onSelected: (_) {
                        setState(() => _filtroEstado = e);
                        _cargar();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_items.length} reclamación(es)'
                '${hayFiltros ? ' con los filtros aplicados' : ' en total'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _items.isEmpty
              ? EstadoVacio(
                  mensaje: hayFiltros
                      ? 'No hay reclamaciones con esos filtros'
                      : 'No hay reclamaciones registradas',
                  icono: Icons.gavel)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tarjeta(_items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  String _fechaCorta(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _tarjeta(Reclamacion r) {
    final ag = _agente(r.idAgente);
    final color = _colores[r.estado] ?? Colors.grey;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _detalle(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EstadoChip(_etiquetaEstado(r.estado), color),
                  const Spacer(),
                  if (r.monto != null)
                    Text(fmtMoneda(r.monto!),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(r.descripcion ?? r.tipo ?? 'Reclamación #${r.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text([
                if (ag != null) 'Agente: ${ag.etiqueta}',
                if (r.idCliente != null) 'Cliente: ${_etiquetaCliente(r.idCliente)}',
                if (r.periodo != null) 'Período: ${r.periodo}',
                if (r.fechaLimite != null) 'Vence: ${fmtFecha(r.fechaLimite)}',
              ].join(' · '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _detalle(r),
                    icon: const Icon(Icons.timeline, size: 18),
                    label: const Text('Seguimiento'),
                  ),
                  const Spacer(),
                  if (Sesion.I.puedeEditar)
                    IconButton(
                        tooltip: 'Editar',
                        onPressed: () => _editar(r),
                        icon: const Icon(Icons.edit_outlined, size: 20)),
                  if (Sesion.I.esAdmin)
                    IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => _eliminar(r),
                        icon: const Icon(Icons.delete_outline, size: 20)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Detalle + seguimiento
// --------------------------------------------------------------------------- //
class _ReclamacionDetalleDialog extends StatefulWidget {
  final Reclamacion reclamacion;
  final List<Agente> agentes;
  final List<Cliente> clientes;
  const _ReclamacionDetalleDialog({
    required this.reclamacion,
    required this.agentes,
    required this.clientes,
  });

  @override
  State<_ReclamacionDetalleDialog> createState() => _ReclamacionDetalleDialogState();
}

class _ReclamacionDetalleDialogState extends State<_ReclamacionDetalleDialog> {
  final _nota = TextEditingController();
  List<Seguimiento> _movs = [];
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _nuevoEstado;
  late String _estado;

  @override
  void initState() {
    super.initState();
    _estado = widget.reclamacion.estado;
    _cargar();
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Agente? get _agente {
    for (final a in widget.agentes) {
      if (a.id == widget.reclamacion.idAgente) return a;
    }
    return null;
  }

  String get _cliente {
    final id = widget.reclamacion.idCliente;
    if (id == null) return '—';
    for (final c in widget.clientes) {
      if (c.id == id) return c.etiqueta;
    }
    return 'Cliente $id';
  }

  Future<void> _cargar() async {
    try {
      final r = await Api.I.get('/reclamaciones/${widget.reclamacion.id}/seguimiento') as List;
      if (!mounted) return;
      setState(() {
        _movs = r.map((e) => Seguimiento.fromJson(Map<String, dynamic>.from(e))).toList();
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _agregar() async {
    final nota = _nota.text.trim();
    final cambiaEstado = _nuevoEstado != null && _nuevoEstado != _estado;
    if (nota.isEmpty && !cambiaEstado) return;
    setState(() => _guardando = true);
    try {
      await Api.I.post('/reclamaciones/${widget.reclamacion.id}/seguimiento', {
        if (nota.isNotEmpty) 'nota': nota,
        if (cambiaEstado) 'estado': _nuevoEstado,
      });
      if (cambiaEstado) _estado = _nuevoEstado!;
      _nota.clear();
      _nuevoEstado = null;
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reclamacion;
    final color = _colores[_estado] ?? Colors.grey;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
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
                        Row(
                          children: [
                            EstadoChip(_etiquetaEstado(_estado), color),
                            const SizedBox(width: 8),
                            Text('Reclamo #${r.id}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(r.descripcion ?? r.tipo ?? 'Sin descripción',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _datos(r),
                    const SizedBox(height: 20),
                    Text('Seguimiento',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_cargando)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red))
                    else if (_movs.isEmpty)
                      const Text('Sin movimientos registrados.')
                    else
                      ..._movs.map(_movimiento),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            if (Sesion.I.puedeEditar)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nota,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Agregar nota de seguimiento',
                        hintText: 'Llamada, envío, respuesta del CND…',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _nuevoEstado,
                            decoration: const InputDecoration(
                              labelText: 'Cambiar estado (opcional)',
                              prefixIcon: Icon(Icons.flag_outlined),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin cambio')),
                              for (final e in _estados)
                                DropdownMenuItem(value: e, child: Text(_etiquetaEstado(e))),
                            ],
                            onChanged: (v) => setState(() => _nuevoEstado = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _guardando ? null : _agregar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send),
                          label: const Text('Registrar'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Solo lectura',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _datos(Reclamacion r) {
    final filas = <MapEntry<String, String>>[
      MapEntry('Agente', _agente?.etiqueta ?? '—'),
      MapEntry('Cliente', _cliente),
      MapEntry('Tipo', r.tipo ?? '—'),
      MapEntry('Período', r.periodo ?? '—'),
      MapEntry('Monto', r.monto != null ? fmtMoneda(r.monto!) : '—'),
      MapEntry('Fecha del hecho', fmtFecha(r.fechaHecho)),
      MapEntry('Fecha límite', fmtFecha(r.fechaLimite)),
      MapEntry('Presentada', fmtFecha(r.fechaPresentacion)),
      MapEntry('Registrada', fmtFecha(r.creado)),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final f in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(f.key,
                        style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ),
                  Expanded(
                    child: Text(f.value.isEmpty ? '—' : f.value,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (r.evidencia != null && r.evidencia!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.attach_file,
                      size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Evidencia / documento adjunto',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: () => _abrirEvidencia(r.evidencia!.trim()),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Ver PDF'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Abre la evidencia de la reclamación: si es una URL (PDF) la abre en el
  /// navegador; si es una ruta/texto la muestra para copiarla.
  void _abrirEvidencia(String ev) {
    if (ev.startsWith('http://') || ev.startsWith('https://')) {
      abrirEnNavegador(ev);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Evidencia'),
        content: SelectableText(ev),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _movimiento(Seguimiento s) {
    final color = s.estado != null ? (_colores[s.estado] ?? Colors.grey) : const Color(0xFF9AA5B1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 3),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (s.estado != null)
                      EstadoChip(_etiquetaEstado(s.estado!), _colores[s.estado] ?? Colors.grey)
                    else
                      const Text('Nota', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(fmtFechaHora(s.fecha),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
                if (s.nota != null && s.nota!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(s.nota!),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('por ${s.usuario ?? 'sistema'}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Formulario (modal)
// --------------------------------------------------------------------------- //
class _ReclamacionFormDialog extends StatefulWidget {
  final Reclamacion? reclamacion;
  final List<Agente> agentes;
  final List<Cliente> clientes;
  const _ReclamacionFormDialog({
    this.reclamacion,
    required this.agentes,
    required this.clientes,
  });

  @override
  State<_ReclamacionFormDialog> createState() => _ReclamacionFormDialogState();
}

class _ReclamacionFormDialogState extends State<_ReclamacionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  final _periodo = TextEditingController();
  final _monto = TextEditingController();
  final _evidencia = TextEditingController();
  int? _idAgente;
  int? _idCliente;
  String _estado = 'identificada';
  String? _tipo;
  bool _guardando = false;

  static const _tipos = [
    'Error de medición',
    'Consumo incorrecto',
    'Cargo indebido',
    'Facturación',
    'Otro',
  ];

  bool get _esNuevo => widget.reclamacion == null;

  @override
  void initState() {
    super.initState();
    final r = widget.reclamacion;
    if (r != null) {
      _descripcion.text = r.descripcion ?? '';
      _periodo.text = r.periodo ?? '';
      _monto.text = r.monto?.toString() ?? '';
      _evidencia.text = r.evidencia ?? '';
      _idAgente = r.idAgente;
      _idCliente = r.idCliente;
      _estado = r.estado;
      _tipo = r.tipo;
    } else {
      _idAgente = widget.agentes.isEmpty ? null : widget.agentes.first.id;
    }
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _periodo.dispose();
    _monto.dispose();
    _evidencia.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idAgente == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccione un agente')));
      return;
    }
    setState(() => _guardando = true);
    final cuerpo = <String, dynamic>{
      'id_agente': _idAgente,
      'id_cliente': _idCliente,
      'tipo': _tipo,
      'descripcion': _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      'periodo': _periodo.text.trim().isEmpty ? null : _periodo.text.trim(),
      'monto': _monto.text.trim().isEmpty ? null : double.tryParse(_monto.text.trim()),
      'evidencia': _evidencia.text.trim().isEmpty ? null : _evidencia.text.trim(),
      'estado': _estado,
    };
    try {
      if (_esNuevo) {
        await Api.I.post('/reclamaciones', cuerpo);
      } else {
        await Api.I.put('/reclamaciones/${widget.reclamacion!.id}', cuerpo);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialogo(
      icono: _esNuevo ? Icons.report_problem_outlined : Icons.edit_note_outlined,
      titulo: _esNuevo ? 'Nueva reclamación' : 'Editar reclamación',
      subtitulo: 'Registra el reclamo de un agente o cliente',
      formKey: _formKey,
      maxAncho: 720,
      cuerpo: [
        FilaCampos(campos: [
          DropdownButtonFormField<int>(
            initialValue: _idAgente,
            decoration: const InputDecoration(
                labelText: 'Agente *', prefixIcon: Icon(Icons.groups_outlined)),
            items: [
              for (final a in widget.agentes)
                DropdownMenuItem(value: a.id, child: Text(a.etiqueta)),
            ],
            onChanged: (v) => setState(() => _idAgente = v),
          ),
          DropdownButtonFormField<int?>(
            initialValue: _idCliente,
            decoration: const InputDecoration(
                labelText: 'Cliente (opcional)',
                prefixIcon: Icon(Icons.people_alt_outlined)),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin cliente')),
              for (final c in widget.clientes)
                DropdownMenuItem(value: c.id, child: Text(c.etiqueta)),
            ],
            onChanged: (v) => setState(() => _idCliente = v),
          ),
        ]),
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          initialValue: _tipo,
          decoration: const InputDecoration(
              labelText: 'Tipo', prefixIcon: Icon(Icons.category_outlined)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin especificar')),
            for (final t in _tipos) DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (v) => setState(() => _tipo = v),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descripcion,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Descripción',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined)),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _evidencia,
          decoration: const InputDecoration(
              labelText: 'Evidencia / PDF (URL o ruta)',
              hintText: 'https://…',
              prefixIcon: Icon(Icons.picture_as_pdf_outlined)),
        ),
        const SizedBox(height: 14),
        FilaCampos(campos: [
          TextFormField(
            controller: _periodo,
            decoration: const InputDecoration(
                labelText: 'Período (AAAAMM)',
                prefixIcon: Icon(Icons.calendar_month_outlined)),
          ),
          TextFormField(
            controller: _monto,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Monto (B/.)', prefixIcon: Icon(Icons.attach_money)),
          ),
        ]),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _estado,
          decoration: const InputDecoration(
              labelText: 'Estado', prefixIcon: Icon(Icons.flag_outlined)),
          items: [
            for (final e in _estados)
              DropdownMenuItem(value: e, child: Text(_etiquetaEstado(e))),
          ],
          onChanged: (v) => setState(() => _estado = v ?? 'identificada'),
        ),
      ],
      acciones: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_esNuevo ? 'Crear reclamación' : 'Guardar cambios'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
// Ajustes publicados por el CND
// --------------------------------------------------------------------------- //
class AjustesCNDTab extends StatefulWidget {
  const AjustesCNDTab({super.key});

  @override
  State<AjustesCNDTab> createState() => _AjustesCNDTabState();
}

class _AjustesCNDTabState extends State<AjustesCNDTab> {
  static const _meses = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  List<AjusteCND> _items = [];
  bool _cargando = true;
  bool _sincronizando = false;
  String? _error;

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
      final r = await Api.I.get('/ajustes') as List;
      setState(() {
        _items = r
            .map((e) => AjusteCND.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    try {
      final r = await Api.I.post('/ajustes/sincronizar', {}) as Map;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Ajustes sincronizados: ${r['nuevos']} nuevo(s), '
                '${r['revisados']} revisado(s)')));
      }
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorVista(error: _error!, alReintentar: _cargar);
    }

    final porPeriodo = <String, List<AjusteCND>>{};
    for (final a in _items) {
      porPeriodo.putIfAbsent(a.periodo, () => []).add(a);
    }
    final periodos = porPeriodo.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _items.isEmpty
                      ? 'Aún no se han detectado ajustes (AJ1/AJ2) del portal.'
                      : '${_items.length} archivo(s) de ajuste en ${periodos.length} mes(es). '
                          'El CND reemite el mes completo con el sufijo AJ1 cuando atiende un reclamo. '
                          'Estos archivos son la fuente del CND; las reclamaciones se crean y '
                          'gestionan en la pestaña Reclamaciones.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              const SizedBox(width: 8),
              if (Sesion.I.puedeEditar)
                FilledButton.tonalIcon(
                  onPressed: _sincronizando ? null : _sincronizar,
                  icon: _sincronizando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Sincronizar'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? const EstadoVacio(
                  mensaje: 'No hay ajustes (AJ1/AJ2) del portal', icono: Icons.tune)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: periodos.length,
                    itemBuilder: (_, i) {
                      final periodo = periodos[i];
                      final archivos = porPeriodo[periodo]!;
                      final codigos = <String>{
                        for (final a in archivos) a.codigo ?? '?',
                      }.toList()
                        ..sort();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.tune),
                          ),
                          title: Text(_periodo(periodo)),
                          subtitle: Text('${archivos.length} archivo(s) · '
                              '${codigos.join(', ')}'),
                          children: [
                            for (final a in archivos)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.insert_drive_file_outlined),
                                title: Text(a.nombre ?? '—'),
                                subtitle: Text('${a.tipo ?? ''}'
                                    '${a.clienteCodigo != null ? ' · ${a.clienteCodigo}' : ''}'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _periodo(String p) {
    if (p.length < 6) return p;
    final anio = p.substring(0, 4);
    final mes = int.tryParse(p.substring(4, 6)) ?? 0;
    if (mes < 1 || mes > 12) return p;
    return '${_meses[mes]} $anio';
  }
}
