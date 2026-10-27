import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import 'analisis_clientes_screen.dart';
import 'cliente_form_dialog.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  List<Cliente> _clientes = [];
  List<Agente> _agentes = [];
  List<Agente> _distribuidores = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';
  int? _idAgenteFiltro;
  final _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final q = _filtro.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(_filtro)}';
      final data = await Api.I.get('/clientes$q') as List;
      final ags = await Api.I.get('/agentes') as List;
      final dist = await Api.I.get('/distribuidores') as List;
      setState(() {
        _clientes = data
            .map((e) => Cliente.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _agentes =
            ags.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
        _distribuidores =
            dist.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Cliente> get _filtrados {
    final q = _buscar.text.trim().toLowerCase();
    return _clientes.where((c) {
      if (_idAgenteFiltro != null && c.idAgente != _idAgenteFiltro) {
        return false;
      }
      if (q.isEmpty) return true;
      final texto = '${c.nombre ?? ''} ${c.codigo} ${c.nis ?? ''} '
              '${c.ruc ?? ''} ${c.agenteNombre ?? ''} ${c.agenteCodigo ?? ''} '
              '${c.contrato ?? ''}'
          .toLowerCase();
      return texto.contains(q);
    }).toList();
  }

  Future<void> _nuevo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClienteFormDialog(distribuidores: _agentes),
    );
    if (ok == true) _cargar();
  }

  Future<void> _editar(Cliente c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ClienteFormDialog(cliente: c, distribuidores: _agentes),
    );
    if (ok == true) _cargar();
  }

  Future<void> _eliminar(Cliente c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Eliminar a "${c.etiqueta}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/clientes/${c.id}');
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Clientes',
            subtitulo: '${_clientes.length} clientes · '
                '${_filtrados.length} visibles',
            icono: Icons.people_alt_outlined,
            acciones: [
              if (Sesion.I.puedeEditar)
                FilledButton.icon(
                  onPressed: _nuevo,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo cliente'),
                ),
            ],
          ),
          _ayudaAsociacion(),
          _filtros(),
          const SizedBox(height: 8),
          Expanded(child: _lista()),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _ayudaAsociacion() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Los clientes se crean aquí o se importan al descargar el CND. '
                'Se asocian a un agente mediante su contrato (pestaña Contratos); '
                'el distribuidor es solo el canal comercial.',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _buscar,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, código, NIS, agente o contrato…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _buscar.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _buscar.clear();
                          setState(() {});
                        },
                      ),
              ),
              onSubmitted: (v) {
                _filtro = v.trim();
                _cargar();
              },
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<int?>(
              initialValue: _idAgenteFiltro,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Agente asociado',
                prefixIcon: Icon(Icons.groups_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Todos los agentes')),
                for (final a in _agentes)
                  DropdownMenuItem<int?>(
                    value: a.id,
                    child: Text('${a.codigo} · ${a.etiqueta}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _idAgenteFiltro = v),
            ),
          ),
          if (_idAgenteFiltro != null)
            TextButton.icon(
              onPressed: () => setState(() => _idAgenteFiltro = null),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Quitar filtro'),
            ),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_cargando && _clientes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorVista(error: _error!, alReintentar: _cargar);
    }
    final items = _filtrados;
    if (items.isEmpty) {
      return const EstadoVacio(
          mensaje: 'No hay clientes con ese filtro', icono: Icons.people_outline);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(Cliente c) {
    Agente? dist;
    for (final d in _distribuidores) {
      if (d.id == c.idDistribuidor) {
        dist = d;
        break;
      }
    }
    final agente = c.agenteNombre ?? c.agenteCodigo;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ficha(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                child: Text(c.codigo.isNotEmpty ? c.codigo.substring(0, 1) : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.etiqueta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        if (!c.activo)
                          const EstadoChip('Inactivo', Color(0xFFD84A43)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _dato(Icons.tag, c.codigo),
                        if (agente != null)
                          _dato(Icons.groups_outlined, 'Agente: $agente',
                              color: const Color(0xFF0B6E4F))
                        else
                          _dato(Icons.link_off, 'Sin agente asignado',
                              color: const Color(0xFFF0A020)),
                        if (c.contrato != null)
                          _dato(Icons.description_outlined, c.contrato!),
                        if (dist != null &&
                            c.idDistribuidor != c.idAgente)
                          _dato(Icons.storefront_outlined,
                              'Canal: ${dist.etiqueta}'),
                        if (c.nis != null && c.nis!.isNotEmpty)
                          _dato(Icons.numbers, 'NIS ${c.nis}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (Sesion.I.puedeEditar)
                PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  onSelected: (v) {
                    if (v == 'editar') _editar(c);
                    if (v == 'ficha') _ficha(c);
                    if (v == 'eliminar') _eliminar(c);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ficha', child: Text('Ver ficha')),
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dato(IconData icono, String texto, {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 12, color: c),
        const SizedBox(width: 3),
        Text(texto, style: TextStyle(fontSize: 10.5, color: c)),
      ],
    );
  }

  void _ficha(Cliente c) {
    final dist = _distribuidores
        .where((d) => d.id == c.idDistribuidor)
        .map((d) => d.etiqueta)
        .join();
    final agente = c.agenteNombre ?? c.agenteCodigo;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    CircleAvatar(child: Text(c.codigo.isNotEmpty ? c.codigo[0] : '?')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.etiqueta,
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text('${c.codigo} · ${c.activo ? 'Activo' : 'Inactivo'}',
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
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _filaFicha('Agente', agente ?? 'Sin agente asignado'),
                    _filaFicha('Contrato', c.contrato ?? '—'),
                    _filaFicha('Tarifa', c.tarifa ?? '—'),
                    if (dist.isNotEmpty && c.idDistribuidor != c.idAgente)
                      _filaFicha('Canal comercial', dist),
                    _filaFicha('NIS', c.nis ?? '—'),
                    _filaFicha('RUC', c.ruc ?? '—'),
                    _filaFicha('Teléfono', c.telefono ?? '—'),
                    _filaFicha('Correo', c.email ?? '—'),
                    _filaFicha('Contacto', c.contacto ?? '—'),
                    _filaFicha('Dirección', c.direccion ?? '—'),
                    const SizedBox(height: 16),
                    Text(
                      'La asociación al agente se define en el contrato. Si el '
                      'cliente no tiene contrato, aparecerá como "sin agente" '
                      'hasta que se cree uno en Contratos.',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (c.idAgente != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnalisisClientesScreen(
                                idAgenteInicial: c.idAgente,
                                comoRuta: true,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.insights_outlined, size: 18),
                        label: const Text('Ver análisis del agente'),
                      ),
                    const Spacer(),
                    if (Sesion.I.puedeEditar)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _editar(c);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
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

  Widget _filaFicha(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(etiqueta,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
