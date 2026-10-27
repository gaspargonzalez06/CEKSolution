import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/abrir_url.dart';
import '../services/api.dart';
import '../widgets/comunes.dart';
import '../widgets/graficas.dart';
import 'facturas_screen.dart';

/// Resultado de generar la factura de varios clientes de una vez.
///
/// Muestra cada factura emitida junto con la grafica de consumo mensual del
/// cliente (misma fuente que la columna "Consumos": la tabla `mediciones`),
/// y los enlaces para ver la factura imprimible (HTML pagina 1 + pagina 2).
class FacturasLoteScreen extends StatefulWidget {
  final String periodo;
  final List<Factura> creadas;
  final List<Map<String, dynamic>> omitidas;
  final List<Map<String, dynamic>> errores;

  const FacturasLoteScreen({
    super.key,
    required this.periodo,
    required this.creadas,
    this.omitidas = const [],
    this.errores = const [],
  });

  @override
  State<FacturasLoteScreen> createState() => _FacturasLoteScreenState();
}

class _FacturasLoteScreenState extends State<FacturasLoteScreen> {
  final Map<int, Map<String, dynamic>> _series = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarSeries();
  }

  Future<void> _cargarSeries() async {
    for (final f in widget.creadas) {
      try {
        final r = await Api.I
            .get('/clientes/${f.idCliente}/consumo?hasta=${widget.periodo}');
        final m = Map<String, dynamic>.from(r);
        if (mounted) {
          setState(() => _series[f.idCliente] = m);
        }
      } catch (_) {
        // Sin serie: la tarjeta simplemente no muestra grafica.
      }
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.creadas.fold<double>(0, (a, f) => a + f.total);
    return Scaffold(
      appBar: AppBar(
        title: Text('Facturación ${widget.periodo}'),
      ),
      body: _cargando && widget.creadas.isNotEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                _resumen(total),
                const SizedBox(height: 16),
                if (widget.creadas.isNotEmpty) ...[
                  Text('Facturas generadas',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final f in widget.creadas) _tarjetaFactura(f),
                ],
                if (widget.omitidas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _lista('Omitidas (ya tenían factura del período)', widget.omitidas,
                      const Color(0xFFF0A020)),
                ],
                if (widget.errores.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _lista('Con error (no se emitieron)', widget.errores,
                      const Color(0xFFD84A43)),
                ],
              ],
            ),
    );
  }

  Widget _resumen(double total) {
    return Tarjeta(
      child: Row(
        children: [
          _kpi('Clientes seleccionados',
              '${widget.creadas.length + widget.omitidas.length + widget.errores.length}'),
          _kpi('Facturas emitidas', '${widget.creadas.length}',
              color: const Color(0xFF12B886)),
          _kpi('Omitidas', '${widget.omitidas.length}'),
          _kpi('Errores', '${widget.errores.length}',
              color: widget.errores.isEmpty ? null : const Color(0xFFD84A43)),
          _kpi('Total facturado', fmtMoneda(total),
              color: const Color(0xFF315C8A)),
        ],
      ),
    );
  }

  Widget _kpi(String titulo, String valor, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 4),
          Text(valor,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _tarjetaFactura(Factura f) {
    final serie = ((_series[f.idCliente]?['serie'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final valores = serie
        .map((s) => (s['kwh'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final etiquetas =
        serie.map((s) => '${s['etiqueta'] ?? ''}').toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.clienteNombre ?? 'Cliente ${f.idCliente}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${f.numero} · período ${f.periodo} · '
                          '${(f.consumoMwh ?? 0).toStringAsFixed(3)} MWh · '
                          '${fmtMoneda(f.total)}'),
                    ],
                  ),
                ),
                EstadoChip(f.estado, const Color(0xFF12B886)),
              ],
            ),
            const SizedBox(height: 12),
            if (valores.isNotEmpty)
              GraficaBarrasFl(
                valores: valores,
                etiquetasX: etiquetas,
                altura: 180,
                etiquetaCada: 1,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Sin datos de consumo para graficar'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => abrirEnNavegador(
                      '${AppConfig.apiBase}/facturas/${f.id}/html'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver / imprimir'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => FacturaDetalleScreen(id: f.id)),
                  ),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Detalle y gráficas'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista(String titulo, List<Map<String, dynamic>> filas, Color color) {
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 8),
          for (final r in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• ${r['cliente'] ?? r['id_cliente']}: ${r['motivo']}'),
            ),
        ],
      ),
    );
  }
}
