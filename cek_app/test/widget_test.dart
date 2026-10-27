import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cek_app/screens/login_screen.dart';

void main() {
  testWidgets('La pantalla de login muestra el formulario', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
