import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import 'contrato_detalle_screen.dart';
import 'contrato_form_dialog.dart';

class ContratosScreen extends StatefulWidget {
  const ContratosScreen({super.key});

  @override
  State<ContratosScreen> createState() => _ContratosScreenState();
}

class _ContratosScreenState extends State<ContratosScreen> {
  List<Contrato> _contratos = [];
  List<Agente> _agentes = [];
  List<Cliente> _clientes = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';
  int? _idAgenteFiltro;
  String _estadoFiltro = 'todos'; // todos | activos | inactivos

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
      final c = await Api.I.get('/contratos') as List;
      final a = await Api.I.get('/agentes') as List;
      final cl = await Api.I.get('/clientes') as List;
      setState(() {
        _contratos = c.map((e) => Contrato.fromJson(Map<String, dynamic>.from(e))).toList();
        _agentes = a.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
        _clientes = cl.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Agente? _agenteDe(int id) {
    for (final a in _agentes) {
      if (a.id == id) return a;
    }
    return null;
  }

  Cliente? _clienteDe(int id) {
    for (final c in _clientes) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Contrato> get _visibles {
    final f = _filtro.trim().toLowerCase();
    return _contratos.where((c) {
      if (_idAgenteFiltro != null && c.idAgente != _idAgenteFiltro) {
        return false;
      }
      if (_estadoFiltro == 'activos' && !c.activo) return false;
      if (_estadoFiltro == 'inactivos' && c.activo) return false;
      if (f.isEmpty) return true;
      final ag = _agenteDe(c.idAgente)?.etiqueta.toLowerCase() ?? '';
      final cl = _clienteDe(c.idCliente)?.etiqueta.toLowerCase() ?? '';
      final co = (c.contrato ?? '').toLowerCase();
      return ag.contains(f) || cl.contains(f) || co.contains(f);
    }).toList();
  }

  Future<void> _nuevo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ContratoFormDialog(agentes: _agentes, clientes: _clientes),
    );
    if (ok == true) _cargar();
  }

  Future<void> _abrir(Contrato c) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContratoDetalleScreen(
          contrato: c,
          agente: _agenteDe(c.idAgente),
          cliente: _clienteDe(c.idCliente),
        ),
      ),
    );
    _cargar();
  }

  Future<void> _eliminar(Contrato c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar contrato'),
        content: Text('¿Eliminar el contrato "${c.contrato ?? c.id}"?\n'
            'También se eliminarán sus tarifas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/contratos/${c.id}');
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Contratos',
            subtitulo: '${_contratos.length} contratos entre agentes y clientes · '
                '${_visibles.length} visibles',
            icono: Icons.description_outlined,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por contrato, agente o cliente…',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => _filtro = v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _idAgenteFiltro,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Agente',
                      prefixIcon: Icon(Icons.groups_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
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
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'todos', label: Text('Todos')),
                    ButtonSegment(value: 'activos', label: Text('Activos')),
                    ButtonSegment(value: 'inactivos', label: Text('Inactivos')),
                  ],
                  selected: {_estadoFiltro},
                  onSelectionChanged: (s) =>
                      setState(() => _estadoFiltro = s.first),
                ),
                if (_idAgenteFiltro != null || _estadoFiltro != 'todos')
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _idAgenteFiltro = null;
                      _estadoFiltro = 'todos';
                      _filtro = '';
                    }),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Limpiar filtros'),
                  ),
              ],
            ),
          ),
          Expanded(child: _lista()),
        ],
      ),
      floatingActionButton: Sesion.I.puedeEditar
          ? FloatingActionButton.extended(
              onPressed: () => _clientes.isEmpty ? null : _nuevo(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo contrato'),
            )
          : null,
    );
  }

  Widget _lista() {
    if (_cargando && _contratos.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    if (_visibles.isEmpty) {
      return EstadoVacio(
        mensaje: _contratos.isEmpty ? 'Sin contratos todavía' : 'Nada coincide con el filtro',
        icono: Icons.description_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _visibles.length,
        itemBuilder: (_, i) {
          final c = _visibles[i];
          return _FichaContrato(
            contrato: c,
            agente: _agenteDe(c.idAgente),
            cliente: _clienteDe(c.idCliente),
            alAbrir: () => _abrir(c),
            alEliminar: Sesion.I.puedeEditar ? () => _eliminar(c) : null,
          );
        },
      ),
    );
  }
}

class _FichaContrato extends StatelessWidget {
  final Contrato contrato;
  final Agente? agente;
  final Cliente? cliente;
  final VoidCallback alAbrir;
  final VoidCallback? alEliminar;

  const _FichaContrato({
    required this.contrato,
    required this.agente,
    required this.cliente,
    required this.alAbrir,
    this.alEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: alAbrir,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 20, color: tema.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      contrato.contrato?.isNotEmpty == true ? contrato.contrato! : 'Contrato #${contrato.id}',
                      style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  EstadoChip(contrato.activo ? 'activo' : 'inactivo',
                      contrato.activo ? const Color(0xFF2E7D32) : tema.colorScheme.outline),
                  if (alEliminar != null)
                    IconButton(
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                      onPressed: alEliminar,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _EtiquetaValor(
                      etiqueta: 'Agente',
                      valor: agente?.etiqueta ?? 'Agente ${contrato.idAgente}',
                      icono: Icons.bolt_outlined,
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 16, color: tema.colorScheme.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EtiquetaValor(
                      etiqueta: 'Cliente',
                      valor: cliente?.etiqueta ?? 'Cliente ${contrato.idCliente}',
                      icono: Icons.people_alt_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (contrato.inicio != null)
                    _MiniDato(icono: Icons.event_available_outlined, texto: 'Inicio ${fmtFecha(contrato.inicio)}'),
                  if (contrato.fin != null)
                    _MiniDato(icono: Icons.event_busy_outlined, texto: 'Fin ${fmtFecha(contrato.fin)}'),
                  if (contrato.interes != null)
                    _MiniDato(icono: Icons.percent, texto: 'Interés ${fmtNumero(contrato.interes!)}%'),
                  if (contrato.garantia?.isNotEmpty == true)
                    _MiniDato(icono: Icons.verified_outlined, texto: contrato.garantia!),
                  if (contrato.indexacion?.isNotEmpty == true)
                    _MiniDato(icono: Icons.trending_up, texto: contrato.indexacion!),
                  if (contrato.medicion?.isNotEmpty == true)
                    _MiniDato(icono: Icons.speed_outlined, texto: contrato.medicion!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EtiquetaValor extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final IconData icono;
  const _EtiquetaValor({required this.etiqueta, required this.valor, required this.icono});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: tema.textTheme.labelSmall?.copyWith(color: tema.colorScheme.outline)),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(icono, size: 16, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(valor,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniDato extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _MiniDato({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: tema.colorScheme.outline),
          const SizedBox(width: 5),
          Text(texto, style: tema.textTheme.labelSmall),
        ],
      ),
    );
  }
}
