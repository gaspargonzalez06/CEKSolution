import 'package:flutter/foundation.dart';

import '../models.dart';
import 'api.dart';

/// Estado de sesion de la app (usuario logueado, rol, etc.).
class Sesion extends ChangeNotifier {
  Sesion._();
  static final Sesion I = Sesion._();

  Usuario? usuario;

  bool get autenticado => usuario != null;
  bool get esAdmin => usuario?.rol == 'admin';
  bool get puedeEditar => usuario?.rol == 'admin' || usuario?.rol == 'operador';

  /// Intenta restaurar la sesion usando el token guardado.
  Future<bool> init() async {
    await Api.I.cargarToken();
    if (!Api.I.autenticado) return false;
    try {
      final data = await Api.I.get('/auth/me');
      usuario = Usuario.fromJson(Map<String, dynamic>.from(data));
      notifyListeners();
      return true;
    } catch (_) {
      await Api.I.cerrarSesion();
      return false;
    }
  }

  Future<void> login(String usuarioNombre, String password) async {
    final data = await Api.I.login(usuarioNombre, password);
    usuario = Usuario.fromJson(Map<String, dynamic>.from(data['usuario']));
    notifyListeners();
  }

  Future<void> logout() async {
    await Api.I.cerrarSesion();
    usuario = null;
    notifyListeners();
  }
}
