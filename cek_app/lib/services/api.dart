import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ApiException implements Exception {
  final int status;
  final String mensaje;
  ApiException(this.status, this.mensaje);
  @override
  String toString() => mensaje;
}

/// Cliente HTTP simple (singleton) que maneja el token JWT.
class Api {
  Api._();
  static final Api I = Api._();

  static const _claveToken = 'cek_token';
  String? _token;
  bool get autenticado => _token != null;

  Future<void> cargarToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_claveToken);
  }

  Future<void> _guardarToken(String? t) async {
    _token = t;
    final prefs = await SharedPreferences.getInstance();
    if (t == null) {
      await prefs.remove(_claveToken);
    } else {
      await prefs.setString(_claveToken, t);
    }
  }

  Future<void> cerrarSesion() => _guardarToken(null);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  dynamic _decodificar(String cuerpo) {
    if (cuerpo.isEmpty) return null;
    try {
      return jsonDecode(cuerpo);
    } catch (_) {
      return cuerpo;
    }
  }

  String _mensajeError(http.Response r, dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      return d.toString();
    }
    return 'Error ${r.statusCode}';
  }

  Future<dynamic> _enviar(String metodo, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('${AppConfig.apiBase}$path');
    late http.Response r;
    final txt = body == null ? null : jsonEncode(body);
    switch (metodo) {
      case 'GET':
        r = await http.get(uri, headers: _headers);
        break;
      case 'POST':
        r = await http.post(uri, headers: _headers, body: txt);
        break;
      case 'PUT':
        r = await http.put(uri, headers: _headers, body: txt);
        break;
      case 'DELETE':
        r = await http.delete(uri, headers: _headers);
        break;
      default:
        throw ApiException(0, 'Metodo no soportado');
    }
    final data = _decodificar(r.body);
    if (r.statusCode >= 400) throw ApiException(r.statusCode, _mensajeError(r, data));
    return data;
  }

  Future<dynamic> get(String p) => _enviar('GET', p);
  Future<dynamic> post(String p, [Map<String, dynamic>? b]) => _enviar('POST', p, b);
  Future<dynamic> put(String p, [Map<String, dynamic>? b]) => _enviar('PUT', p, b);
  Future<dynamic> delete(String p) => _enviar('DELETE', p);

  Future<Map<String, dynamic>> login(String usuario, String password) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/login');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': usuario, 'password': password},
    );
    final data = _decodificar(r.body);
    if (r.statusCode >= 400) throw ApiException(r.statusCode, _mensajeError(r, data));
    await _guardarToken(data['access_token'] as String);
    return Map<String, dynamic>.from(data);
  }
}
