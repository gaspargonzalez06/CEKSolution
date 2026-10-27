import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/formulario.dart';

/// Formulario modal para crear/editar un agente (o distribuidor).
///
/// Los datos generales y las credenciales del portal CND viven en pestañas
/// separadas para no mezclar la ficha del agente con su acceso al portal.
class AgenteFormDialog extends StatefulWidget {
  final Agente? agente;
  final String endpoint;
  const AgenteFormDialog({super.key, this.agente, this.endpoint = '/agentes'});

  @override
  State<AgenteFormDialog> createState() => _AgenteFormDialogState();
}

class _AgenteFormDialogState extends State<AgenteFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _codigoCnd = TextEditingController();
  final _ruc = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _usuarioPortal = TextEditingController();
  final _passwordPortal = TextEditingController();

  bool _generador = false;
  bool _distribuidor = false;
  bool _gestionado = true;
  bool _activo = true;
  bool _credencialActiva = true;
  bool _verClave = false;
  bool _guardando = false;

  bool get _esNuevo => widget.agente == null;
  bool get _esDist => widget.endpoint.contains('distribuidores');
  String get _sustantivo => _esDist ? 'distribuidor' : 'agente';

  @override
  void initState() {
    super.initState();
    final a = widget.agente;
    if (a != null) {
      _codigo.text = a.codigo;
      _nombre.text = a.nombre ?? '';
      _codigoCnd.text = a.codigoCnd ?? '';
      _ruc.text = a.ruc ?? '';
      _email.text = a.email ?? '';
      _telefono.text = a.telefono ?? '';
      _direccion.text = a.direccion ?? '';
      _generador = a.generador;
      _distribuidor = a.distribuidor;
      _gestionado = a.gestionado;
      _activo = a.activo;
      _usuarioPortal.text = a.usuarioPortal ?? '';
      // Si editando y tiene credenciales + es admin, cargar clave real
      final tiene = a.tieneCredencial;
      if (tiene && Sesion.I.esAdmin) {
        _cargarClaveReal(a.id);
      }
    } else if (_esDist) {
      _distribuidor = true;
    }
  }

  Future<void> _cargarClaveReal(int idAgente) async {
    try {
      final res = await Api.I.get('/agentes/$idAgente/credencial/clave');
      if (mounted) {
        _passwordPortal.text = (res['password_portal'] as String?) ?? '';
      }
    } catch (_) {
      // Si falla, dejar campo vacío (usuario podrá escribir nueva)
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _codigoCnd.dispose();
    _ruc.dispose();
    _email.dispose();
    _telefono.dispose();
    _direccion.dispose();
    _usuarioPortal.dispose();
    _passwordPortal.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _credencial() {
    final usuario = _usuarioPortal.text.trim();
    final password = _passwordPortal.text;
    if (usuario.isEmpty && password.isEmpty) return null;
    final map = <String, dynamic>{'activo': _credencialActiva};
    if (usuario.isNotEmpty) map['usuario_portal'] = usuario;
    if (password.isNotEmpty) map['password_portal'] = password;
    return map;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final cuerpo = <String, dynamic>{
      'codigo': _codigo.text.trim(),
      'nombre': _nombre.text.trim(),
      'codigo_cnd': _codigoCnd.text.trim().isEmpty ? null : _codigoCnd.text.trim(),
      'ruc': _ruc.text.trim().isEmpty ? null : _ruc.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'telefono': _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
      'direccion': _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
      'generador': _generador,
      'distribuidor': _distribuidor,
      'gestionado': _gestionado,
      'activo': _activo,
    };
    final cred = _credencial();
    if (cred != null) cuerpo['credencial'] = cred;

    try {
      if (_esNuevo) {
        await Api.I.post(widget.endpoint, cuerpo);
      } else {
        await Api.I.put('${widget.endpoint}/${widget.agente!.id}', cuerpo);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } catch (e) {
      _aviso('Error: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: tema.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_esDist ? Icons.storefront : Icons.solar_power,
                          color: tema.colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_esNuevo ? 'Nuevo $_sustantivo' : 'Editar $_sustantivo',
                              style: tema.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Datos generales y credenciales del portal CND',
                              style: tema.textTheme.bodySmall
                                  ?.copyWith(color: tema.colorScheme.outline)),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Datos generales', icon: Icon(Icons.badge_outlined)),
                  Tab(text: 'Credenciales CND', icon: Icon(Icons.vpn_key_outlined)),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: TabBarView(
                    children: [
                      _tabDatos(),
                      _tabCredenciales(),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: _guardando ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_esNuevo ? 'Crear $_sustantivo' : 'Guardar cambios'),
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

  Widget _tabDatos() {
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SeccionFormulario(
          titulo: 'Identidad',
          icono: Icons.badge_outlined,
          hijos: [
            TextFormField(
              controller: _codigo,
              decoration: const InputDecoration(
                  labelText: 'Código *',
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
            TextFormField(
              controller: _codigoCnd,
              decoration: const InputDecoration(
                  labelText: 'Código en el mercado (CND)',
                  helperText: 'El valor de la columna AGENTE en la data del CND',
                  prefixIcon: Icon(Icons.public_outlined)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Contacto',
          icono: Icons.contact_mail_outlined,
          hijos: [
            FilaCampos(campos: [
              TextFormField(
                controller: _telefono,
                decoration: const InputDecoration(
                    labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ruc,
              decoration: const InputDecoration(
                  labelText: 'RUC', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _direccion,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Clasificación',
          icono: Icons.category_outlined,
          hijos: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _chipSwitch('Generador', _generador, Icons.solar_power,
                    (v) => setState(() => _generador = v)),
                _chipSwitch('Distribuidor', _distribuidor, Icons.storefront,
                    (v) => setState(() => _distribuidor = v)),
                _chipSwitch('Activo', _activo, Icons.check_circle_outline,
                    (v) => setState(() => _activo = v)),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.verified_outlined,
                  color: _gestionado ? tema.colorScheme.primary : tema.colorScheme.outline),
              title: const Text('Gestionado por CEK'),
              subtitle: const Text('Aparece en las listas de la app'),
              value: _gestionado,
              onChanged: (v) => setState(() => _gestionado = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tabCredenciales() {
    final tema = Theme.of(context);
    final tiene = widget.agente?.tieneCredencial ?? false;
    final soloLectura = tiene && !_esNuevo && Sesion.I.esAdmin;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tema.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tema.colorScheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: tema.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  soloLectura
                      ? 'Clave actual del portal (solo lectura). Para cambiarla, edite el campo.'
                      : (tiene
                          ? 'Este agente ya tiene credenciales. Deje la contraseña vacía para no cambiarla.'
                          : 'Se usarán para el login automático del portal CND (Playwright).'),
                  style: tema.textTheme.bodySmall
                      ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _usuarioPortal,
          readOnly: soloLectura,
          decoration: InputDecoration(
            labelText: 'Usuario del portal',
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _passwordPortal,
          obscureText: !_verClave,
          readOnly: soloLectura,
          decoration: InputDecoration(
            labelText: 'Contraseña del portal',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _verClave ? 'Ocultar' : 'Mostrar',
              icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
              // El ojito siempre debe funcionar: permite ver la clave guardada
              // (solo lectura) o la que se esta escribiendo.
              onPressed: () => setState(() => _verClave = !_verClave),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.power_settings_new,
              color: _credencialActiva ? tema.colorScheme.primary : tema.colorScheme.outline),
          title: const Text('Credencial activa'),
          subtitle: const Text('Habilita la automatización (scraper) para este agente'),
          value: _credencialActiva,
          onChanged: (v) => setState(() => _credencialActiva = v),
        ),
      ],
    );
  }

  Widget _chipSwitch(String texto, bool valor, IconData icono, ValueChanged<bool> onCambio) {
    final tema = Theme.of(context);
    return FilterChip(
      selected: valor,
      showCheckmark: false,
      avatar: Icon(icono,
          size: 18, color: valor ? tema.colorScheme.primary : tema.colorScheme.outline),
      label: Text(texto),
      onSelected: onCambio,
    );
  }
}
