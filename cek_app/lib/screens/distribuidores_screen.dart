import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import 'agente_form_dialog.dart';

/// Distribuidores = agentes con el flag distribuidor (agencias que venden luz).
class DistribuidoresScreen extends StatefulWidget {
  const DistribuidoresScreen({super.key});

  @override
  State<DistribuidoresScreen> createState() => _DistribuidoresScreenState();
}

class _DistribuidoresScreenState extends State<DistribuidoresScreen> {
  List<Agente> _items = [];
  bool _cargando = true;
  String? _error;
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
      final q = _soloGestionados ? '?gestionado=true' : '?todos=true';
      final data = await Api.I.get('/distribuidores$q') as List;
      setState(() => _items = data.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const AgenteFormDialog(endpoint: '/distribuidores'),
    );
    if (ok == true) _cargar();
  }

  Future<void> _editar(Agente a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AgenteFormDialog(agente: a, endpoint: '/distribuidores'),
    );
    if (ok == true) _cargar();
  }

  Future<void> _eliminar(Agente a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar distribuidor'),
        content: Text('¿Eliminar a "${a.etiqueta}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/distribuidores/${a.id}');
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);

    return Column(
      children: [
        EncabezadoSeccion(
          titulo: 'Distribuidores',
          subtitulo: _soloGestionados
              ? '${_items.length} agencias gestionadas por CEK'
              : '${_items.length} agencias · incluye contrapartes del mercado',
          icono: Icons.storefront_outlined,
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
            if (Sesion.I.puedeEditar)
              FilledButton.icon(
                onPressed: _nuevo,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo distribuidor'),
              ),
          ],
        ),
        Expanded(
          child: _items.isEmpty
              ? EstadoVacio(
                  icono: Icons.storefront,
                  mensaje: _soloGestionados
                      ? 'Aún no hay distribuidores gestionados.\nUse "Todos" para ver el mercado o cree uno.'
                      : 'No hay distribuidores.',
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final a = _items[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF315C8A).withValues(alpha: 0.12),
                            child: const Icon(Icons.storefront, color: Color(0xFF315C8A)),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(a.etiqueta,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              if (a.gestionado && !_soloGestionados)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: EstadoChip('Nuestro', Color(0xFF0B6E4F)),
                                ),
                            ],
                          ),
                          subtitle: Text([
                            a.codigo,
                            if (a.ruc != null && a.ruc!.isNotEmpty) 'RUC: ${a.ruc}',
                            if (a.tieneCredencial) 'Portal CND: ${a.usuarioPortal ?? "configurado"}',
                          ].join(' · ')),
                          trailing: Sesion.I.puedeEditar
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        tooltip: 'Editar',
                                        onPressed: () => _editar(a),
                                        icon: const Icon(Icons.edit_outlined)),
                                    if (Sesion.I.esAdmin)
                                      IconButton(
                                          tooltip: 'Eliminar',
                                          onPressed: () => _eliminar(a),
                                          icon: const Icon(Icons.delete_outline)),
                                  ],
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
