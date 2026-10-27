import 'package:flutter/material.dart';

import '../models.dart';
import '../services/preferencias.dart';

/// Encabezado de seccion con titulo, subtitulo y acciones.
class EncabezadoSeccion extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;
  final IconData? icono;

  const EncabezadoSeccion({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones = const [],
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(icono, color: tema.colorScheme.primary, size: 24),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titulo,
                      style: tema.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  if (subtitulo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitulo!,
                          style: tema.textTheme.bodySmall
                              ?.copyWith(color: tema.colorScheme.outline)),
                    ),
                ],
              ),
            ],
          ),
          Row(mainAxisSize: MainAxisSize.min, children: acciones),
        ],
      ),
    );
  }
}

/// Tarjeta contenedora con padding.
class Tarjeta extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin ?? EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Tarjeta de indicador (KPI).
class TarjetaKpi extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final String? pie;
  final VoidCallback? alTocar;

  const TarjetaKpi({
    super.key,
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
    this.pie,
    this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: alTocar,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.outline,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(valor,
                          maxLines: 1,
                          style: tema.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    ),
                    if (pie != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          pie!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.labelSmall
                              ?.copyWith(color: tema.colorScheme.outline),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de estado con color.
class EstadoChip extends StatelessWidget {
  final String texto;
  final Color color;
  const EstadoChip(this.texto, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(texto,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Grafica de barras simple (sin dependencias externas).
class GraficaBarras extends StatelessWidget {
  final List<PuntoSerie> serie;
  final double altura;
  final Color color;
  final String Function(double)? formatoValor;

  const GraficaBarras({
    super.key,
    required this.serie,
    this.altura = 220,
    this.color = const Color(0xFF315C8A),
    this.formatoValor,
  });

  @override
  Widget build(BuildContext context) {
    if (serie.isEmpty) {
      return SizedBox(
        height: altura,
        child: const Center(child: Text('Sin datos para graficar')),
      );
    }
    final maximo = serie.map((p) => p.valor).fold<double>(0, (a, b) => b > a ? b : a);
    final techo = maximo <= 0 ? 1.0 : maximo * 1.15;

    return SizedBox(
      height: altura,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in serie)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      (formatoValor ?? _formato)(p.valor),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: (p.valor.clamp(0, techo)) / techo,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color, color.withValues(alpha: 0.65)],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.etiqueta,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formato(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

/// Estado vacio.
class EstadoVacio extends StatelessWidget {
  final String mensaje;
  final IconData icono;
  final Widget? accion;
  const EstadoVacio({super.key, required this.mensaje, this.icono = Icons.inbox_outlined, this.accion});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 56, color: tema.colorScheme.outline.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(mensaje, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.outline)),
          if (accion != null) ...[const SizedBox(height: 16), accion!],
        ],
      ),
    );
  }
}

/// Vista de error con reintento.
class ErrorVista extends StatelessWidget {
  final String error;
  final VoidCallback alReintentar;
  const ErrorVista({super.key, required this.error, required this.alReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formato de moneda B/.
String fmtMoneda(num v) {
  final s = v.toStringAsFixed(2);
  final partes = s.split('.');
  final entero = partes[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'B/. $entero.${partes[1]}';
}

String fmtNumero(num v, {int decimales = 0}) {
  final s = v.toStringAsFixed(decimales);
  final partes = s.split('.');
  final entero = partes[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return partes.length > 1 ? '$entero.${partes[1]}' : entero;
}

/// Formatea una fecha ISO (yyyy-MM-ddTHH:mm:ss) a 'dd/mm/aaaa'.
String fmtFecha(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_dos(d.day)}/${_dos(d.month)}/${d.year}';
}

/// Formatea fecha y hora ISO a 'dd/mm/aaaa HH:mm'.
String fmtFechaHora(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_dos(d.day)}/${_dos(d.month)}/${d.year} ${_dos(d.hour)}:${_dos(d.minute)}';
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// Selector de tema (sistema / claro / oscuro) para la barra superior.
class BotonTema extends StatelessWidget {
  const BotonTema({super.key});

  @override
  Widget build(BuildContext context) {
    final modo = Preferencias.I.tema;
    final icono = switch (modo) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema de la aplicación',
      icon: Icon(icono),
      initialValue: modo,
      onSelected: Preferencias.I.setTema,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: ThemeMode.system,
          child: Row(children: [
            Icon(Icons.brightness_auto_outlined, size: 18),
            SizedBox(width: 10),
            Text('Sistema'),
          ]),
        ),
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(children: [
            Icon(Icons.light_mode_outlined, size: 18),
            SizedBox(width: 10),
            Text('Claro'),
          ]),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(children: [
            Icon(Icons.dark_mode_outlined, size: 18),
            SizedBox(width: 10),
            Text('Oscuro'),
          ]),
        ),
      ],
    );
  }
}
