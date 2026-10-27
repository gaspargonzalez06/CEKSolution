import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias visuales del usuario (por ahora, el tema claro/oscuro).
///
/// Se guarda en `shared_preferences` para que la elección sobreviva a recargas
/// y reinicios. Toda la app lee el tema desde aquí y se reconstruye sola.
class Preferencias extends ChangeNotifier {
  Preferencias._();
  static final Preferencias I = Preferencias._();

  static const String _claveTema = 'cek_tema';

  ThemeMode _tema = ThemeMode.system;
  ThemeMode get tema => _tema;

  bool get esOscuroFijo => _tema == ThemeMode.dark;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _tema = switch (p.getString(_claveTema)) {
        'claro' => ThemeMode.light,
        'oscuro' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Sin preferencias guardadas: se usa el tema del sistema.
    }
    notifyListeners();
  }

  Future<void> setTema(ThemeMode modo) async {
    if (_tema == modo) return;
    _tema = modo;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _claveTema,
        switch (modo) {
          ThemeMode.light => 'claro',
          ThemeMode.dark => 'oscuro',
          ThemeMode.system => 'sistema',
        },
      );
    } catch (_) {
      // Si no se puede persistir, el cambio igual aplica en esta sesión.
    }
  }

  /// Alterna entre claro y oscuro tomando como base el brillo actual.
  Future<void> alternar(Brightness actual) =>
      setTema(actual == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
