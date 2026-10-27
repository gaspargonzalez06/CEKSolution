import 'abrir_url_stub.dart' if (dart.library.html) 'abrir_url_web.dart' as impl;

/// Abre una URL en una pestaña nueva del navegador (solo tiene efecto en Web).
void abrirEnNavegador(String url) => impl.abrirEnNavegador(url);
