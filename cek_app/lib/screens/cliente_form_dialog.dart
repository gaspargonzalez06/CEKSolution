import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/formulario.dart';

/// Formulario modal para crear/editar un cliente.
class ClienteFormDialog extends StatefulWidget {
  final Cliente? cliente;
  final List<Agente> distribuidores;
  const ClienteFormDialog({super.key, this.cliente, this.distribuidores = const []});

  @override
  State<ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _ruc = TextEditingController();
  final _nis = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _contacto = TextEditingController();
  final _email = TextEditingController();
  int? _idDistribuidor;
  bool _activo = true;
  bool _guardando = false;

  bool get _esNuevo => widget.cliente == null;

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    if (c != null) {
      _codigo.text = c.codigo;
      _nombre.text = c.nombre ?? '';
      _ruc.text = c.ruc ?? '';
      _nis.text = c.nis ?? '';
      _telefono.text = c.telefono ?? '';
      _direccion.text = c.direccion ?? '';
      _contacto.text = c.contacto ?? '';
      _email.text = c.email ?? '';
      _idDistribuidor = c.idDistribuidor;
      _activo = c.activo;
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _ruc.dispose();
    _nis.dispose();
    _telefono.dispose();
    _direccion.dispose();
    _contacto.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _vacio(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final cuerpo = <String, dynamic>{
      'codigo': _codigo.text.trim(),
      'nombre': _nombre.text.trim(),
      'ruc': _vacio(_ruc),
      'nis': _vacio(_nis),
      'telefono': _vacio(_telefono),
      'direccion': _vacio(_direccion),
      'contacto': _vacio(_contacto),
      'email': _vacio(_email),
      'id_distribuidor': _idDistribuidor,
      'activo': _activo,
    };
    try {
      if (_esNuevo) {
        await Api.I.post('/clientes', cuerpo);
      } else {
        await Api.I.put('/clientes/${widget.cliente!.id}', cuerpo);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return FormDialogo(
      icono: _esNuevo ? Icons.person_add_alt_1_outlined : Icons.person_outline,
      titulo: _esNuevo ? 'Nuevo cliente' : 'Editar cliente',
      subtitulo: _esNuevo
          ? 'Registra los datos del cliente'
          : 'Actualiza la información del cliente',
      formKey: _formKey,
      cuerpo: [
        SeccionFormulario(
          titulo: 'Identificación',
          icono: Icons.badge_outlined,
          hijos: [
            TextFormField(
              controller: _codigo,
              decoration: const InputDecoration(
                  labelText: 'Código *',
                  hintText: 'Ej. GCP0001',
                  prefixIcon: Icon(Icons.tag)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(
                  labelText: 'Nombre / razón social',
                  prefixIcon: Icon(Icons.business_outlined)),
            ),
            const SizedBox(height: 14),
            FilaCampos(campos: [
              TextFormField(
                controller: _ruc,
                decoration: const InputDecoration(
                    labelText: 'RUC', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              TextFormField(
                controller: _nis,
                decoration: const InputDecoration(
                    labelText: 'NIS', prefixIcon: Icon(Icons.numbers)),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Contacto',
          icono: Icons.contact_mail_outlined,
          hijos: [
            TextFormField(
              controller: _telefono,
              decoration: const InputDecoration(
                  labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _direccion,
              decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: 14),
            FilaCampos(campos: [
              TextFormField(
                controller: _contacto,
                decoration: const InputDecoration(
                    labelText: 'Contacto',
                    prefixIcon: Icon(Icons.person_pin_outlined)),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Clasificación',
          icono: Icons.category_outlined,
          hijos: [
            DropdownButtonFormField<int?>(
              initialValue: _idDistribuidor,
              decoration: const InputDecoration(
                  labelText: 'Agente',
                  helperText: 'El agente principal se define en el contrato; '
                      'aquí puedes dejarlo asociado directamente.',
                  prefixIcon: Icon(Icons.groups_outlined)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin agente')),
                for (final d in widget.distribuidores)
                  DropdownMenuItem(value: d.id, child: Text(d.etiqueta)),
              ],
              onChanged: (v) => setState(() => _idDistribuidor = v),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.check_circle_outline,
                  color: _activo ? tema.colorScheme.primary : tema.colorScheme.outline),
              title: const Text('Activo'),
              subtitle:
                  const Text('Disponible para contratos y facturación'),
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
          label: Text(_esNuevo ? 'Crear cliente' : 'Guardar cambios'),
        ),
      ],
    );
  }
}
