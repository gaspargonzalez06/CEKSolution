import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import 'agente_form_dialog.dart';
import 'analisis_clientes_screen.dart';

class AgentesScreen extends StatefulWidget {
  const AgentesScreen({super.key});

  @override
  State<AgentesScreen> createState() => _AgentesScreenState();
}

class _AgentesScreenState extends State<AgentesScreen> {
  List<Agente> _agentes = [];
  List<Map<String, dynamic>> _consumo = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';
  bool _soloGestionados = true;

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
      final params = <String>[
        if (_filtro.isNotEmpty) 'q=${Uri.encodeQueryComponent(_filtro)}',
        _soloGestionados ? 'gestionado=true' : 'todos=true',
      ];
      final data = await Api.I.get('/agentes?${params.join('&')}') as List;
      // Indicadores de consumo por agente (solo para los gestionados).
      var consumo = <Map<String, dynamic>>[];
      if (_soloGestionados) {
        try {
          final d = Map<String, dynamic>.from(
              await Api.I.get('/dashboard/resumen') as Map);
          consumo = ((d['agentes_cards'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {
          // sin datos de consumo se muestra solo el listado
        }
      }
      setState(() {
        _agentes = data
            .map((e) => Agente.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _consumo = consumo;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final creado = await showDialog<bool>(
      context: context,
      builder: (_) => const AgenteFormDialog(),
    );
    if (creado == true) _cargar();
  }

  Future<void> _editar(Agente a) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => AgenteFormDialog(agente: a),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _eliminar(Agente a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar agente'),
        content: Text('Eliminar "${a.etiqueta}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/agentes/${a.id}');
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Agentes',
            subtitulo: _soloGestionados
                ? '${_agentes.length} agentes gestionados por CEK'
                : '${_agentes.length} agentes · incluye contrapartes del mercado',
            icono: Icons.groups_outlined,
            acciones: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Nuestros'),
                    icon: Icon(Icons.verified_outlined),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Todos'),
                    icon: Icon(Icons.public_outlined),
                  ),
                ],
                selected: {_soloGestionados},
                onSelectionChanged: (s) {
                  setState(() => _soloGestionados = s.first);
                  _cargar();
                },
              ),
            ],
          ),
          if (_soloGestionados && _consumo.isNotEmpty) _resumen(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o codigo...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) {
                _filtro = v.trim();
                _cargar();
              },
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
      floatingActionButton: Sesion.I.puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _nuevo,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo agente'),
            )
          : null,
    );
  }

  void _abrirAnalisis({int? idAgente}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AnalisisClientesScreen(
        idAgenteInicial: idAgente,
        comoRuta: true,
      ),
    ));
  }

  Widget _resumen() {
    final generadores = _agentes.where((a) => a.generador).length;
    final distribuidores = _agentes.where((a) => a.distribuidor).length;
    final conCred = _agentes.where((a) => a.tieneCredencial).length;
    final conConsumo =
        _consumo.where((c) => ((c['consumo'] as num?) ?? 0) > 0).toList();
    final maximo = conConsumo
        .map((c) => (c['consumo'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    final techo = maximo <= 0 ? 1.0 : maximo;
    final top = conConsumo.take(6).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Indicadores generales',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => _abrirAnalisis(),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: const Text('Análisis general'),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _indicador('Gestionados', '${_agentes.length}',
                    Icons.groups_outlined, const Color(0xFF0B6E4F)),
                _indicador('Generadores', '$generadores',
                    Icons.solar_power, const Color(0xFFF0A020)),
                _indicador('Distribuidores', '$distribuidores',
                    Icons.storefront_outlined, const Color(0xFF315C8A)),
                _indicador('Con credencial CND', '$conCred',
                    Icons.vpn_key_outlined, const Color(0xFF7C4DFF)),
              ],
            ),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Consumo del período por agente (MWh)',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 8),
              for (final c in top)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _abrirAnalisis(idAgente: c['id'] as int?),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text('${c['nombre'] ?? c['codigo']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, cc) {
                              final v = (c['consumo'] as num?)?.toDouble() ?? 0;
                              return Stack(
                                children: [
                                  Container(
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  Container(
                                    height: 14,
                                    width: (cc.maxWidth * (v / techo))
                                        .clamp(3.0, cc.maxWidth),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [
                                        Color(0xFF0B6E4F),
                                        Color(0xFF12B886),
                                      ]),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 84,
                          child: Text(
                            fmtNumero((c['consumo'] as num?) ?? 0,
                                decimales: 2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _indicador(
      String titulo, String valor, IconData icono, Color color) {
    return Container(
      width: 158,
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
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline)),
                Text(valor,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    if (_agentes.isEmpty) {
      return EstadoVacio(
        icono: _soloGestionados ? Icons.groups_outlined : Icons.search_off,
        mensaje: _soloGestionados
            ? 'Aun no hay agentes gestionados. Cree uno con el boton +.'
            : 'No se encontraron agentes con ese criterio.',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _agentes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final a = _agentes[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: a.generador
                    ? Colors.orange.shade100
                    : (a.distribuidor ? Colors.blue.shade100 : Colors.grey.shade200),
                child: Icon(
                  a.generador ? Icons.solar_power : (a.distribuidor ? Icons.storefront : Icons.business),
                  color: Colors.black87,
                ),
              ),
              title: Text(a.etiqueta),
              subtitle: Text('${a.codigo} · ${a.tipo}'
                  '${a.codigoCnd != null ? ' · CND: ${a.codigoCnd}' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.gestionado && !_soloGestionados)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: EstadoChip('Nuestro', Color(0xFF0B6E4F)),
                    ),
                  Tooltip(
                    message: a.tieneCredencial ? 'Con credenciales de portal' : 'Sin credenciales',
                    child: Icon(
                      a.tieneCredencial ? Icons.vpn_key : Icons.key_off,
                      color: a.tieneCredencial ? Colors.green : Colors.grey,
                    ),
                  ),
                  if (a.gestionado)
                    IconButton(
                      tooltip: 'Análisis de sus clientes',
                      icon: const Icon(Icons.insights_outlined),
                      onPressed: () => _abrirAnalisis(idAgente: a.id),
                    ),
                  if (Sesion.I.puedeEditar) ...[
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(a)),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _eliminar(a)),
                  ],
                ],
              ),
              onTap: Sesion.I.puedeEditar ? () => _editar(a) : null,
            ),
          );
        },
      ),
    );
  }
}
