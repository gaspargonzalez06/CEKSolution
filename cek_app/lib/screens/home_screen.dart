import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import 'agentes_screen.dart';
import 'analisis_clientes_screen.dart';
import 'analisis_screen.dart';
import 'automatizacion_screen.dart';
import 'clientes_screen.dart';
import 'comerciales_screen.dart';
import 'contratos_screen.dart';
import 'dashboard_screen.dart';
import 'descargas_screen.dart';
import 'distribuidores_screen.dart';
import 'estado_periodo_screen.dart';
import 'facturas_screen.dart';
import 'reclamaciones_screen.dart';
import 'usuarios_screen.dart';

class _Destino {
  final String titulo;
  final IconData icono;
  final Widget Function() builder;
  final bool Function(Sesion) visible;
  const _Destino(this.titulo, this.icono, this.builder, this.visible);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  int _nuevasReclamaciones = 0;

  @override
  void initState() {
    super.initState();
    _cargarReclamaciones();
  }

  Future<void> _cargarReclamaciones() async {
    if (!Sesion.I.puedeEditar) return;
    try {
      final r = await Api.I.get('/reclamaciones?estado=identificada') as List;
      if (mounted) setState(() => _nuevasReclamaciones = r.length);
    } catch (_) {
      // Silencioso: el badge es un aviso, no debe romper la navegación.
    }
  }

  Widget _iconoDestino(_Destino d) {
    final icono = Icon(d.icono);
    if (d.titulo == 'Reclamaciones' && _nuevasReclamaciones > 0) {
      return Badge(
        label: Text('$_nuevasReclamaciones'),
        child: icono,
      );
    }
    return icono;
  }

  List<_Destino> get _destinos {
    final s = Sesion.I;
    return [
      _Destino('Dashboard', Icons.dashboard_outlined, () => const DashboardScreen(),
          (x) => x.puedeEditar),
      _Destino('Descargas CND', Icons.cloud_download_outlined,
          () => const DescargasScreen(), (x) => x.puedeEditar),
      _Destino('Análisis mercado', Icons.insights_outlined, () => const AnalisisScreen(),
          (x) => x.puedeEditar),
      _Destino('Análisis clientes', Icons.query_stats_outlined,
          () => const AnalisisClientesScreen(), (x) => true),
      _Destino('Comerciales', Icons.assessment_outlined, () => const ComercialesScreen(),
          (x) => x.puedeEditar),
      _Destino('Agentes', Icons.groups_outlined, () => const AgentesScreen(),
          (x) => x.puedeEditar),
      _Destino('Distribuidores', Icons.storefront_outlined,
          () => const DistribuidoresScreen(), (x) => x.puedeEditar),
      _Destino('Clientes', Icons.people_alt_outlined, () => const ClientesScreen(),
          (x) => x.puedeEditar),
      _Destino('Contratos', Icons.description_outlined, () => const ContratosScreen(),
          (x) => x.puedeEditar),
      _Destino(s.puedeEditar ? 'Facturas' : 'Mis facturas',
          Icons.receipt_long_outlined, () => const FacturasScreen(), (x) => true),
      _Destino('Estado mensual', Icons.event_available_outlined,
          () => const EstadoPeriodoScreen(), (x) => x.puedeEditar),
      _Destino('Reclamaciones', Icons.gavel_outlined, () => const ReclamacionesScreen(),
          (x) => x.puedeEditar),
      _Destino('Usuarios', Icons.manage_accounts_outlined, () => const UsuariosScreen(),
          (x) => x.esAdmin),
      _Destino('Proceso masivo', Icons.cloud_sync_outlined,
          () => const AutomatizacionScreen(), (x) => x.puedeEditar),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sesion = Sesion.I;
    final destinos = _destinos.where((d) => d.visible(sesion)).toList();
    if (_index >= destinos.length) _index = 0;

    final ancho = MediaQuery.of(context).size.width;
    final usaRail = ancho >= 800;

    final contenido = destinos.isEmpty
        ? const Center(child: Text('Sin modulos disponibles'))
        : destinos[_index].builder();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt),
            const SizedBox(width: 8),
            const Text(AppConfig.appNombre),
            const SizedBox(width: 12),
            Text(destinos.isEmpty ? '' : destinos[_index].titulo,
                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 16)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('${sesion.usuario?.etiqueta ?? ''} (${sesion.usuario?.rol ?? ''})'),
            ),
          ),
          const BotonTema(),
          IconButton(
            tooltip: 'Cerrar sesion',
            icon: const Icon(Icons.logout),
            onPressed: () => Sesion.I.logout(),
          ),
        ],
      ),
      drawer: usaRail
          ? null
          : Drawer(
              child: ListView(
                children: [
                  DrawerHeader(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.semilla, AppTheme.verde],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.bolt, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Text('CEK',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Gestión del mercado eléctrico',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  for (var i = 0; i < destinos.length; i++)
                    ListTile(
                      leading: _iconoDestino(destinos[i]),
                      title: Text(destinos[i].titulo),
                      selected: i == _index,
                      onTap: () {
                        setState(() => _index = i);
                        Navigator.pop(context);
                        if (destinos[i].titulo == 'Reclamaciones') {
                          Future.delayed(const Duration(seconds: 2),
                              _cargarReclamaciones);
                        }
                      },
                    ),
                ],
              ),
            ),
      body: usaRail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    setState(() => _index = i);
                    if (destinos[i].titulo == 'Reclamaciones') {
                      Future.delayed(
                          const Duration(seconds: 2), _cargarReclamaciones);
                    }
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  useIndicator: true,
                  destinations: destinos
                      .map((d) => NavigationRailDestination(
                            icon: _iconoDestino(d),
                            label: Text(d.titulo),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: contenido),
              ],
            )
          : contenido,
    );
  }
}
