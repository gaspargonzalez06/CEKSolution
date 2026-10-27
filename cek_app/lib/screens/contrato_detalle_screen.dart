import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/formulario.dart';
import 'contrato_form_dialog.dart';

/// Detalle de un contrato: muestra sus condiciones y permite mantener las
/// tarifas (tabla Precios del sistema viejo).
class ContratoDetalleScreen extends StatefulWidget {
  final Contrato contrato;
  final Agente? agente;
  final Cliente? cliente;

  const ContratoDetalleScreen({
    super.key,
    required this.contrato,
    this.agente,
    this.cliente,
  });

  @override
  State<ContratoDetalleScreen> createState() => _ContratoDetalleScreenState();
}

class _ContratoDetalleScreenState extends State<ContratoDetalleScreen> {
  late Contrato _contrato;
  List<Precio> _precios = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contrato = widget.contrato;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await Api.I.get('/precios?id_contrato=${_contrato.id}') as List;
      setState(() {
        _precios = p.map((e) => Precio.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ContratoFormDialog(
        contrato: _contrato,
        agentes: [if (widget.agente != null) widget.agente!],
        clientes: [if (widget.cliente != null) widget.cliente!],
      ),
    );
    if (ok == true) {
      // recargar el contrato y sus precios
      try {
        final j = await Api.I.get('/contratos/${_contrato.id}');
        setState(() => _contrato = Contrato.fromJson(Map<String, dynamic>.from(j as Map)));
      } catch (_) {}
      _cargar();
    }
  }

  Future<void> _agregarPrecio() async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _DialogoPrecio(),
    );
    if (res == null) return;
    try {
      await Api.I.post('/precios', {...res, 'id_contrato': _contrato.id});
      _cargar();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _editarPrecio(Precio p) async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoPrecio(precio: p),
    );
    if (res == null) return;
    try {
      await Api.I.put('/precios/${p.id}', res);
      _cargar();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _borrarPrecio(Precio p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarifa'),
        content: const Text('¿Eliminar esta tarifa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/precios/${p.id}');
      _cargar();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final puedeEditar = Sesion.I.puedeEditar;
    return Scaffold(
      appBar: AppBar(
        title: Text(_contrato.contrato?.isNotEmpty == true ? _contrato.contrato! : 'Contrato #${_contrato.id}'),
        actions: [
          if (puedeEditar)
            IconButton(onPressed: _editar, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar contrato'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Entidad(
                  icono: Icons.bolt_outlined,
                  rol: 'Agente',
                  nombre: widget.agente?.etiqueta ?? 'Agente ${_contrato.idAgente}',
                ),
                const SizedBox(height: 10),
                _Entidad(
                  icono: Icons.people_alt_outlined,
                  rol: 'Cliente',
                  nombre: widget.cliente?.etiqueta ?? 'Cliente ${_contrato.idCliente}',
                ),
                const Divider(height: 24),
                _Dato('Inicio', _contrato.inicio == null ? '—' : fmtFecha(_contrato.inicio)),
                _Dato('Fin', _contrato.fin == null ? '—' : fmtFecha(_contrato.fin)),
                _Dato('Interés', _contrato.interes == null ? '—' : '${fmtNumero(_contrato.interes!)} %'),
                _Dato('Garantía', _contrato.garantia?.isNotEmpty == true ? _contrato.garantia! : '—'),
                _Dato('Indexación', _contrato.indexacion?.isNotEmpty == true ? _contrato.indexacion! : '—'),
                _Dato('Medición', _contrato.medicion?.isNotEmpty == true ? _contrato.medicion! : '—'),
                _Dato('Estado', _contrato.activo ? 'Activo' : 'Inactivo'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.attach_money, color: tema.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text('Tarifas / Precios',
                  style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (Sesion.I.puedeEditar)
                FilledButton.tonalIcon(
                  onPressed: _agregarPrecio,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            ErrorVista(error: _error!, alReintentar: _cargar)
          else if (_precios.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EstadoVacio(mensaje: 'Sin tarifas registradas', icono: Icons.attach_money),
            )
          else
            ..._precios.map(_filaPrecio),
        ],
      ),
    );
  }

  Widget _filaPrecio(Precio p) {
    final vigencia = [
      if (p.inicia != null) 'desde ${fmtFecha(p.inicia)}',
      if (p.termina != null) 'hasta ${fmtFecha(p.termina)}',
    ].join('  ·  ');
    final partes = [
      if (p.tarifa != null && p.tarifa!.isNotEmpty) 'Tarifa ${p.tarifa}',
      if (vigencia.isNotEmpty) vigencia,
      if (p.idAntiguo != null) 'Precio #${p.idAntiguo} (sistema viejo)',
    ];
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.attach_money)),
        title: Text(p.precio == null ? 'Precio sin definir' : '${fmtNumero(p.precio!, decimales: 4)} / kWh'),
        subtitle: Text(partes.join('\n')),
        isThreeLine: partes.length >= 3,
        trailing: Sesion.I.puedeEditar
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _editarPrecio(p),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _borrarPrecio(p),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _Entidad extends StatelessWidget {
  final IconData icono;
  final String rol;
  final String nombre;
  const _Entidad({required this.icono, required this.rol, required this.nombre});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tema.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icono, size: 20, color: tema.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rol,
                  style: tema.textTheme.labelSmall?.copyWith(color: tema.colorScheme.outline)),
              Text(nombre,
                  style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Dato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(etiqueta,
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
          ),
          Expanded(
            child: Text(valor,
                style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Dialogo para crear/editar una tarifa.
class _DialogoPrecio extends StatefulWidget {
  final Precio? precio;
  const _DialogoPrecio({this.precio});

  @override
  State<_DialogoPrecio> createState() => _DialogoPrecioState();
}

class _DialogoPrecioState extends State<_DialogoPrecio> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _precio;
  late final TextEditingController _tarifa;
  DateTime? _inicia;
  DateTime? _termina;

  @override
  void initState() {
    super.initState();
    final p = widget.precio;
    final pr = p?.precio;
    _precio = TextEditingController(
      text: pr == null ? '' : (pr == pr.roundToDouble() ? pr.toInt().toString() : pr.toString()),
    );
    _tarifa = TextEditingController(text: p?.tarifa ?? '');
    _inicia = p?.inicia != null ? DateTime.tryParse(p!.inicia!) : null;
    _termina = p?.termina != null ? DateTime.tryParse(p!.termina!) : null;
  }

  @override
  void dispose() {
    _precio.dispose();
    _tarifa.dispose();
    super.dispose();
  }

  Future<void> _fecha(bool inicio) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (inicio ? _inicia : _termina) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => inicio ? _inicia = d : _termina = d);
  }

  String _iso(DateTime? d) =>
      d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FormDialogo(
      icono: Icons.attach_money_outlined,
      titulo: widget.precio == null ? 'Nueva tarifa' : 'Editar tarifa',
      subtitulo: 'Precio por kWh vigente en el contrato',
      formKey: _formKey,
      maxAncho: 640,
      cuerpo: [
        FilaCampos(campos: [
          TextFormField(
            controller: _precio,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Precio por kWh',
                prefixIcon: Icon(Icons.payments_outlined)),
          ),
          TextFormField(
            controller: _tarifa,
            decoration: const InputDecoration(
                labelText: 'Tarifa', prefixIcon: Icon(Icons.local_offer_outlined)),
          ),
        ]),
        const SizedBox(height: 14),
        FilaCampos(campos: [
          _filaFecha('Inicia', _inicia, () => _fecha(true), () => setState(() => _inicia = null)),
          _filaFecha(
              'Termina', _termina, () => _fecha(false), () => setState(() => _termina = null)),
        ]),
      ],
      acciones: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context, {
              'precio': double.tryParse(_precio.text.trim().replaceAll(',', '.')),
              'tarifa': _tarifa.text.trim().isEmpty ? null : _tarifa.text.trim(),
              'inicia': _inicia == null ? null : _iso(_inicia),
              'termina': _termina == null ? null : _iso(_termina),
            });
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _filaFecha(String label, DateTime? valor, VoidCallback elegir, VoidCallback limpiar) {
    return InkWell(
      onTap: elegir,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: valor == null
              ? null
              : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: limpiar),
        ),
        child: Text(valor == null ? 'Sin fecha' : _iso(valor),
            style: TextStyle(color: valor == null ? Theme.of(context).colorScheme.outline : null)),
      ),
    );
  }
}
