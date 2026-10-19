import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plataforma/impresora.dart';
import 'version.dart';

/// Providers del Model. La base y su carpeta se abren en `main` antes de la
/// primera pantalla y entran aquí como override.
final carpetaDatosProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('La carpeta de datos entra como override.'),
);

final baseDeDatosProvider = Provider<EmmaDatabase>(
  (ref) => throw UnimplementedError('La base se abre en main y entra como override.'),
);

final ventaServiceProvider = Provider((ref) => VentaService(ref.watch(baseDeDatosProvider)));
final productoServiceProvider = Provider((ref) => ProductoService(ref.watch(baseDeDatosProvider)));
final cajaServiceProvider = Provider((ref) => CajaService(ref.watch(baseDeDatosProvider)));
final fiadoServiceProvider = Provider((ref) => FiadoService(ref.watch(baseDeDatosProvider)));
final ticketServiceProvider = Provider((ref) => TicketService(ref.watch(baseDeDatosProvider)));
final deliveryServiceProvider = Provider((ref) => DeliveryService(ref.watch(baseDeDatosProvider)));
final compraServiceProvider = Provider((ref) => CompraService(ref.watch(baseDeDatosProvider)));
final usuarioServiceProvider = Provider((ref) => UsuarioService(ref.watch(baseDeDatosProvider)));
final reporteServiceProvider = Provider((ref) => ReporteService(ref.watch(baseDeDatosProvider)));
final negocioServiceProvider = Provider((ref) => NegocioService(ref.watch(baseDeDatosProvider)));
final mantenimientoServiceProvider = Provider((ref) => MantenimientoService(ref.watch(baseDeDatosProvider)));
final respaldoServiceProvider = Provider(
  (ref) => RespaldoService(ref.watch(baseDeDatosProvider), ref.watch(carpetaDatosProvider)),
);
final nubeServiceProvider = Provider((ref) => NubeService(ref.watch(baseDeDatosProvider), version: versionEmma));
final sincronizacionServiceProvider = Provider(
  (ref) => SincronizacionService(ref.watch(baseDeDatosProvider), ref.watch(nubeServiceProvider)),
);
final impresoraProvider = Provider<Impresora>((ref) => Impresora.delSistema());

/// Quién está usando la caja. null = pantalla de entrada.
final sesionProvider = NotifierProvider<SesionNotifier, Sesion?>(SesionNotifier.new);

class SesionNotifier extends Notifier<Sesion?> {
  @override
  Sesion? build() => null;

  void entrar(Sesion s) => state = s;
  void salir() => state = null;
}

extension SesionDeRef on Ref {
  /// La sesión de quien entró. Las pantallas solo se ven después de entrar.
  Sesion get sesion => read(sesionProvider) ?? (throw const EmmaError('Debe iniciar sesión.'));
}

/// El turno abierto, o null con la caja cerrada.
final turnoAbiertoProvider = FutureProvider<TurnoCaja?>((ref) => ref.watch(cajaServiceProvider).turnoAbierto());

/// Los datos del negocio (nombre, impresora, ticket...).
final negocioProvider = FutureProvider<NegocioRow>((ref) => ref.watch(negocioServiceProvider).negocio());

/// "Nube al día", "N datos por enviar a la nube", o vacío sin nube.
final estadoNubeProvider = FutureProvider<String>((ref) async {
  if (!await ref.watch(nubeServiceProvider).conectada()) return '';
  final n = await ref.watch(sincronizacionServiceProvider).pendientes();
  return n == 0 ? 'Nube al día' : '$n datos por enviar a la nube';
});

/// Después de vender, abonar, abrir o cerrar la caja: refresca lo que dice la
/// barra del menú.
void refrescarEstado(Ref ref) {
  ref.invalidate(turnoAbiertoProvider);
  ref.invalidate(estadoNubeProvider);
}
