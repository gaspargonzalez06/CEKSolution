import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/abrir_url.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/formulario.dart';
import '../widgets/graficas.dart';
import '../widgets/proceso_dialog.dart';
import 'facturas_lote_screen.dart';
import 'historico_facturas_screen.dart';

class FacturasScreen extends StatefulWidget {
  const FacturasScreen({super.key});

  @override
  State<FacturasScreen> createState() => _FacturasScreenState();
}

class _FacturasScreenState extends State<FacturasScreen> {
  List<Factura> _items = [];
  List<Cliente> _clientes = [];
  List<Agente> _agentes = [];
  bool _cargando = true;
  String? _error;
  final _busqueda = TextEditingController();
  int? _filtroAgente;
  int? _filtroCliente;
  String? _filtroEstado;
  String? _filtroPeriodo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final f = await Api.I.get('/facturas') as List;
      final c = await Api.I.get('/clientes') as List;
      List<dynamic> a = const [];
      try {
        a = await Api.I.get('/agentes') as List;
      } catch (_) {
        // Sin agentes se puede seguir facturando (lista completa de clientes).
      }
      setState(() {
        _items = f.map((e) => Factura.fromJson(Map<String, dynamic>.from(e))).toList();
        _clientes = c.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
        _agentes = a.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _generar() async {
    final creada = await showDialog<Factura>(
      context: context,
      builder: (_) => _GenerarDialog(
        clientes: _clientes,
        agentes: _agentes,
        agenteInicial: _filtroAgente,
        periodoInicial: _filtroPeriodo,
      ),
    );
    if (creada != null) {
      _cargar();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FacturaDetalleScreen(id: creada.id)),
        );
      }
    }
  }

  Future<void> _ver(Factura f) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FacturaDetalleScreen(id: f.id)),
    );
    _cargar();
  }

  void _abrirHtml(Factura f) {
    abrirEnNavegador('${AppConfig.apiBase}/facturas/${f.id}/html');
  }

  Future<void> _eliminar(Factura f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text('¿Eliminar la factura ${f.numero}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/facturas/${f.id}');
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Cliente? _cliente(int id) {
    for (final c in _clientes) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<String> get _periodosFactura {
    final set = <String>{for (final f in _items) f.periodo};
    final lista = set.toList()..sort((a, b) => b.compareTo(a));
    return lista;
  }

  List<String> get _estadosFactura {
    final set = <String>{for (final f in _items) f.estado};
    final lista = set.toList()..sort();
    return lista;
  }

  bool get _hayFiltros =>
      _busqueda.text.trim().isNotEmpty ||
      _filtroAgente != null ||
      _filtroCliente != null ||
      _filtroEstado != null ||
      _filtroPeriodo != null;

  List<Factura> get _filtradas {
    final q = _busqueda.text.trim().toLowerCase();
    return _items.where((f) {
      if (_filtroCliente != null && f.idCliente != _filtroCliente) return false;
      if (_filtroAgente != null) {
        final c = _cliente(f.idCliente);
        if (c?.idAgente != _filtroAgente) return false;
      }
      if (_filtroEstado != null && f.estado != _filtroEstado) return false;
      if (_filtroPeriodo != null && f.periodo != _filtroPeriodo) return false;
      if (q.isNotEmpty) {
        final texto =
            '${f.numero} ${f.clienteNombre ?? ''} ${f.periodo} ${f.estado}'
                .toLowerCase();
        if (!texto.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void _limpiarFiltros() {
    _busqueda.clear();
    setState(() {
      _filtroAgente = null;
      _filtroCliente = null;
      _filtroEstado = null;
      _filtroPeriodo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _filtradas;
    final total = visibles.fold<double>(0, (a, f) => a + f.total);
    if (_cargando && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);

    final clientesFiltrados = _filtroAgente == null
        ? _clientes
        : _clientes.where((c) => c.idAgente == _filtroAgente).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Facturas',
            subtitulo: '${visibles.length} de ${_items.length} facturas · '
                '${fmtMoneda(total)} facturado',
            icono: Icons.receipt_long_outlined,
            acciones: [
              if (Sesion.I.puedeEditar) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoricoFacturasScreen()),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Histórico'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _generarLote,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Generar en lote'),
                ),
              ],
            ],
          ),
          _filtros(clientesFiltrados),
          Expanded(
            child: visibles.isEmpty
                ? EstadoVacio(
                    mensaje: _hayFiltros
                        ? 'No hay facturas con esos filtros'
                        : 'No hay facturas generadas',
                    icono: Icons.receipt_long,
                  )
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final f = visibles[i];
                      final c = _cliente(f.idCliente);
                      return Card(
                        child: ListTile(
                          onTap: () => _ver(f),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                          title: Text(f.numero, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            f.clienteNombre ?? 'Cliente ${f.idCliente}',
                            if (c?.agenteNombre != null) 'Agente: ${c!.agenteNombre}',
                            'Período ${f.periodo}',
                          ].join(' · ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtMoneda(f.total),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  EstadoChip(
                                      f.estado,
                                      f.estado == 'pagada'
                                          ? const Color(0xFF12B886)
                                          : f.estado == 'anulada'
                                              ? Colors.grey
                                              : const Color(0xFFF0A020)),
                                ],
                              ),
                              IconButton(
                                  tooltip: 'Ver / imprimir',
                                  onPressed: () => _abrirHtml(f),
                                  icon: const Icon(Icons.picture_as_pdf_outlined)),
                              if (Sesion.I.esAdmin)
                                IconButton(
                                    tooltip: 'Eliminar',
                                    onPressed: () => _eliminar(f),
                                    icon: const Icon(Icons.delete_outline)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: Sesion.I.puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _nuevaFactura,
              icon: const Icon(Icons.add),
              label: const Text('Generar factura'),
            )
          : null,
    );
  }

  Widget _filtros(List<Cliente> clientesFiltrados) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 270,
                child: TextField(
                  controller: _busqueda,
                  decoration: const InputDecoration(
                    labelText: 'Buscar',
                    hintText: 'Número, cliente, período…',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 225,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('fac-agente-$_filtroAgente'),
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
                      DropdownMenuItem<int?>(value: a.id, child: Text(a.etiqueta)),
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
                  },
                ),
              ),
              SizedBox(
                width: 235,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('fac-cliente-$_filtroAgente-$_filtroCliente'),
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
                  onChanged: (v) => setState(() => _filtroCliente = v),
                ),
              ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('fac-estado-$_filtroEstado'),
                  initialValue: _estadosFactura.contains(_filtroEstado)
                      ? _filtroEstado
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    isDense: true,
                    prefixIcon: Icon(Icons.flag_outlined, size: 19),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todos')),
                    for (final e in _estadosFactura)
                      DropdownMenuItem<String?>(value: e, child: Text(e)),
                  ],
                  onChanged: (v) => setState(() => _filtroEstado = v),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('fac-periodo-$_filtroPeriodo'),
                  initialValue: _periodosFactura.contains(_filtroPeriodo)
                      ? _filtroPeriodo
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Período',
                    isDense: true,
                    prefixIcon: Icon(Icons.event_outlined, size: 19),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todos')),
                    for (final p in _periodosFactura)
                      DropdownMenuItem<String?>(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => _filtroPeriodo = v),
                ),
              ),
              if (_hayFiltros)
                TextButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Limpiar'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_filtradas.length} factura(s) con los filtros actuales',
            style: tema.textTheme.bodySmall
                ?.copyWith(color: tema.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  void _nuevaFactura() {
    if (_clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero cree un cliente para poder facturar')),
      );
      return;
    }
    _generar();
  }

  /// Factura los clientes de un agente de una vez (elijo agente, se listan sus
  /// clientes con checks) y muestra el resultado con la grafica de consumo.
  Future<void> _generarLote() async {
    if (_clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero cree un cliente para poder facturar')),
      );
      return;
    }
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _GenerarLoteDialog(agentes: _agentes),
    );
    if (res == null || !mounted) return;
    _cargar();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacturasLoteScreen(
          periodo: res['periodo'] as String,
          creadas: (res['creadas'] as List).cast<Factura>(),
          omitidas: (res['omitidas'] as List).cast<Map<String, dynamic>>(),
          errores: (res['errores'] as List).cast<Map<String, dynamic>>(),
        ),
      ),
    );
  }
}

class _GenerarDialog extends StatefulWidget {
  final List<Cliente> clientes;
  final List<Agente> agentes;

  /// Agente y período preseleccionados (vienen de los filtros de la lista de
  /// facturas).  Si el agente es nulo, el formulario arranca en "Todos los
  /// agentes" para poder elegir cualquier cliente directamente.
  final int? agenteInicial;
  final String? periodoInicial;

  const _GenerarDialog({
    required this.clientes,
    this.agentes = const [],
    this.agenteInicial,
    this.periodoInicial,
  });

  @override
  State<_GenerarDialog> createState() => _GenerarDialogState();
}

class _GenerarDialogState extends State<_GenerarDialog> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  int? _idAgente;
  List<Cliente> _clientesFiltrados = [];
  bool _cargandoClientes = false;
  int? _idCliente;
  late int _anio;
  late int _mes; // 1..12
  String _modo = 'redondo'; // 'redondo' | 'corte'
  int _diaCorte = 24;
  final _precio = TextEditingController();
  final _consumo = TextEditingController();
  final _itbms = TextEditingController(text: '0');
  final _dter = TextEditingController();
  final _obs = TextEditingController();
  bool _incluirDte = true;
  bool _incluirGrafica = true;
  bool _grafDiaria = true;
  bool _grafCosto = true;
  bool _grafHistorico = true;
  bool _enviando = false;
  bool _cargandoPrecio = false;
  String? _tarifa;
  bool _aplicarDescuento = false;
  final _descuento = TextEditingController();
  bool _aplicarOtrosCargos = false;
  final List<_OtroCargo> _otrosCargos = [];
  // true si el usuario escribio el consumo a mano (no se sobreescribe al
  // cambiar de cliente / periodo; si es auto-rellenado si se actualiza).
  bool _consumoManual = false;

  @override
  void initState() {
    super.initState();
    // Por defecto el mes anterior: es el que normalmente ya tiene publicada la
    // liquidación del CND (el mes calendario suele estar vacío y parecía que no
    // había datos que facturar).
    final ahora = DateTime.now();
    final prev = DateTime(ahora.year, ahora.month - 1, 1);
    _anio = prev.year;
    _mes = prev.month;
    if (widget.periodoInicial != null && widget.periodoInicial!.length >= 6) {
      _anio = int.tryParse(widget.periodoInicial!.substring(0, 4)) ?? _anio;
      _mes = int.tryParse(widget.periodoInicial!.substring(4, 6)) ?? _mes;
    }
    // Jerarquía Todos -> agente -> cliente.  Se respeta el agente filtrado en
    // la lista; si no hay filtro arranca en "Todos los agentes" para no caer en
    // el primer agente (que puede no tener clientes y confundir).
    _idAgente = widget.agenteInicial;
    if (_idAgente != null) {
      _cargarClientesDelAgente();
    } else {
      _clientesFiltrados = widget.clientes;
      _idCliente = widget.clientes.isEmpty ? null : widget.clientes.first.id;
      _cargarPrecio();
    }
  }

  /// Lista los clientes del agente elegido (via contratos del agente).
  Future<void> _cargarClientesDelAgente() async {
    final id = _idAgente;
    if (id == null) return;
    setState(() => _cargandoClientes = true);
    try {
      final r = await Api.I.get('/agentes/$id/clientes') as List;
      if (!mounted) return;
      final lista =
          r.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
      setState(() {
        _clientesFiltrados = lista;
        _idCliente = lista.isEmpty ? null : lista.first.id;
      });
      _cargarPrecio();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _cargandoClientes = false);
    }
  }

  /// Toma el precio/tarifa vigentes del contrato (tabla `precios`, sistema viejo)
  /// para no escribir un precio fijo. Si falla, se deja vacio y el backend lo
  /// resuelve igualmente al generar la factura.
  Future<void> _cargarPrecio() async {
    final id = _idCliente;
    if (id == null) return;
    setState(() => _cargandoPrecio = true);
    try {
      final r = Map<String, dynamic>.from(
          await Api.I.get('/clientes/$id/precio?periodo=$_periodo') as Map);
      if (!mounted) return;
      setState(() {
        final p = (r['precio'] as num?)?.toDouble();
        _precio.text = p == null ? '' : p.toStringAsFixed(4);
        _tarifa = r['tarifa'] as String?;
        // Consumo medido del periodo (si existe): evita facturar en 0 por
        // dejar el campo vacio; el usuario puede editarlo despues. Si el
        // usuario ya escribio un consumo a mano no se sobreescribe.
        final consumo = (r['consumo_mwh'] as num?)?.toDouble();
        if (consumo != null && !_consumoManual) {
          _consumo.text = consumo.toStringAsFixed(6);
        }
      });
    } catch (_) {
      // silencioso: el backend resuelve el precio del contrato al generar
    } finally {
      if (mounted) setState(() => _cargandoPrecio = false);
    }
  }

  @override
  void dispose() {
    _precio.dispose();
    _consumo.dispose();
    _itbms.dispose();
    _dter.dispose();
    _obs.dispose();
    _descuento.dispose();
    for (final c in _otrosCargos) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleOtrosCargos(bool v) {
    setState(() {
      _aplicarOtrosCargos = v;
      if (v && _otrosCargos.isEmpty) _otrosCargos.add(_OtroCargo());
    });
  }

  void _agregarOtroCargo() => setState(() => _otrosCargos.add(_OtroCargo()));

  void _quitarOtroCargo(int i) {
    setState(() {
      _otrosCargos.removeAt(i).dispose();
      if (_otrosCargos.isEmpty) _aplicarOtrosCargos = false;
    });
  }

  double get _descuentoVal =>
      _aplicarDescuento ? (double.tryParse(_descuento.text.trim()) ?? 0) : 0;

  double get _otrosCargosTotal {
    if (!_aplicarOtrosCargos) return 0;
    var s = 0.0;
    for (final c in _otrosCargos) {
      s += double.tryParse(c.monto.text.trim()) ?? 0;
    }
    return s;
  }

  double get _baseEstimado =>
      _consumoMwh * 1000 * _precioVal + _dterVal - _descuentoVal + _otrosCargosTotal;

  String get _periodo => '$_anio${_mes.toString().padLeft(2, '0')}';

  (DateTime, DateTime) get _rango {
    if (_modo == 'redondo') {
      return (DateTime(_anio, _mes, 1), DateTime(_anio, _mes + 1, 0));
    }
    return (DateTime(_anio, _mes - 1, _diaCorte), DateTime(_anio, _mes, _diaCorte));
  }

  int get _dias {
    final (ini, fin) = _rango;
    return fin.difference(ini).inDays;
  }

  String _f(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get _rangoTexto {
    final (ini, fin) = _rango;
    final pref = _modo == 'redondo' ? 'Mes completo' : 'Ciclo (corte día $_diaCorte)';
    return '$pref: ${_f(ini)} al ${_f(fin)} · $_dias días';
  }

  double get _precioVal => double.tryParse(_precio.text.trim()) ?? 0.0775;
  double get _consumoMwh => double.tryParse(_consumo.text.trim()) ?? 0;
  double get _itbmsPct => double.tryParse(_itbms.text.trim()) ?? 0;
  double get _dterVal => double.tryParse(_dter.text.trim()) ?? 0;

  Agente? get _agenteActual {
    if (_idAgente != null) {
      for (final a in widget.agentes) {
        if (a.id == _idAgente) return a;
      }
    }
    // En modo "Todos los agentes", el agente emisor se deduce del contrato del
    // cliente elegido (el backend hace lo mismo al generar).
    if (_idCliente != null) {
      for (final c in widget.clientes) {
        if (c.id == _idCliente && c.idAgente != null) {
          for (final a in widget.agentes) {
            if (a.id == c.idAgente) return a;
          }
        }
      }
    }
    return null;
  }

  /// Texto del item del selector de cliente.  En "Todos los agentes" se agrega
  /// el agente para respetar la jerarquía sin perder de vista a quién pertenece.
  String _textoCliente(Cliente c) {
    if (_idAgente != null) return c.etiqueta;
    final ag = c.agenteNombre;
    return (ag == null || ag.isEmpty) ? c.etiqueta : '${c.etiqueta} · $ag';
  }

  /// Detecta datos incompletos y ofrece descargarlos del CND con la pantalla
  /// animada de etapas. Al terminar recarga precio/consumo del contrato.
  Future<void> _descargarDatosAgente() async {
    final ag = _agenteActual;
    if (ag == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un agente para descargar sus datos')),
      );
      return;
    }
    final ok = await abrirProcesoDialog(
      context,
      titulo: 'Descargar datos · ${ag.etiqueta} · $_periodo',
      periodo: _periodo,
      codigos: [ag.codigo],
      modo: 'completo',
    );
    if (ok == true) {
      await _cargarPrecio();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Datos descargados. Revise el consumo y genere la factura.'),
        ));
      }
    }
  }

  Future<void> _enviar() async {
    if (_idCliente == null) return;
    // Detección de datos incompletos: si no hay consumo medido ni capturado,
    // se ofrece descargar/transformar los datos del agente en vez de facturar 0.
    if (_consumoMwh == 0) {
      final opcion = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF0A020)),
              SizedBox(width: 8),
              Text('Datos incompletos'),
            ],
          ),
          content: Text(
            'No hay consumo medido para este cliente en $_periodo. '
            'Puede descargar y transformar los datos del CND ahora '
            '${_agenteActual != null ? 'para ${_agenteActual!.etiqueta} ' : ''}'
            'o continuar: la factura se genera igual con consumo 0 y los '
            'cargos del mercado (DTE) se calculan con los datos publicados.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'cancelar'),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'igual'),
                child: const Text('Generar igual')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'descargar'),
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Descargar datos')),
          ],
        ),
      );
      if (opcion == null || opcion == 'cancelar') return;
      if (opcion == 'descargar') {
        await _descargarDatosAgente();
        return;
      }
    }
    final obsUsuario = _obs.text.trim();
    final obs = obsUsuario.isEmpty ? _rangoTexto : '$_rangoTexto · $obsUsuario';
    setState(() => _enviando = true);
    try {
      final res = await Api.I.post('/facturas/generar', {
        'id_cliente': _idCliente,
        if (_idAgente != null) 'id_agente': _idAgente,
        'periodo': _periodo,
        if (_precio.text.trim().isNotEmpty)
          'precio_kwh': double.tryParse(_precio.text.trim()),
        if (_consumo.text.trim().isNotEmpty)
          'consumo_mwh': double.tryParse(_consumo.text.trim()),
        'itbms_pct': double.tryParse(_itbms.text.trim()) ?? 0,
        if (_dter.text.trim().isNotEmpty) 'dter_monto': double.tryParse(_dter.text.trim()),
        'dias_lectura': _dias,
        'incluir_dte': _incluirDte,
        if (_aplicarDescuento && _descuento.text.trim().isNotEmpty)
          'descuento': double.tryParse(_descuento.text.trim()),
        if (_aplicarOtrosCargos)
          'otros_cargos': [
            for (final c in _otrosCargos)
              if (c.nombre.text.trim().isNotEmpty && c.monto.text.trim().isNotEmpty)
                {
                  'nombre': c.nombre.text.trim(),
                  'monto': double.tryParse(c.monto.text.trim()) ?? 0,
                }
          ],
        'observaciones': obs,
        'graficas': [
          if (_incluirGrafica && _grafDiaria) 'diario',
          if (_incluirGrafica && _grafCosto) 'costo',
          if (_incluirGrafica && _grafHistorico) 'historico',
        ].join(','),
      });
      if (!mounted) return;
      Navigator.pop(context, Factura.fromJson(Map<String, dynamic>.from(res)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.bolt, color: tema.colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Generar factura',
                            style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text(_rangoTexto,
                            style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.agentes.isNotEmpty) ...[
                    DropdownButtonFormField<int?>(
                      key: ValueKey('gen-agente-$_idAgente'),
                      initialValue: _idAgente,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Agente emisor',
                          prefixIcon: Icon(Icons.business_outlined),
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Todos los agentes')),
                        for (final a in widget.agentes)
                          DropdownMenuItem<int?>(
                              value: a.id, child: Text(a.etiqueta)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _idAgente = v;
                          _idCliente = null;
                          if (v == null) {
                            _clientesFiltrados = widget.clientes;
                            _idCliente = widget.clientes.isEmpty
                                ? null
                                : widget.clientes.first.id;
                          } else {
                            _clientesFiltrados = [];
                          }
                        });
                        if (v == null) {
                          _cargarPrecio();
                        } else {
                          _cargarClientesDelAgente();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<int>(
                    initialValue: _idCliente,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: 'Cliente',
                        prefixIcon: const Icon(Icons.people_alt_outlined),
                        helperText: _cargandoClientes
                            ? 'Cargando clientes...'
                            : '${_clientesFiltrados.length} cliente(s)'
                                '${_idAgente == null ? ' · elige uno para fijar el agente' : ''}',
                        border: const OutlineInputBorder()),
                    items: [
                      for (final c in _clientesFiltrados)
                        DropdownMenuItem(
                            value: c.id, child: Text(_textoCliente(c))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _idCliente = v;
                        // Cambio de cliente: el consumo manual del anterior
                        // no aplica; se autorellena con el nuevo.
                        _consumoManual = false;
                        _consumo.clear();
                      });
                      _cargarPrecio();
                    },
                  ),
                  const SizedBox(height: 16),
                  _bloque('Período', Icons.calendar_month_outlined, [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _mes,
                            decoration: const InputDecoration(
                                labelText: 'Mes', border: OutlineInputBorder()),
                            items: [
                              for (var m = 1; m <= 12; m++)
                                DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                            ],
                            onChanged: (v) {
                              setState(() => _mes = v ?? _mes);
                              _cargarPrecio();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _anio,
                            decoration: const InputDecoration(
                                labelText: 'Año', border: OutlineInputBorder()),
                            items: [
                              for (final a in _anios())
                                DropdownMenuItem(value: a, child: Text('$a')),
                            ],
                            onChanged: (v) {
                              setState(() => _anio = v ?? _anio);
                              _cargarPrecio();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'redondo',
                            label: Text('Mes redondo'),
                            icon: Icon(Icons.calendar_month)),
                        ButtonSegment(
                            value: 'corte', label: Text('Corte'), icon: Icon(Icons.content_cut)),
                      ],
                      selected: {_modo},
                      onSelectionChanged: (sel) => setState(() => _modo = sel.first),
                    ),
                    if (_modo == 'corte') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _diaCorte,
                        decoration: const InputDecoration(
                            labelText: 'Día de corte',
                            helperText: 'El ciclo va de este día del mes anterior a este día',
                            border: OutlineInputBorder()),
                        items: [
                          for (var d = 1; d <= 28; d++)
                            DropdownMenuItem(value: d, child: Text('Día $d')),
                        ],
                        onChanged: (v) => setState(() => _diaCorte = v ?? _diaCorte),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  _bloque('Cargos', Icons.receipt_long_outlined, [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _precio,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                labelText: 'Precio B/./kWh',
                                helperText: _cargandoPrecio
                                    ? 'Cargando del contrato...'
                                    : (_tarifa == null
                                        ? 'Del contrato'
                                        : 'Tarifa $_tarifa (del contrato)'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _consumo,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) {
                              _consumoManual = true;
                              setState(() {});
                            },
                            decoration: const InputDecoration(
                                labelText: 'Consumo MWh',
                                helperText: 'Opcional (hereda el último)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    if (!_cargandoPrecio && _idCliente != null && _consumoMwh == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFF0A020), size: 18),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Sin consumo medido para el período. Puede descargar '
                                'los datos del agente ahora.',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                            TextButton.icon(
                              onPressed:
                                  _enviando ? null : _descargarDatosAgente,
                              icon: const Icon(
                                  Icons.cloud_download_outlined,
                                  size: 16),
                              label: const Text('Descargar'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _itbms,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'ITBMS %', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _dter,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'DTER mes anterior',
                                helperText: 'Opcional (fn_DTER_Mes)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.account_balance_outlined,
                          color: _incluirDte ? tema.colorScheme.primary : tema.colorScheme.outline),
                      title: const Text('Incluir cargos del mercado (DTE)'),
                      subtitle: const Text('Suma los costos reales publicados por el CND'),
                      value: _incluirDte,
                      onChanged: (v) => setState(() => _incluirDte = v),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _bloque('Descuento y otros cargos', Icons.tune, [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.percent,
                          color: _aplicarDescuento
                              ? tema.colorScheme.primary
                              : tema.colorScheme.outline),
                      title: const Text('Aplicar descuento por pronto pago'),
                      subtitle: const Text('Se resta del subtotal'),
                      value: _aplicarDescuento,
                      onChanged: (v) => setState(() => _aplicarDescuento = v),
                    ),
                    if (_aplicarDescuento)
                      TextField(
                        controller: _descuento,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Descuento B/.', border: OutlineInputBorder()),
                      ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.add_card_outlined,
                          color: _aplicarOtrosCargos
                              ? tema.colorScheme.primary
                              : tema.colorScheme.outline),
                      title: const Text('Aplicar otros cargos'),
                      subtitle: const Text('Cargos adicionales con nombre y monto'),
                      value: _aplicarOtrosCargos,
                      onChanged: _toggleOtrosCargos,
                    ),
                    if (_aplicarOtrosCargos) ...[
                      for (var i = 0; i < _otrosCargos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _otrosCargos[i].nombre,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                      labelText: 'Nombre del cargo',
                                      border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _otrosCargos[i].monto,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                      labelText: 'Monto B/.', border: OutlineInputBorder()),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Quitar',
                                onPressed: () => _quitarOtroCargo(i),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _agregarOtroCargo,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar otro cargo'),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  _bloque('Gráficas en la factura (página 2)', Icons.bar_chart_outlined, [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.insert_chart_outlined,
                          color: _incluirGrafica
                              ? tema.colorScheme.primary
                              : tema.colorScheme.outline),
                      title: const Text('Incluir gráfica en la factura'),
                      subtitle: const Text('Se imprime en la página 2 del HTML/PDF'),
                      value: _incluirGrafica,
                      onChanged: (v) => setState(() => _incluirGrafica = v),
                    ),
                    if (_incluirGrafica) ...[
                      CheckboxListTile(
                        value: _grafDiaria,
                        onChanged: (v) => setState(() => _grafDiaria = v ?? false),
                        title: const Text('Gráfica diaria (consumo por día)'),
                        subtitle: const Text('Barras de todos los días del mes'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _grafCosto,
                        onChanged: (v) => setState(() => _grafCosto = v ?? false),
                        title: const Text('Gráfica de generación y costo promedio'),
                        subtitle: const Text('Puntos del Promedio CMS (B/./kWh)'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _grafHistorico,
                        onChanged: (v) => setState(() => _grafHistorico = v ?? false),
                        title: const Text('Gráfica histórica'),
                        subtitle: const Text('Barras de los últimos meses'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _obs,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Observaciones', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tema.colorScheme.primary.withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      children: [
                        _filaResumen('Consumo', '${_consumoMwh.toStringAsFixed(3)} MWh', tema),
                        _filaResumen('Energía (consumo × precio)',
                            fmtMoneda(_consumoMwh * 1000 * _precioVal), tema),
                        if (_dter.text.trim().isNotEmpty)
                          _filaResumen('DTER mes anterior', fmtMoneda(_dterVal), tema),
                        if (_descuentoVal != 0)
                          _filaResumen('Descuento por pronto pago',
                              fmtMoneda(-_descuentoVal), tema),
                        if (_otrosCargosTotal != 0)
                          _filaResumen('Otros cargos', fmtMoneda(_otrosCargosTotal), tema),
                        _filaResumen('ITBMS ${_itbmsPct.toStringAsFixed(0)}%',
                            fmtMoneda(_baseEstimado * _itbmsPct / 100), tema),
                        const Divider(height: 20),
                        _filaResumen(
                            'Total estimado',
                            fmtMoneda(_baseEstimado * (1 + _itbmsPct / 100)),
                            tema,
                            grande: true),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Estimado: no incluye los cargos del mercado (DTE) que se suman al generar.',
                            style: tema.textTheme.labelSmall
                                ?.copyWith(color: tema.colorScheme.outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _enviando ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bolt),
                    label: const Text('Generar factura'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<int> _anios() {
    final actual = DateTime.now().year;
    return [for (var a = actual - 4; a <= actual + 1; a++) a];
  }

  Widget _filaResumen(String etiqueta, String valor, ThemeData tema, {bool grande = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(etiqueta,
                style: TextStyle(
                    fontWeight: grande ? FontWeight.w700 : FontWeight.normal,
                    color: grande ? null : tema.colorScheme.outline)),
          ),
          Text(valor,
              style: TextStyle(
                  fontWeight: grande ? FontWeight.w800 : FontWeight.w600,
                  fontSize: grande ? 17 : null)),
        ],
      ),
    );
  }

  Widget _bloque(String titulo, IconData icono, List<Widget> hijos) =>
      SeccionFormulario(titulo: titulo, icono: icono, hijos: hijos);
}

class _OtroCargo {
  final TextEditingController nombre = TextEditingController();
  final TextEditingController monto = TextEditingController();

  void dispose() {
    nombre.dispose();
    monto.dispose();
  }
}

class FacturaDetalleScreen extends StatefulWidget {
  final int id;
  const FacturaDetalleScreen({super.key, required this.id});

  @override
  State<FacturaDetalleScreen> createState() => _FacturaDetalleScreenState();
}

class _FacturaDetalleScreenState extends State<FacturaDetalleScreen> {
  Factura? _factura;
  GraficoConsumo? _grafico;
  bool _cargando = true;
  String? _error;
  String _tipo = 'historico';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({String? tipo}) async {
    final t = tipo ?? _tipo;
    setState(() {
      _cargando = true;
      _error = null;
      if (tipo != null) _tipo = t;
    });
    try {
      final f = await Api.I.get('/facturas/${widget.id}');
      final g = await Api.I.get('/facturas/${widget.id}/consumo?tipo=$t');
      setState(() {
        _factura = Factura.fromJson(Map<String, dynamic>.from(f));
        _grafico = GraficoConsumo.fromJson(Map<String, dynamic>.from(g));
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_factura?.numero ?? 'Factura'),
          actions: [
            IconButton(
              tooltip: 'Abrir / imprimir (HTML)',
              onPressed: () {
                final gs = _factura?.graficas;
                final url = (gs != null && gs.trim().isNotEmpty)
                    ? '${AppConfig.apiBase}/facturas/${widget.id}/html?graficas=${Uri.encodeComponent(gs)}'
                    : '${AppConfig.apiBase}/facturas/${widget.id}/html?grafica=$_tipo';
                abrirEnNavegador(url);
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Factura'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Consumo'),
          ]),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorVista(error: _error!, alReintentar: _cargar)
                : TabBarView(children: [_paginaFactura(), _paginaConsumo()]),
      ),
    );
  }

  Widget _paginaFactura() {
    final f = _factura!;
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.numero, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(f.clienteNombre ?? 'Cliente',
                              style: tema.textTheme.bodyMedium),
                          Text('Período ${f.periodo}',
                              style: tema.textTheme.bodySmall
                                  ?.copyWith(color: tema.colorScheme.outline)),
                        ],
                      ),
                    ),
                    EstadoChip(f.estado, const Color(0xFFF0A020)),
                  ],
                ),
                const Divider(height: 28),
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    _dato('Consumo', '${(f.consumoMwh ?? 0).toStringAsFixed(3)} MWh'),
                    _dato('Precio', '${(f.precioKwh ?? 0).toStringAsFixed(4)} B/./kWh'),
                    _dato('Tarifa', f.tarifa ?? '—'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Detalle', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final d in f.detalles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.descripcion,
                            style: TextStyle(
                                fontWeight: d.esTotal ? FontWeight.w600 : FontWeight.w700,
                                color: d.esTotal ? null : tema.colorScheme.outline),
                          ),
                        ),
                        if (d.cantidad != null)
                          Text('${d.cantidad!.toStringAsFixed(3)} ${d.unidad ?? ""}   ',
                              style: TextStyle(color: tema.colorScheme.outline)),
                        SizedBox(
                          width: 110,
                          child: Text(
                            d.monto == null ? '' : fmtMoneda(d.monto!),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 28),
                _filaTotal('Subtotal', f.subtotal, tema),
                _filaTotal('ITBMS ${f.itbmsPct.toStringAsFixed(0)}%', f.itbms, tema),
                const SizedBox(height: 4),
                _filaTotal('TOTAL', f.total, tema, grande: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _filaTotal(String etiqueta, double valor, ThemeData tema, {bool grande = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(etiqueta,
                style: TextStyle(
                    fontWeight: grande ? FontWeight.w800 : FontWeight.w500,
                    fontSize: grande ? 16 : 14)),
          ),
          Text(fmtMoneda(valor),
              style: TextStyle(
                  fontWeight: grande ? FontWeight.w800 : FontWeight.w600,
                  fontSize: grande ? 18 : 14)),
        ],
      ),
    );
  }

  Widget _paginaConsumo() {
    final g = _grafico;
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gráficas de consumo',
                    style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Visualización por tipo de consulta (datos reales del sistema)',
                    style: tema.textTheme.bodySmall
                        ?.copyWith(color: tema.colorScheme.outline)),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'historico', label: Text('Histórico'), icon: Icon(Icons.calendar_month)),
                    ButtonSegment(
                        value: 'diario', label: Text('Diario'), icon: Icon(Icons.calendar_view_day)),
                    ButtonSegment(
                        value: 'costo', label: Text('Generación + costo'), icon: Icon(Icons.trending_up)),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (sel) async {
                    await _cargar(tipo: sel.first);
                  },
                ),
                const SizedBox(height: 20),
                if (g != null) ...[
                  Text(g.titulo,
                      style: tema.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(g.subtitulo,
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: tema.colorScheme.outline)),
                  const SizedBox(height: 16),
                  if (g.tipo == 'costo')
                    if (g.tieneLinea)
                      GraficaCombinadaFl(
                        barras: g.valores,
                        linea: g.linea!,
                        etiquetasX: g.ejeX,
                        etiquetaBarra: 'Consumo (kWh)',
                        etiquetaLinea: g.nombreLinea ?? 'Costo promedio (B/./kWh)',
                        altura: 260,
                        etiquetaCada: _etiquetaCada(g.ejeX.length),
                      )
                    else
                      GraficaLineas(
                        series: [
                          SerieLinea(
                            nombre: g.nombreSerie ?? 'Promedio CMS (B/./kWh)',
                            valores: g.valores,
                            color: const Color(0xFFF0A020),
                          )
                        ],
                        etiquetasX: g.ejeX,
                        altura: 260,
                        etiquetaCada: _etiquetaCada(g.ejeX.length),
                        curva: false,
                        mostrarPuntos: true,
                        radioPuntos: 4,
                        formatoValor: (v) => v.toStringAsFixed(4),
                      )
                  else
                    GraficaBarrasFl(
                      valores: g.valores,
                      etiquetasX: g.ejeX,
                      altura: 260,
                      etiquetaCada: _etiquetaCada(g.ejeX.length),
                      color: const Color(0xFF0B6E4F),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _etiquetaCada(int n) {
    if (n <= 12) return 1;
    if (n <= 20) return 2;
    if (n <= 30) return 3;
    return 4;
  }
}

/// Dialogo para emitir la factura del mismo periodo a los clientes de un agente.
///
/// Primero se elige el agente; se listan sus clientes (via contratos del
/// agente) con checks y "seleccionar todos" (tristate). Al generar llama a
/// `/facturas/generar-lote` con el agente y los clientes marcados, y devuelve
/// el resultado para mostrar las facturas con su grafica.
class _GenerarLoteDialog extends StatefulWidget {
  final List<Agente> agentes;
  const _GenerarLoteDialog({required this.agentes});

  @override
  State<_GenerarLoteDialog> createState() => _GenerarLoteDialogState();
}

class _GenerarLoteDialogState extends State<_GenerarLoteDialog> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  late int _anio;
  late int _mes;
  int? _idAgente;
  List<Cliente> _clientesAgente = [];
  bool _cargandoClientes = false;
  String? _errorClientes;
  final Set<int> _sel = {};
  final _itbms = TextEditingController(text: '0');
  bool _incluirDte = true;
  bool _omitirExistentes = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _anio = hoy.year;
    _mes = hoy.month;
    if (widget.agentes.isNotEmpty) {
      _idAgente = widget.agentes.first.id;
      _cargarClientesDelAgente();
    }
  }

  @override
  void dispose() {
    _itbms.dispose();
    super.dispose();
  }

  List<int> get _anios {
    final hoy = DateTime.now().year;
    return [for (var a = hoy - 2; a <= hoy + 1; a++) a];
  }

  String get _periodo => '$_anio${_mes.toString().padLeft(2, '0')}';

  /// Clientes del agente elegido (relacion real: contratos.id_agente).
  Future<void> _cargarClientesDelAgente() async {
    final id = _idAgente;
    if (id == null) return;
    setState(() {
      _cargandoClientes = true;
      _errorClientes = null;
      _sel.clear();
    });
    try {
      final r = await Api.I.get('/agentes/$id/clientes') as List;
      if (!mounted) return;
      final lista =
          r.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
      setState(() {
        _clientesAgente = lista;
        // Por defecto se facturan todos los clientes del agente.
        _sel.addAll(lista.map((c) => c.id));
      });
    } catch (e) {
      if (mounted) setState(() => _errorClientes = '$e');
    } finally {
      if (mounted) setState(() => _cargandoClientes = false);
    }
  }

  bool get _todosSeleccionados =>
      _clientesAgente.isNotEmpty && _sel.length == _clientesAgente.length;

  bool get _algunoSeleccionado => _sel.isNotEmpty && !_todosSeleccionados;

  void _toggleTodos(bool? v) {
    setState(() {
      if (v == true) {
        _sel.addAll(_clientesAgente.map((c) => c.id));
      } else {
        _sel.clear();
      }
    });
  }

  Future<void> _generar() async {
    if (_idAgente == null || _sel.isEmpty) return;
    setState(() => _enviando = true);
    try {
      final r = await Api.I.post('/facturas/generar-lote', {
        'periodo': _periodo,
        'id_agente': _idAgente,
        'id_clientes': _sel.toList(),
        'incluir_dte': _incluirDte,
        'itbms_pct': double.tryParse(_itbms.text.trim()) ?? 0,
        'omitir_existentes': _omitirExistentes,
      });
      final m = Map<String, dynamic>.from(r);
      final creadas = ((m['creadas'] as List?) ?? [])
          .map((e) => Factura.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final omitidas = ((m['omitidas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final errores = ((m['errores'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      Navigator.pop(context, {
        'periodo': _periodo,
        'creadas': creadas,
        'omitidas': omitidas,
        'errores': errores,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Agente? agenteSel;
    for (final a in widget.agentes) {
      if (a.id == _idAgente) {
        agenteSel = a;
        break;
      }
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.playlist_add_check, color: tema.colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Generar facturas en lote',
                            style: tema.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                            agenteSel == null
                                ? 'Elija el agente · período $_periodo'
                                : '${agenteSel.etiqueta} · período $_periodo',
                            style: tema.textTheme.bodySmall
                                ?.copyWith(color: tema.colorScheme.outline)),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed:
                          _enviando ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  if (widget.agentes.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      initialValue: _idAgente,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Agente emisor *',
                          prefixIcon: Icon(Icons.business_outlined),
                          border: OutlineInputBorder()),
                      items: [
                        for (final a in widget.agentes)
                          DropdownMenuItem(value: a.id, child: Text(a.etiqueta)),
                      ],
                      onChanged: _enviando
                          ? null
                          : (v) {
                              setState(() => _idAgente = v);
                              _cargarClientesDelAgente();
                            },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _mes,
                          decoration: const InputDecoration(
                              labelText: 'Mes', border: OutlineInputBorder()),
                          items: [
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem(value: m, child: Text(_meses[m - 1])),
                          ],
                          onChanged: (v) => setState(() => _mes = v ?? _mes),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _anio,
                          decoration: const InputDecoration(
                              labelText: 'Año', border: OutlineInputBorder()),
                          items: [
                            for (final a in _anios)
                              DropdownMenuItem(value: a, child: Text('$a')),
                          ],
                          onChanged: (v) => setState(() => _anio = v ?? _anio),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 115,
                        child: TextField(
                          controller: _itbms,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'ITBMS %', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _incluirDte,
                    onChanged: (v) => setState(() => _incluirDte = v ?? true),
                    title: const Text('Incluir cargos del DTE'),
                    subtitle: const Text(
                        'Suma los costos reales del mercado (tabla DTE)'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _omitirExistentes,
                    onChanged: (v) => setState(() => _omitirExistentes = v ?? true),
                    title: const Text('Omitir clientes que ya tienen factura'),
                    subtitle: const Text('Evita duplicar el mismo período'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const Divider(),
                  if (_cargandoClientes)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_errorClientes != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_errorClientes!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    )
                  else if (_clientesAgente.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Este agente no tiene clientes registrados'),
                    )
                  else ...[
                    CheckboxListTile(
                      tristate: true,
                      value: _todosSeleccionados
                          ? true
                          : (_algunoSeleccionado ? null : false),
                      onChanged: _toggleTodos,
                      title: Text(
                          'Seleccionar todos (${_clientesAgente.length} clientes)',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    for (final c in _clientesAgente)
                      CheckboxListTile(
                        value: _sel.contains(c.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sel.add(c.id);
                          } else {
                            _sel.remove(c.id);
                          }
                        }),
                        title: Text(c.etiqueta),
                        subtitle: Text(c.codigo),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_sel.length} seleccionados',
                        style: tema.textTheme.bodySmall
                            ?.copyWith(color: tema.colorScheme.outline)),
                  ),
                  OutlinedButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: (_sel.isEmpty || _enviando) ? null : _generar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bolt),
                    label: Text(_enviando
                        ? 'Generando...'
                        : 'Generar ${_sel.length} factura(s)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
