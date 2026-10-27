import 'package:flutter/material.dart';

/// Carcasa común de los formularios modales: encabezado con icono y título,
/// cuerpo desplazable y pie con las acciones. Unifica el diseño y el ancho de
/// TODOS los formularios de la app.
class FormDialogo extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final GlobalKey<FormState>? formKey;
  final List<Widget> cuerpo;
  final List<Widget> acciones;
  final double maxAncho;
  final double maxAlto;

  const FormDialogo({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.formKey,
    required this.cuerpo,
    this.acciones = const [],
    this.maxAncho = 780,
    this.maxAlto = 840,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final contenido = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cuerpo,
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxAncho, maxHeight: maxAlto),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icono, color: tema.colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: tema.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (subtitulo != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitulo!,
                                style: tema.textTheme.bodySmall
                                    ?.copyWith(color: tema.colorScheme.outline)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                child: formKey == null ? contenido : Form(key: formKey, child: contenido),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: acciones,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sección (tarjeta interior) de un formulario: título con icono, descripción
/// opcional y sus campos.
class SeccionFormulario extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String? descripcion;
  final List<Widget> hijos;

  const SeccionFormulario({
    super.key,
    required this.titulo,
    required this.icono,
    this.descripcion,
    required this.hijos,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final oscuro = tema.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: oscuro ? 0.42 : 0.52),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tema.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 18, color: tema.colorScheme.primary),
              const SizedBox(width: 8),
              Text(titulo,
                  style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          if (descripcion != null) ...[
            const SizedBox(height: 4),
            Text(descripcion!,
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: tema.colorScheme.outline)),
          ],
          const SizedBox(height: 16),
          ...hijos,
        ],
      ),
    );
  }
}

/// Distribuye campos en fila y, en pantallas angostas, los apila uno debajo de
/// otro (formularios responsivos).
class FilaCampos extends StatelessWidget {
  final List<Widget> campos;
  final double anchoMinimo;
  const FilaCampos({super.key, required this.campos, this.anchoMinimo = 620});

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    if (ancho < anchoMinimo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < campos.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            campos[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < campos.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(child: campos[i]),
        ],
      ],
    );
  }
}
