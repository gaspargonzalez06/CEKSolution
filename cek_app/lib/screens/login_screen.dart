import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController(text: 'admin');
  final _password = TextEditingController(text: 'admin123');
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await Sesion.I.login(_usuario.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'No se pudo conectar con el servidor.\n$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ancho = MediaQuery.of(context).size.width;
    final mostrarMarca = ancho >= 900;

    final formulario = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!mostrarMarca) ...[
                      Icon(Icons.bolt, size: 44, color: tema.colorScheme.primary),
                      const SizedBox(height: 12),
                    ],
                    Text('Iniciar sesión',
                        style: tema.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('Acceso al sistema de agentes, clientes y facturación',
                        style: tema.textTheme.bodySmall
                            ?.copyWith(color: tema.colorScheme.outline)),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _usuario,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingrese el usuario' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onFieldSubmitted: (_) => _entrar(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Ingrese la contraseña' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tema.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: tema.colorScheme.onErrorContainer, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(color: tema.colorScheme.onErrorContainer)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _cargando ? null : _entrar,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _cargando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          mostrarMarca
              ? Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppTheme.semilla, AppTheme.verde],
                          ),
                        ),
                        child: const _MarcaPanel(),
                      ),
                    ),
                    Expanded(flex: 4, child: formulario),
                  ],
                )
              : formulario,
          const Positioned(top: 12, right: 12, child: BotonTema()),
        ],
      ),
    );
  }
}

class _MarcaPanel extends StatelessWidget {
  const _MarcaPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.bolt, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 28),
          const Text('CEK',
              style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            '${AppConfig.appNombre} · Gestión del mercado eléctrico',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          const _Punto('Agentes, distribuidores y clientes en un solo lugar'),
          const _Punto('Dashboard con datos reales del CND'),
          const _Punto('Facturación mensual y reclamaciones'),
          const _Punto('Automatización de la descarga de informes'),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  final String texto;
  const _Punto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
