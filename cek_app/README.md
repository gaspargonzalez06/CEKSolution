# cek_app — App Flutter (Web + móvil)

Cliente de la CEK API (usuarios, agentes con sus claves, dashboard).

## Ejecutar

**Web (desarrollo, en Chrome):**
```bat
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
```

**Móvil (Android):** el emulador no ve `localhost`; use `10.0.2.2`:
```bat
flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000
```

**Producción web:**
```bat
flutter build web --dart-define=API_BASE=https://api.tudominio.com
```
El resultado queda en `build\web\` (sirva esa carpeta con cualquier hosting estático).

## Estructura
```
lib/
  config.dart                 URL del backend (--dart-define=API_BASE=...)
  models.dart                 Usuario, Agente
  services/
    api.dart                  cliente HTTP + manejo del token (shared_preferences)
    sesion.dart               estado de sesión (ChangeNotifier)
  screens/
    login_screen.dart         inicio de sesión
    home_screen.dart          navegación por rol
    dashboard_screen.dart     KPIs + data real del mercado
    usuarios_screen.dart      CRUD de usuarios (admin)
    agentes_screen.dart       lista de agentes
    agente_form_screen.dart   alta/edición de agente + credenciales del portal
    placeholder_screen.dart   módulos "en construcción"
  main.dart
```

Usuario inicial: **admin / admin123**.
