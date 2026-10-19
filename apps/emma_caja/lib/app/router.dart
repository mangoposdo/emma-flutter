import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/caja/caja_view.dart';
import '../features/clientes/clientes_view.dart';
import '../features/compras/compras_view.dart';
import '../features/configuracion/configuracion_view.dart';
import '../features/entrar/entrar_view.dart';
import '../features/productos/productos_view.dart';
import '../features/reportes/reportes_view.dart';
import '../features/usuarios/usuarios_view.dart';
import '../features/ventas/ventas_view.dart';
import '../shell/shell_view.dart';
import 'providers.dart';

/// Las pantallas del menú, en el orden de la 0.7.
enum Pantalla {
  ventas('/', 'Ventas  (F1)'),
  productos('/productos', 'Productos'),
  compras('/compras', 'Compras', soloDueno: true),
  clientes('/clientes', 'Clientes y fiado'),
  caja('/caja', 'Caja y cuadre'),
  reportes('/reportes', 'Reportes', soloDueno: true),
  usuarios('/usuarios', 'Usuarios', soloDueno: true),
  configuracion('/configuracion', 'Configuración', soloDueno: true);

  const Pantalla(this.ruta, this.titulo, {this.soloDueno = false});

  final String ruta;
  final String titulo;

  /// El cajero no ve las pantallas de administración.
  final bool soloDueno;

  static Pantalla de(String ruta) => values.firstWhere((p) => p.ruta == ruta, orElse: () => ventas);
}

final routerProvider = Provider<GoRouter>((ref) {
  final cambio = ValueNotifier(0);
  ref.listen(sesionProvider, (_, __) => cambio.value++);
  ref.onDispose(cambio.dispose);

  Page<void> pagina(Widget w) => NoTransitionPage(child: w);

  return GoRouter(
    initialLocation: '/entrar',
    refreshListenable: cambio,
    redirect: (context, state) {
      final sesion = ref.read(sesionProvider);
      final enEntrar = state.matchedLocation == '/entrar';
      if (sesion == null) return enEntrar ? null : '/entrar';
      if (enEntrar) return Pantalla.ventas.ruta;
      if (!sesion.esDueno && Pantalla.de(state.matchedLocation).soloDueno) return Pantalla.ventas.ruta;
      return null;
    },
    routes: [
      GoRoute(path: '/entrar', pageBuilder: (_, __) => pagina(const EntrarView())),
      ShellRoute(
        builder: (context, state, child) => ShellView(pantalla: Pantalla.de(state.matchedLocation), child: child),
        routes: [
          for (final p in Pantalla.values)
            GoRoute(
              path: p.ruta,
              // Cada vez que se entra a una pantalla se carga de nuevo, como en la 0.7.
              pageBuilder: (_, __) => pagina(switch (p) {
                Pantalla.ventas => const VentasView(),
                Pantalla.productos => const ProductosView(),
                Pantalla.compras => const ComprasView(),
                Pantalla.clientes => const ClientesView(),
                Pantalla.caja => const CajaView(),
                Pantalla.reportes => const ReportesView(),
                Pantalla.usuarios => const UsuariosView(),
                Pantalla.configuracion => const ConfiguracionView(),
              }),
            ),
        ],
      ),
    ],
  );
});
