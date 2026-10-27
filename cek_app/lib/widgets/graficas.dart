import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Series y graficas basadas en fl_chart (estilo del dashboard Python de CND).
const _azul = Color(0xFF315C8A);
const _verde = Color(0xFF12B886);
const _ambar = Color(0xFFF0A020);
const _rojo = Color(0xFFD84A43);
const _morado = Color(0xFF7C4DFF);
const _cyan = Color(0xFF39C5CF);
const _rosa = Color(0xFFDB61A2);

const coloresSerie = [_azul, _verde, _ambar, _morado, _rojo, _cyan, _rosa];

/// Serie para graficas de lineas (valores nulos = sin dato).
class SerieLinea {
  final String nombre;
  final List<double?> valores;
  final Color color;
  final bool area;
  const SerieLinea({
    required this.nombre,
    required this.valores,
    required this.color,
    this.area = false,
  });
}

String _abrev(double v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (a >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

/// Valor legible para tooltips: conserva decimales utiles en costos pequenos.
String _valorDetalle(double v) {
  final a = v.abs();
  if (a == 0) return '0';
  if (a < 10) return v.toStringAsFixed(4);
  if (a < 1000) return v.toStringAsFixed(2);
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(2)} M';
  if (a >= 1000) return '${(v / 1000).toStringAsFixed(2)} k';
  return v.toStringAsFixed(1);
}

double _techo(Iterable<double?> vals) {
  double max = 0;
  for (final v in vals) {
    if (v != null && v > max) max = v;
  }
  return max <= 0 ? 1 : max * 1.15;
}

FlTitlesData _titulos(
  List<String> etiquetasX, {
  required bool visibles,
  int cada = 5,
  double reservaIzq = 46,
  bool texto = true,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: visibles,
        reservedSize: reservaIzq,
        getTitlesWidget: (v, meta) => texto
            ? Text(_abrev(v),
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF8A94A6)))
            : const SizedBox.shrink(),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: visibles,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (v, meta) {
          if (!texto) return const SizedBox.shrink();
          final i = v.round() - 1;
          if (i < 0 || i >= etiquetasX.length) return const SizedBox.shrink();
          if (cada > 1 && i % cada != 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(etiquetasX[i],
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF8A94A6))),
          );
        },
      ),
    ),
  );
}

/// Grafica de lineas con multiples series.
class GraficaLineas extends StatelessWidget {
  final List<SerieLinea> series;
  final List<String> etiquetasX;
  final double altura;
  final int etiquetaCada;
  final bool curva;
  /// Dibuja un punto en cada valor. La factura "Generación y costo promedio"
  /// se muestra de puntos (como el HTML/PDF), no solo como linea.
  final bool mostrarPuntos;
  final double radioPuntos;
  final String Function(double)? formatoValor;

  const GraficaLineas({
    super.key,
    required this.series,
    required this.etiquetasX,
    this.altura = 260,
    this.etiquetaCada = 5,
    this.curva = true,
    this.mostrarPuntos = false,
    this.radioPuntos = 3.4,
    this.formatoValor,
  });

  @override
  Widget build(BuildContext context) {
    final conDatos = series.where((s) => s.valores.any((v) => v != null)).toList();
    if (conDatos.isEmpty) {
      return SizedBox(
          height: altura,
          child: const Center(child: Text('Sin datos para graficar')));
    }
    final techo = _techo(conDatos.expand((s) => s.valores));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: altura,
          child: LineChart(
            LineChartData(
              minX: 1,
              maxX: etiquetasX.length.toDouble(),
              minY: 0,
              maxY: techo,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: techo / 4,
              ),
              borderData: FlBorderData(show: false),
              titlesData: _titulos(etiquetasX, visibles: true, cada: etiquetaCada),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colors.white,
                  tooltipBorder: const BorderSide(color: Color(0xFFD3DBE4)),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.barIndex < conDatos.length ? conDatos[s.barIndex].nombre : ''}\n'
                        '${(formatoValor ?? _valorDetalle)(s.y)}',
                        const TextStyle(
                            color: Color(0xFF1F2933),
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final s in conDatos)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < s.valores.length; i++)
                        if (s.valores[i] != null) FlSpot((i + 1).toDouble(), s.valores[i]!),
                    ],
                    isCurved: curva,
                    color: s.color,
                    barWidth: 2.4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: mostrarPuntos,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: radioPuntos,
                        color: s.color,
                        strokeWidth: 1.2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: s.area,
                      color: s.color.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final s in conDatos) _Leyenda(color: s.color, texto: s.nombre),
          ],
        ),
      ],
    );
  }
}

/// Grafica de barras verticales.
class GraficaBarrasFl extends StatelessWidget {
  final List<double?> valores;
  final List<String> etiquetasX;
  final Color color;
  final List<Color>? colores;
  final double altura;
  final int etiquetaCada;
  final bool permitirNegativos;

  const GraficaBarrasFl({
    super.key,
    required this.valores,
    required this.etiquetasX,
    this.color = _azul,
    this.colores,
    this.altura = 240,
    this.etiquetaCada = 5,
    this.permitirNegativos = false,
  });

  @override
  Widget build(BuildContext context) {
    if (valores.every((v) => v == null)) {
      return SizedBox(
          height: altura,
          child: const Center(child: Text('Sin datos para graficar')));
    }
    final techo = _techo(valores);
    double piso = 0;
    if (permitirNegativos) {
      for (final v in valores) {
        if (v != null && v < piso) piso = v;
      }
      piso = piso < 0 ? piso * 1.25 : 0;
    }
    final ancho = valores.length > 20
        ? 6.0
        : valores.length > 8
            ? 14.0
            : 30.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: altura,
          child: BarChart(
            BarChartData(
              minY: piso,
              maxY: techo,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (techo - piso) / 4,
              ),
              borderData: FlBorderData(show: false),
              titlesData: _titulos(etiquetasX, visibles: true, cada: etiquetaCada),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.white,
                  tooltipBorder: const BorderSide(color: Color(0xFFD3DBE4)),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final i = group.x - 1;
                    final etq = i >= 0 && i < etiquetasX.length ? etiquetasX[i] : '';
                    return BarTooltipItem(
                      '$etq\n${_valorDetalle(rod.toY)}',
                      const TextStyle(
                          color: Color(0xFF1F2933),
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < valores.length; i++)
                  BarChartGroupData(
                    x: i + 1,
                    barRods: [
                      if (valores[i] != null)
                        BarChartRodData(
                          toY: valores[i]!,
                          color: (colores != null && i < colores!.length)
                              ? colores![i]
                              : color,
                          width: ancho,
                          borderRadius: BorderRadius.circular(3),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Grafica combinada: barras diarias (real + proyeccion) con linea del mes cerrado.
class GraficaEvolucion extends StatelessWidget {
  final List<double?> real;
  final List<double?> proyectado;
  final List<double?> cerrado;
  final List<String> etiquetasX;
  final double altura;

  const GraficaEvolucion({
    super.key,
    required this.real,
    required this.proyectado,
    required this.cerrado,
    required this.etiquetasX,
    this.altura = 300,
  });

  @override
  Widget build(BuildContext context) {
    final techo = _techo([...real, ...proyectado, ...cerrado]);
    final n = etiquetasX.length.toDouble();
    // BarChart centra la barra i en el pixel W*(i+0.5)/N; con minX=0 y maxX=N, la
    // linea en x=i+0.5 cae exactamente en el mismo pixel (barras y linea alineadas).
    final maxX = n;

    final barData = BarChartData(
      minY: 0,
      maxY: techo,
      alignment: BarChartAlignment.spaceAround,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: techo / 4,
      ),
      borderData: FlBorderData(show: false),
      titlesData: _titulos(etiquetasX, visibles: true, cada: 5),
      barTouchData: BarTouchData(enabled: true),
      barGroups: [
        for (var i = 0; i < etiquetasX.length; i++)
          BarChartGroupData(
            x: i + 1,
            barRods: [
              if (real.length > i && real[i] != null)
                BarChartRodData(
                  toY: real[i]!,
                  color: _azul,
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                )
              else if (proyectado.length > i && proyectado[i] != null)
                BarChartRodData(
                  toY: proyectado[i]!,
                  color: _ambar.withValues(alpha: 0.45),
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                ),
            ],
          ),
      ],
    );

    final lineData = LineChartData(
      minX: 0,
      maxX: maxX,
      minY: 0,
      maxY: techo,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      // Mismos tamanos reservados (sin texto) para alinear con las barras.
      titlesData: _titulos(etiquetasX, visibles: true, cada: 5, texto: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < cerrado.length; i++)
              if (cerrado[i] != null) FlSpot(i + 0.5, cerrado[i]!),
          ],
          isCurved: true,
          color: _morado,
          barWidth: 2.4,
          dotData: const FlDotData(show: false),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: altura,
          child: Stack(
            children: [
              BarChart(barData),
              LineChart(lineData),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: const [
            _Leyenda(color: _azul, texto: 'Mes en curso'),
            _Leyenda(color: _ambar, texto: 'Proyección'),
            _Leyenda(color: _morado, texto: 'Mes cerrado'),
          ],
        ),
      ],
    );
  }
}

/// Barras horizontales (para el top de agentes).
class BarrasHorizontales extends StatelessWidget {
  final List<(String, double)> items;
  final Color color;
  final String Function(double)? formato;

  const BarrasHorizontales({
    super.key,
    required this.items,
    this.color = _verde,
    this.formato,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Sin datos para graficar')),
      );
    }
    final maximo = items.map((e) => e.$2).fold<double>(0, (a, b) => b > a ? b : a);
    final techo = maximo <= 0 ? 1.0 : maximo;
    return Column(
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    it.$1,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        Container(
                          height: 18,
                          width: (c.maxWidth * (it.$2 / techo)).clamp(2.0, c.maxWidth),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              color,
                              color.withValues(alpha: 0.7),
                            ]),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 72,
                  child: Text(
                    (formato ?? _abrev)(it.$2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Barras (eje izq.) + linea (eje der.) con doble escala.
///
/// Pensada para la variante "Generacion y costo promedio": barras de consumo
/// en kWh y linea del costo promedio B/./kWh sobre un segundo eje vertical.
class GraficaCombinadaFl extends StatelessWidget {
  final List<double?> barras;
  final List<double?> linea;
  final List<String> etiquetasX;
  final String etiquetaBarra;
  final String etiquetaLinea;
  final Color colorBarra;
  final Color colorLinea;
  final double altura;
  final int etiquetaCada;

  const GraficaCombinadaFl({
    super.key,
    required this.barras,
    required this.linea,
    required this.etiquetasX,
    this.etiquetaBarra = 'Consumo',
    this.etiquetaLinea = 'Costo promedio',
    this.colorBarra = _azul,
    this.colorLinea = _ambar,
    this.altura = 260,
    this.etiquetaCada = 1,
  });

  @override
  Widget build(BuildContext context) {
    final vl = linea.whereType<double>().toList();
    if (!barras.any((v) => v != null) && vl.isEmpty) {
      return SizedBox(
          height: altura, child: const Center(child: Text('Sin datos para graficar')));
    }
    final techo = _techo(barras);
    final maxLin = vl.isEmpty ? 0.0 : vl.reduce((a, b) => a > b ? a : b);
    final topeLin = maxLin <= 0 ? 1.0 : maxLin * 1.2;
    final escala = techo / topeLin; // valor del costo -> escala de barras

    final barChart = BarChart(
      BarChartData(
        minY: 0,
        maxY: techo,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: techo / 4,
          getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE6EBF1), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 54,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (v, meta) => Text(_abrev(v),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF8A94A6))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round() - 1;
                if (i < 0 || i >= etiquetasX.length) return const SizedBox.shrink();
                if (etiquetaCada > 1 && i % etiquetaCada != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(etiquetasX[i],
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF8A94A6))),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorder: const BorderSide(color: Color(0xFFD3DBE4)),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final i = group.x - 1;
              final etq = i >= 0 && i < etiquetasX.length ? etiquetasX[i] : '';
              return BarTooltipItem(
                '$etq\n${_valorDetalle(rod.toY)} $etiquetaBarra',
                const TextStyle(
                    color: Color(0xFF1F2933),
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < barras.length; i++)
            BarChartGroupData(
              x: i + 1,
              barRods: [
                if (barras[i] != null)
                  BarChartRodData(
                    toY: barras[i]!,
                    color: colorBarra,
                    width: barras.length > 20 ? 6 : 22,
                    borderRadius: BorderRadius.circular(3),
                  ),
              ],
            ),
        ],
      ),
    );

    final lineChart = LineChart(
      LineChartData(
        minX: 0,
        maxX: barras.length.toDouble(),
        minY: 0,
        maxY: techo,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 54,
              getTitlesWidget: (v, _) => Text(
                (v / escala).toStringAsFixed(3),
                style: const TextStyle(fontSize: 10, color: Color(0xFFB07A20)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < linea.length; i++)
                if (linea[i] != null) FlSpot(i + 0.5, linea[i]! * escala),
            ],
            isCurved: false,
            color: colorLinea,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 2.6,
                color: colorLinea,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: altura,
          child: Stack(children: [barChart, lineChart]),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            etiqueta2(colorBarra, etiquetaBarra),
            if (linea.any((v) => v != null)) etiqueta2(colorLinea, etiquetaLinea),
          ],
        ),
      ],
    );
  }

  Widget etiqueta2(Color color, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _Leyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
