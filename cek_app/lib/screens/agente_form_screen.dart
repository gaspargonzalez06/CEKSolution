import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';

class AgenteFormScreen extends StatefulWidget {
  final Agente? agente;
  final String endpoint;
  const AgenteFormScreen({super.key, this.agente, this.endpoint = '/agentes'});

  @override
  State<AgenteFormScreen> createState() => _AgenteFormScreenState();
}

class _AgenteFormScreenState extends State<AgenteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _codigoCnd = TextEditingController();
  final _ruc = TextEditingController();
  final _email = TextEditingController();
  final _usuarioPortal = TextEditingController();
  final _passwordPortal = TextEditingController();

  bool _generador = false;
  bool _distribuidor = false;
  bool _gestionado = true;
  bool _activo = true;
  bool _guardando = false;

  bool get _esNuevo => widget.agente == null;

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
      _generador = a.generador;
      _distribuidor = a.distribuidor;
      _gestionado = a.gestionado;
      _activo = a.activo;
      _usuarioPortal.text = a.usuarioPortal ?? '';
      if (a.tieneCredencial) {
        _passwordPortal.text = ''; // no se muestra la clave
      }
    } else if (widget.endpoint.contains('distribuidores')) {
      _distribuidor = true;
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _codigoCnd.dispose();
    _ruc.dispose();
    _email.dispose();
    _usuarioPortal.dispose();
    _passwordPortal.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _credencial() {
    final usuario = _usuarioPortal.text.trim();
    final password = _passwordPortal.text;
    if (usuario.isEmpty && password.isEmpty) return null;
    final map = <String, dynamic>{'activo': true};
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
      'generador': _generador,
      'distribuidor': _distribuidor,
      'activo': _activo,
    };
    cuerpo['gestionado'] = _gestionado;
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
    final esDist = widget.endpoint.contains('distribuidores');
    final sustantivo = esDist ? 'distribuidor' : 'agente';
    return Scaffold(
      appBar: AppBar(
        title: Text(_esNuevo ? 'Nuevo $sustantivo' : 'Editar $sustantivo'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Datos del agente',
                style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigo,
              decoration: const InputDecoration(
                  labelText: 'Codigo *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(
                  labelText: 'Nombre / razon social', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigoCnd,
              decoration: const InputDecoration(
                  labelText: 'Codigo en el mercado (CND)',
                  helperText: 'El valor de la columna AGENTE en la data del CND',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ruc,
              decoration: const InputDecoration(labelText: 'RUC', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Generador'),
              value: _generador,
              onChanged: (v) => setState(() => _generador = v),
            ),
            SwitchListTile(
              title: const Text('Distribuidor'),
              value: _distribuidor,
              onChanged: (v) => setState(() => _distribuidor = v),
            ),
            SwitchListTile(
              secondary: Icon(
                Icons.verified_outlined,
                color: _gestionado ? tema.colorScheme.primary : tema.colorScheme.outline,
              ),
              title: const Text('Gestionado por CEK'),
              subtitle: const Text('Aparece en las listas de la app'),
              value: _gestionado,
              onChanged: (v) => setState(() => _gestionado = v),
            ),
            SwitchListTile(
              title: const Text('Activo'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const Divider(height: 32),
            Text('Credenciales del portal CND (automatizacion)',
                style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              _esNuevo
                  ? 'Se usaran para el login automatico (Playwright).'
                  : 'Deje la contrasena vacia para no cambiarla.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usuarioPortal,
              decoration: const InputDecoration(
                  labelText: 'Usuario del portal', prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordPortal,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Contrasena del portal', prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_esNuevo ? 'Crear agente' : 'Guardar cambios'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
