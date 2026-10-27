import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/comunes.dart';

/// Facturas del sistema viejo (SQL Server / CEK). Solo lectura.
class HistoricoFacturasScreen extends StatefulWidget {
  const HistoricoFacturasScreen({super.key});

  @override
  State<HistoricoFacturasScreen> createState() => _HistoricoFacturasScreenState();
}

class _HistoricoFacturasScreenState extends State<HistoricoFacturasScreen> {
  List<FacturaHistorica> _items = [];
  List<Map<String, dynamic>> _resumen = [];
  bool _cargando = true;
  String? _error;
  int? _annio;
  final _generador = TextEditingController();
  final _cliente = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _generador.dispose();
    _cliente.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final q = <String>[];
      if (_annio != null) q.add('annio=$_annio');
      if (_generador.text.trim().isNotEmpty) {
        q.add('generador=${Uri.encodeQueryComponent(_generador.text.trim())}');
      }
      if (_cliente.text.trim().isNotEmpty) {
        q.add('cliente=${Uri.encodeQueryComponent(_cliente.text.trim())}');
      }
      final sufijo = q.isEmpty ? '' : '?${q.join('&')}';
      final lista = await Api.I.get('/facturas-historicas$sufijo') as List;
      setState(() {
        _items = lista
            .map((e) => FacturaHistorica.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
      if (_resumen.isEmpty) {
        final res = await Api.I.get('/facturas-historicas/resumen') as List;
        setState(() {
          _resumen = res.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<int> get _anios {
    final s = <int>{};
    for (final r in _resumen) {
      final a = r['annio'];
      if (a is int) s.add(a);
    }
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (a, f) => a + (f.valor ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Facturas históricas (sistema viejo)')),
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Histórico de facturación',
            subtitulo:
                '${_items.length} registros · ${fmtMoneda(total)} en la vista actual',
            icono: Icons.history,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _annio,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Año', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final a in _anios)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) {
                      setState(() => _annio = v);
                      _cargar();
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _generador,
                    decoration: const InputDecoration(
                        labelText: 'Generador (código)', isDense: true),
                    onSubmitted: (_) => _cargar(),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _cliente,
                    decoration: const InputDecoration(
                        labelText: 'Cliente (código)', isDense: true),
                    onSubmitted: (_) => _cargar(),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _cargar,
                  icon: const Icon(Icons.search),
                  label: const Text('Filtrar'),
                ),
              ],
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    if (_items.isEmpty) {
      return const EstadoVacio(
        mensaje: 'Sin facturas históricas. Importa el resultado de la consulta 5.',
        icono: Icons.history,
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final f = _items[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(f.generador?.isNotEmpty == true ? f.generador![0] : '?'),
              ),
              title: Text('${f.cliente ?? '—'} · ${f.contrato ?? '—'}'),
              subtitle: Text(
                '${f.generador ?? '—'} · ${f.periodo}'
                '${f.consumo != null ? ' · ${fmtNumero(f.consumo!, decimales: 1)} kWh' : ''}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtMoneda(f.valor ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (f.precio != null)
                    Text('${fmtNumero(f.precio!, decimales: 4)} /kWh',
                        style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
