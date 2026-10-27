import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../widgets/comunes.dart';
import '../widgets/formulario.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Usuario> _usuarios = [];
  bool _cargando = true;
  String? _error;

  static const _roles = ['admin', 'operador', 'cliente', 'agente'];

  static const _colorRol = {
    'admin': Color(0xFF7C4DFF),
    'operador': Color(0xFF315C8A),
    'cliente': Color(0xFF0B6E4F),
    'agente': Color(0xFFF0A020),
  };

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
      final data = await Api.I.get('/usuarios') as List;
      setState(() => _usuarios = data.map((e) => Usuario.fromJson(Map<String, dynamic>.from(e))).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _UsuarioDialog(),
    );
    if (ok == true) {
      _aviso('Usuario creado');
      _cargar();
    }
  }

  Future<void> _editar(Usuario u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _UsuarioDialog(usuario: u),
    );
    if (ok == true) {
      _aviso('Usuario actualizado');
      _cargar();
    }
  }

  Future<void> _eliminar(Usuario u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a "${u.usuario}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.delete('/usuarios/${u.id}');
      _aviso('Usuario eliminado');
      _cargar();
    } on ApiException catch (e) {
      _aviso(e.mensaje, error: true);
    }
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          EncabezadoSeccion(
            titulo: 'Usuarios',
            subtitulo: '${_usuarios.length} usuarios · ${_usuarios.where((u) => u.activo).length} activos',
            icono: Icons.manage_accounts_outlined,
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
      floatingActionButton: Sesion.I.esAdmin
          ? FloatingActionButton.extended(
              onPressed: _crear,
              icon: const Icon(Icons.person_add),
              label: const Text('Nuevo usuario'),
            )
          : null,
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorVista(error: _error!, alReintentar: _cargar);
    if (_usuarios.isEmpty) {
      return const EstadoVacio(mensaje: 'Sin usuarios registrados', icono: Icons.people_outline);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _usuarios.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final u = _usuarios[i];
          final yo = u.id == Sesion.I.usuario?.id;
          final color = _colorRol[u.rol] ?? Colors.grey;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: Sesion.I.esAdmin ? () => _editar(u) : null,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(u.usuario.substring(0, 1).toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(u.etiqueta,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (yo) ...[
                    const SizedBox(width: 8),
                    const Chip(
                        label: Text('yo'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero),
                  ],
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(u.usuario),
                    EstadoChip(u.rol, color),
                    EstadoChip(u.activo ? 'activo' : 'inactivo',
                        u.activo ? const Color(0xFF12B886) : Colors.grey),
                    if (u.email != null && u.email!.isNotEmpty)
                      Text(u.email!,
                          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
              trailing: Sesion.I.esAdmin && !yo
                  ? IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _eliminar(u),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _UsuarioDialog extends StatefulWidget {
  final Usuario? usuario;
  const _UsuarioDialog({this.usuario});

  @override
  State<_UsuarioDialog> createState() => _UsuarioDialogState();
}

class _UsuarioDialogState extends State<_UsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _buscaCliente = TextEditingController();
  String _rol = 'cliente';
  bool _activo = true;
  bool _verClave = false;
  bool _guardando = false;

  // Acceso customizable: agentes completos y/o clientes sueltos.
  List<Agente> _agentes = [];
  List<Cliente> _clientes = [];
  final Set<int> _selAgentes = {};
  final Set<int> _selClientes = {};
  bool _cargandoAccesos = true;

  bool get _esNuevo => widget.usuario == null;

  static const _descRol = {
    'admin': 'Acceso total, incluye usuarios',
    'operador': 'Opera datos e invoices',
    'cliente': 'Solo consulta de su cuenta',
    'agente': 'Solo consulta de su agente',
  };

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    if (u != null) {
      _usuario.text = u.usuario;
      _email.text = u.email ?? '';
      _rol = u.rol;
      _activo = u.activo;
    }
    _cargarAccesos();
  }

  Future<void> _cargarAccesos() async {
    try {
      final ag = await Api.I.get('/agentes') as List;
      final cl = await Api.I.get('/clientes') as List;
      if (mounted) {
        setState(() {
          _agentes =
              ag.map((e) => Agente.fromJson(Map<String, dynamic>.from(e))).toList();
          _clientes =
              cl.map((e) => Cliente.fromJson(Map<String, dynamic>.from(e))).toList();
        });
      }
      if (!_esNuevo) {
        final a = Map<String, dynamic>.from(
            await Api.I.get('/usuarios/${widget.usuario!.id}/accesos'));
        if (mounted) {
          setState(() {
            _selAgentes
                .addAll(((a['agentes'] as List?) ?? []).map((e) => e as int));
            _selClientes
                .addAll(((a['clientes'] as List?) ?? []).map((e) => e as int));
          });
        }
      }
    } catch (_) {
      // Sin catalogos igual se puede guardar el usuario (acceso vacio).
    } finally {
      if (mounted) setState(() => _cargandoAccesos = false);
    }
  }

  @override
  void dispose() {
    _usuario.dispose();
    _email.dispose();
    _password.dispose();
    _buscaCliente.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final cuerpo = <String, dynamic>{
      'nombre': _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'rol': _rol,
      'activo': _activo,
    };
    if (_esNuevo) {
      cuerpo['usuario'] = _usuario.text.trim();
      cuerpo['password'] = _password.text;
    } else if (_password.text.isNotEmpty) {
      cuerpo['password'] = _password.text;
    }
    try {
      int idGuardado;
      if (_esNuevo) {
        final creado =
            Map<String, dynamic>.from(await Api.I.post('/usuarios', cuerpo));
        idGuardado = creado['id'] as int;
      } else {
        await Api.I.put('/usuarios/${widget.usuario!.id}', cuerpo);
        idGuardado = widget.usuario!.id;
      }
      await Api.I.put('/usuarios/$idGuardado/accesos', {
        'agentes': _selAgentes.toList(),
        'clientes': _selClientes.toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } catch (e) {
      _aviso('$e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: Theme.of(context).colorScheme.error));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return FormDialogo(
      icono: _esNuevo ? Icons.person_add_alt_outlined : Icons.manage_accounts_outlined,
      titulo: _esNuevo ? 'Nuevo usuario' : 'Editar usuario',
      subtitulo: 'Credenciales, perfil y accesos del usuario',
      formKey: _formKey,
      maxAncho: 720,
      cuerpo: [
        SeccionFormulario(
          titulo: 'Acceso',
          icono: Icons.login_outlined,
          hijos: [
            TextFormField(
              controller: _usuario,
              enabled: _esNuevo,
              decoration: const InputDecoration(
                  labelText: 'Usuario *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Mínimo 3 caracteres' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: !_verClave,
              decoration: InputDecoration(
                labelText: _esNuevo ? 'Contraseña *' : 'Nueva contraseña (opcional)',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: _esNuevo ? null : 'Déjela vacía para no cambiarla',
                suffixIcon: IconButton(
                  tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                  icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _verClave = !_verClave),
                ),
              ),
              validator: (v) {
                if (_esNuevo && (v == null || v.length < 4)) return 'Mínimo 4 caracteres';
                if (v != null && v.isNotEmpty && v.length < 4) return 'Mínimo 4 caracteres';
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Perfil',
          icono: Icons.badge_outlined,
          hijos: [
            FilaCampos(campos: [
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(
                    labelText: 'Nombre', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Rol y estado',
          icono: Icons.admin_panel_settings_outlined,
          hijos: [
            for (final r in _UsuariosScreenState._roles)
              InkWell(
                onTap: () => setState(() => _rol = r),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _rol == r ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 20,
                        color: _rol == r ? tema.colorScheme.primary : tema.colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      EstadoChip(r, _UsuariosScreenState._colorRol[r] ?? Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_descRol[r] ?? '',
                            style: tema.textTheme.bodySmall
                                ?.copyWith(color: tema.colorScheme.outline)),
                      ),
                    ],
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.check_circle_outline,
                  color: _activo ? tema.colorScheme.primary : tema.colorScheme.outline),
              title: const Text('Activo'),
              subtitle: const Text('Permite iniciar sesión en el sistema'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SeccionFormulario(
          titulo: 'Accesos',
          icono: Icons.key_outlined,
          hijos: [_accesos()],
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
          label: Text(_esNuevo ? 'Crear usuario' : 'Guardar cambios'),
        ),
      ],
    );
  }

  Widget _accesos() {
    final tema = Theme.of(context);
    if (_cargandoAccesos) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_rol == 'admin' || _rol == 'operador') {
      return Text(
          'Este rol ve todo el sistema (no requiere asignar accesos).',
          style: tema.textTheme.bodySmall
              ?.copyWith(color: tema.colorScheme.outline));
    }
    final busca = _buscaCliente.text.trim().toLowerCase();
    final clientesVisibles = _clientes
        .where((c) =>
            busca.isEmpty ||
            c.etiqueta.toLowerCase().contains(busca) ||
            c.codigo.toLowerCase().contains(busca))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Agentes (da acceso a TODOS sus clientes)',
            style:
                tema.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final a in _agentes)
              FilterChip(
                label: Text(a.codigo),
                selected: _selAgentes.contains(a.id),
                onSelected: (v) => setState(() {
                  if (v) {
                    _selAgentes.add(a.id);
                  } else {
                    _selAgentes.remove(a.id);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Clientes sueltos (acceso fino)',
            style:
                tema.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _buscaCliente,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Buscar cliente',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final c in clientesVisibles)
              FilterChip(
                label: Text(c.codigo),
                tooltip: c.etiqueta,
                selected: _selClientes.contains(c.id),
                onSelected: (v) => setState(() {
                  if (v) {
                    _selClientes.add(c.id);
                  } else {
                    _selClientes.remove(c.id);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
            '${_selAgentes.length} agente(s) · ${_selClientes.length} cliente(s) seleccionados',
            style: tema.textTheme.bodySmall
                ?.copyWith(color: tema.colorScheme.outline)),
      ],
    );
  }
}
