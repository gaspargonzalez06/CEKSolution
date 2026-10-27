import 'package:flutter/material.dart';

import '../services/abrir_url.dart';
import '../services/api.dart';
import '../config.dart';
import '../widgets/comunes.dart';

class ComercialesScreen extends StatefulWidget {
  const ComercialesScreen({super.key});

  @override
  State<ComercialesScreen> createState() => _ComercialesScreenState();
}

class _ComercialesScreenState extends State<ComercialesScreen> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  static const _reportes = [
    ('comercial', 'Reporte Comercial'),
    ('dter', 'Reporte Comercial DTER'),
    ('ley15', 'Subsidio Ley 15'),
    ('cobros', 'Facturación y Cobros'),
  ];

  String _tipo = 'comercial';
  List<Map<String, dynamic>> _agentes = [];
  String? _agente;
  int _annio = DateTime.now().year;
  int _mes = DateTime.now().month;

  Map<String, dynamic>? _data;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarAgentes();
  }

  Future<void> _cargarAgentes() async {
    try {
      final r = await Api.I.get('/comerciales/agentes') as List;
      setState(() {
        _agentes = r.map((e) => Map<String, dynamic>.from(e)).toList();
        if (_agentes.isNotEmpty) {
          _agente = _agentes.first['codigo'] as String?;
        }
      });
    } catch (e) {
      // sin agentes: la pantalla muestra el aviso
    }
  }

  Future<void> _consultar() async {
    if (_agente == null) return;
    setState(() {
      _cargando = true;
      _error = null;
      _data = null;
    });
    try {
      var url = '/comerciales/$_tipo?agente=${Uri.encodeQueryComponent(_agente!)}';
      if (_tipo == 'comercial') {
        url += '&periodo=$_annio${_mes.toString().padLeft(2, '0')}';
      } else {
        url += '&annio=$_annio&mes=$_mes';
      }
      final data = await Api.I.get(url);
      setState(() => _data = Map<String, dynamic>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String get _urlHtml {
    var url = '${AppConfig.apiBase}/comerciales/$_tipo/html?agente=${Uri.encodeQueryComponent(_agente ?? '')}';
    if (_tipo == 'comercial') {
      url += '&periodo=$_annio${_mes.toString().padLeft(2, '0')}';
    } else {
      url += '&annio=$_annio&mes=$_mes';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final anios = List.generate(DateTime.now().year - 2020, (i) => 2021 + i);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Reportes Comerciales',
            subtitulo: '${_reportes.firstWhere((r) => r.$1 == _tipo).$2}'
                ' · ${_meses[_mes - 1]} $_annio',
            icono: Icons.assessment_outlined,
            acciones: [
              FilledButton.icon(
                onPressed: _cargando ? null : _consultar,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Generar'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Tarjeta(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 220),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _agente,
                        decoration: const InputDecoration(
                          labelText: 'Agente (generador)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _agentes
                            .map((a) => DropdownMenuItem(
                                  value: a['codigo'] as String?,
                                  child: Text('${a['nombre']}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _agente = v),
                      ),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _mes,
                      decoration: const InputDecoration(
                        labelText: 'Mes',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                      ],
                      onChanged: (v) => setState(() => _mes = v ?? _mes),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _annio,
                      decoration: const InputDecoration(
                        labelText: 'Año',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final a in anios) DropdownMenuItem(value: a, child: Text('$a')),
                      ],
                      onChanged: (v) => setState(() => _annio = v ?? _annio),
                    ),
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String>(
                        initialValue: _tipo,
                        decoration: const InputDecoration(
                          labelText: 'Reporte',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final (k, t) in _reportes)
                            DropdownMenuItem(value: k, child: Text(t)),
                        ],
                        onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorVista(error: _error!, alReintentar: _consultar)
                    : _data == null
                        ? const EstadoVacio(
                            mensaje:
                                'Elige agente, mes, año y el reporte a generar. ',
                            icono: Icons.assessment_outlined)
                        : _resultado(),
          ),
        ],
      ),
    );
  }

  Widget _resultado() {
    final d = _data!;
    if ((d['lineas'] ?? const []) is List && (d['lineas'] as List).isEmpty) {
      return const EstadoVacio(mensaje: 'El generador no tiene transacciones en ese periodo.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Tarjeta(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(Icons.assessment_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d['nombre'] ?? d['generador']}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text('${d['titulo']} · ${d['mes'] ?? ''}'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._lineas(),
                const Divider(height: 24),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => abrirEnNavegador(_urlHtml),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimir / PDF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _lineas() {
    final d = _data!;
    final tipo = d['titulo'] as String? ?? '';
    final lineas = (d['lineas'] as List?) ?? const [];

    if (tipo.startsWith('REPORTE COMERCIAL') && !tipo.endsWith('DTER')) {
      return [
        _tabla(['Descripción', 'Débito', 'Crédito'],
            lineas.map((x) => [ (x['agrupacion'] ?? '') + (x['sub'] != 1 ? ' (ajuste)' : ''),
                               x['atributo'] == 'Debito' ? _d(x['valor']) : '',
                               x['atributo'] == 'Credito' ? _d(x['valor']) : '' ]).toList()),
        const SizedBox(height: 8),
        _totales({'Débitos': d['subtotal_debito'], 'Créditos': d['subtotal_credito'], 'Total neto': d['total_neto']}),
        if (d['precio_promedio_venta'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Precio promedio de venta Mercado Ocasional: ${_d(d['precio_promedio_venta'])} \$ / MWh'),
          ),
      ];
    }
    if (tipo.endsWith('DTER')) {
      return [
        _tabla(['Agrupación', 'Generador', 'Cliente', 'Atributo', 'Valor'],
            lineas.map((x) => [x['agrupacion'], x['agente'], x['cliente'], x['atributo'], _d(x['valor'])]).toList()),
        const SizedBox(height: 8),
        _totales({'Débitos': d['subtotal_debito'], 'Créditos': d['subtotal_credito'], 'Total neto': d['total_neto']}),
      ];
    }
    if (tipo.contains('LEY 15')) {
      return [
        _tabla(['Distribuidor', 'Contrato', 'Cliente', 'NIS', 'Factor', 'Importe'],
            lineas.map((x) => [x['distribuidor'], x['contrato'], x['cliente'],
                               (x['nis'] ?? '').toString(), _d(x['ley15']), _d(x['importe'])]).toList()),
        const SizedBox(height: 8),
        _totales({'Total importe': d['total_importe']}),
      ];
    }
    return [
      _tabla(['Agente', 'Descripción', 'Cantidad', 'Créditos', 'Débitos'],
          lineas.map((x) => [(x['transaccion'] == null ? (x['agente'] ?? '') : ''),
                             x['transaccion'] == null ? 'TOTAL' : x['transaccion'],
                             _d(x['cantidad'], 3), _d(x['creditos']), _d(x['debitos'])]).toList()),
      const SizedBox(height: 8),
      _totales({'Cantidad': d['total_cantidad'], 'Total créditos': d['total_creditos'], 'Total débitos': d['total_debitos']}),
    ];
  }

  String _d(dynamic v, [int dec = 2]) {
    if (v == null) return '';
    final n = double.tryParse(v.toString()) ?? 0.0;
    return n.toStringAsFixed(dec);
  }

  Widget _tabla(List<String> cabezas, List<List<dynamic>> filas) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: cabezas.map((c) => DataColumn(label: Text(c))).toList(),
        rows: filas
            .map((f) => DataRow(
                  cells: f.map((c) => DataCell(Text(c?.toString() ?? ' '))).toList(),
                ))
            .toList(),
      ),
    );
  }

  Widget _totales(Map<String, dynamic> items) {
    return Wrap(
      spacing: 14,
      children: items.entries
          .map((e) => Chip(label: Text('${e.key}: ${_d(e.value)}')))
          .toList(),
    );
  }
}
