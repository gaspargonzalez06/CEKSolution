import 'package:flutter/material.dart';

/// Pantalla generica para modulos aun no implementados.
class PlaceholderScreen extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String descripcion;
  final List<String> puntos;

  const PlaceholderScreen({
    super.key,
    required this.titulo,
    required this.icono,
    required this.descripcion,
    this.puntos = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 72, color: tema.colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(titulo,
                  style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(descripcion, textAlign: TextAlign.center, style: tema.textTheme.bodyMedium),
              if (puntos.isNotEmpty) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Que incluira',
                            style: tema.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...puntos.map((p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle_outline, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(p)),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
