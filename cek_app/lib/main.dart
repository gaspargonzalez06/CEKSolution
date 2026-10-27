import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/preferencias.dart';
import 'services/sesion.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferencias.I.init();
  final restored = await Sesion.I.init();
  runApp(CekApp(iniciado: restored));
}

class CekApp extends StatelessWidget {
  final bool iniciado;
  const CekApp({super.key, required this.iniciado});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Preferencias.I,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appNombre,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.claro(),
          darkTheme: AppTheme.oscuro(),
          themeMode: Preferencias.I.tema,
          home: _Raiz(iniciado: iniciado),
        );
      },
    );
  }
}

class _Raiz extends StatelessWidget {
  final bool iniciado;
  const _Raiz({required this.iniciado});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Sesion.I,
      builder: (_, _) => Sesion.I.autenticado ? const HomeScreen() : const LoginScreen(),
    );
  }
}
