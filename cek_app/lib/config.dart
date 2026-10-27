/// Configuracion de la app.
///
/// La URL del backend se puede cambiar sin tocar codigo con --dart-define:
///   flutter run --dart-define=API_BASE=http://192.168.1.10:8000
///   flutter build web --dart-define=API_BASE=https://api.tudominio.com
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8000',
  );

  static const String appNombre = 'CEK';
}
