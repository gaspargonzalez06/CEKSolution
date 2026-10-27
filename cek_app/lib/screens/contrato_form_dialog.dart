import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/formulario.dart';

/// Formulario modal para crear/editar un contrato.
class ContratoFormDialog extends StatefulWidget {
  final Contrato? contrato;
  final List<Agente> agentes;
  final List<Cliente> clientes;
  const ContratoFormDialog({
    super.key,
    this.contrato,
    required this.agentes,
    required this.clientes,
  });

  @override
  State<ContratoFormDialog> createState() => _ContratoFormDialogState();
}

class _ContratoFormDialogState extends State<ContratoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _interes = TextEditingController();
  final _garantia = TextEditingController();
  final _indexacion = TextEditingController();
  final _medicion = TextEditingController();
  int? _idAgente;
  int? _idCliente;
  DateTime? _inicio;
  DateTime? _fin;
  bool _activo = true;
  bool _guardando = false;

  bool get _esNuevo => widget.contrato == null;

  @override
  void initState() {
    super.initState();
    final c = widget.contrato;
    if (c != null) {
      _codigo.text = c.contrato ?? '';
      _idAgente = c.idAgente;
      _idCliente = c.idCliente;
      _inicio = c.inicio != null ? DateTime.tryParse(c.inicio!) : null;
      _fin = c.fin != null ? DateTime.tryParse(c.fin!) : null;
      _interes.text = c.interes != null ? _num(c.interes!) : '';
      _garantia.text = c.garantia ?? '';
      _indexacion.text = c.indexacion ?? '';
      _medicion.text = c.medicion ?? '';
      _activo = c.activo;
    } else {
      _idAgente = widget.agentes.isEmpty ? null : widget.agentes.first.id;
    }
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _codigo.dispose();
    _interes.dispose();
    _garantia.dispose();
    _indexacion.dispose();
    _medicion.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha(bool esInicio) async {
    final inicial = (esInicio ? _inicio : _fin) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: esInicio ? 'Fecha de inicio' : 'Fecha final',
    );
    if (d != null) setState(() => esInicio ? _inicio = d : _fin = d);
  }

  String _iso(DateTime? d) =>
      d == null ? '' : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idAgente == null || _idCliente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione agente y cliente')));
      return;
    }
    setState(() => _guardando = true);
    final interes = double.tryParse(_interes.text.trim().replaceAll(',', '.'));
    final data = <String, dynamic>{
      'contrato': _codigo.text.trim().isEmpty ? null : _codigo.text.trim(),
      'id_agente': _idAgente,
      'id_cliente': _idCliente,
      'inicio': _inicio == null ? null : _iso(_inicio),
      'final': _fin == null ? null : _iso(_fin),
      'interes': interes,
      'garantia': _garantia.text.trim().isEmpty ? null : _garantia.text.trim(),
      'indexacion': _indexacion.text.trim().isEmpty ? null : _indexacion.text.trim(),
      'medicion': _medicion.text.trim().isEmpty ? null : _medicion.text.trim(),
      'activo': _activo,
    };
    try {
      if (_esNuevo) {
        await Api.I.post('/contratos', data);
      } else {
        await Api.I.put('/contratos/${widget.contrato!.id}', data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return FormDialogo(
      icono: _esNuevo ? Icons.note_add_outlined : Icons.description_outlined,
      titulo: _esNuevo ? 'Nuevo contrato' : 'Editar contrato',
      subtitulo: 'Vincula un agente con un cliente y define las condiciones',
      formKey: _formKey,
      maxAncho: 820,
      cuerpo: [
        SeccionFormulario(
          titulo: 'Partes',
          icono: Icons.handshake_outlined,
          hijos: [
            TextFormField(
              controller: _codigo,
              decoration: const InputDecoration(
                  labelText: 'N.º de contrato',
                  prefixIcon: Icon(Icons.tag),
                  helperText: 'Ej. GC No.24-25'),
            ),
            const SizedBox(height: 14),
            FilaCampos(campos: [
              DropdownButtonFormField<int>(
                initialValue: _idAgente,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Agente *', prefixIcon: Icon(Icons.bolt_outlined)),
                items: [
                  for (final a in widget.agentes)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.etiqueta} (${a.tipo})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _idAgente = v),
              ),
              DropdownButtonFormField<int>(
                initialValue: _idCliente,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Cliente *',
                    prefixIcon: Icon(Icons.people_alt_outlined)),
                items: [
                  for (final c in widget.clientes)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text(c.etiqueta, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _idCliente = v),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Vigencia',
          icono: Icons.event_outlined,
          hijos: [
            FilaCampos(campos: [
              _CampoFecha(
                etiqueta: 'Inicio',
                valor: _inicio,
                alTocar: () => _elegirFecha(true),
                alLimpiar: _inicio == null ? null : () => setState(() => _inicio = null),
              ),
              _CampoFecha(
                etiqueta: 'Final',
                valor: _fin,
                alTocar: () => _elegirFecha(false),
                alLimpiar: _fin == null ? null : () => setState(() => _fin = null),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Condiciones',
          icono: Icons.tune_outlined,
          hijos: [
            TextFormField(
              controller: _interes,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Interés (%)', prefixIcon: Icon(Icons.percent)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _garantia,
              decoration: const InputDecoration(
                  labelText: 'Garantía',
                  prefixIcon: Icon(Icons.verified_outlined)),
            ),
            const SizedBox(height: 14),
            FilaCampos(campos: [
              TextFormField(
                controller: _indexacion,
                decoration: const InputDecoration(
                    labelText: 'Indexación', prefixIcon: Icon(Icons.trending_up)),
              ),
              TextFormField(
                controller: _medicion,
                decoration: const InputDecoration(
                    labelText: 'Medición', prefixIcon: Icon(Icons.speed_outlined)),
              ),
            ]),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.check_circle_outline,
                  color: _activo ? tema.colorScheme.primary : tema.colorScheme.outline),
              title: const Text('Contrato activo'),
              subtitle: const Text('Habilita el contrato para la facturación'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
          ],
        ),
      ],
      acciones: [
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_esNuevo ? 'Crear contrato' : 'Guardar cambios'),
        ),
      ],
    );
  }
}

class _CampoFecha extends StatelessWidget {
  final String etiqueta;
  final DateTime? valor;
  final VoidCallback alTocar;
  final VoidCallback? alLimpiar;
  const _CampoFecha({
    required this.etiqueta,
    required this.valor,
    required this.alTocar,
    this.alLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: alTocar,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: const Icon(Icons.event_outlined),
          border: const OutlineInputBorder(),
          suffixIcon: alLimpiar == null
              ? null
              : IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: alLimpiar,
                ),
        ),
        child: Text(
          valor == null
              ? 'Sin fecha'
              : '${valor!.year}-${valor!.month.toString().padLeft(2, '0')}-${valor!.day.toString().padLeft(2, '0')}',
          style: TextStyle(color: valor == null ? tema.colorScheme.outline : null),
        ),
      ),
    );
  }
}
