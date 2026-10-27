// Pruebas de humo de las graficas (fl_chart): verifican que renderizan sin
// excepciones de layout con datos tipicos del analisis de sustentos.
import 'package:cek_app/widgets/graficas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _envolver(Widget hijo) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 820, height: 420, child: SingleChildScrollView(child: hijo)),
        ),
      ),
    );

void main() {
  testWidgets('GraficaEvolucion combina barras y linea', (tester) async {
    final real = List<double?>.generate(31, (i) => i < 11 ? 30000.0 + i * 100 : null);
    final proy = List<double?>.generate(31, (i) => i < 11 ? null : 33212.0);
    final cerr = List<double?>.generate(30, (i) => 34000.0 + i);
    await tester.pumpWidget(_envolver(GraficaEvolucion(
      real: real,
      proyectado: proy,
      cerrado: cerr,
      etiquetasX: List.generate(31, (i) => '${i + 1}'),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GraficaLineas con varias series', (tester) async {
    await tester.pumpWidget(_envolver(GraficaLineas(
      series: [
        SerieLinea(nombre: 'v1', valores: List<double?>.generate(31, (i) => i < 27 ? 1000.0 * i : null), color: Colors.blue),
        SerieLinea(nombre: 'v2', valores: List<double?>.generate(31, (i) => i < 30 ? 1100.0 * i : null), color: Colors.green),
      ],
      etiquetasX: List.generate(31, (i) => '${i + 1}'),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GraficaLineas con datos nulos', (tester) async {
    await tester.pumpWidget(_envolver(const GraficaLineas(
      series: [SerieLinea(nombre: 'x', valores: [null, null], color: Colors.blue)],
      etiquetasX: ['1', '2'],
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GraficaBarrasFl con valores negativos', (tester) async {
    await tester.pumpWidget(_envolver(GraficaBarrasFl(
      valores: [10.5, -3.2, 8.0, -1.0, 4.4],
      etiquetasX: const ['a', 'b', 'c', 'd', 'e'],
      colores: const [Colors.green, Colors.red, Colors.green, Colors.red, Colors.green],
      etiquetaCada: 1,
      permitirNegativos: true,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GraficaBarrasFl de 31 dias', (tester) async {
    await tester.pumpWidget(_envolver(GraficaBarrasFl(
      valores: List<double?>.generate(31, (i) => 2000.0 + i * 50),
      etiquetasX: List.generate(31, (i) => '${i + 1}'),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('BarrasHorizontales top agentes', (tester) async {
    await tester.pumpWidget(_envolver(const BarrasHorizontales(
      items: [('EDEMET', 145019.5), ('ENSA', 95929.8), ('EDECHI', 52435.7)],
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
