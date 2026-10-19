import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/imprenta.dart';
import '../../app/providers.dart';

/// Lo que trae la ventana de delivery al abrir.
class DeliveryState {
  const DeliveryState({
    required this.pedido,
    required this.subtotal,
    required this.repartidores,
    required this.envio,
    this.clienteId,
    this.aviso = 'Escriba el teléfono: si el cliente ya pidió antes, el nombre y la dirección salen solos.',
    this.nombre = '',
    this.telefono = '',
    this.direccion = '',
  });

  final TicketAbierto pedido;

  /// Productos sin el envío (centavos).
  final int subtotal;
  final List<String> repartidores;

  /// Envío que sale puesto (el del pedido o el de Configuración).
  final int envio;
  final int? clienteId;
  final String aviso;

  /// Lo que se llenó solo con un cliente de la lista.
  final String nombre;
  final String telefono;
  final String direccion;
}

final deliveryViewModelProvider =
    AsyncNotifierProvider.autoDispose.family<DeliveryViewModel, DeliveryState, int>(DeliveryViewModel.new);

/// Datos de entrega del pedido (F9): con el teléfono se llenan solos el nombre
/// y la dirección de los clientes que ya pidieron.
class DeliveryViewModel extends AsyncNotifier<DeliveryState> {
  DeliveryViewModel(this.ticketId);

  final int ticketId;

  DeliveryService get _delivery => ref.read(deliveryServiceProvider);

  @override
  Future<DeliveryState> build() async {
    final t = await ref.read(ticketServiceProvider).porId(ticketId);
    if (t == null) throw const DatoInvalido('El pedido ya no existe.');
    final total = await _delivery.total(t);
    var s = DeliveryState(
      pedido: t,
      subtotal: total - t.cargoEnvio,
      repartidores: await _delivery.repartidores(),
      envio: t.esDelivery ? t.cargoEnvio : (await ref.read(negocioServiceProvider).negocio()).cargoDelivery,
      clienteId: t.clienteId,
      nombre: t.nombreCliente ?? '',
      telefono: t.telefono ?? '',
      direccion: t.direccion ?? '',
    );
    if (t.clienteId != null && !t.esDelivery) {
      final c = await ref.read(fiadoServiceProvider).porId(t.clienteId!);
      if (c != null && c.activo) s = _llenar(s, c);
    }
    return s;
  }

  DeliveryState _llenar(DeliveryState s, Cliente c) => DeliveryState(
        pedido: s.pedido,
        subtotal: s.subtotal,
        repartidores: s.repartidores,
        envio: s.envio,
        clienteId: c.id,
        aviso: 'Cliente de la lista: ${c.nombre}${(c.notas ?? '').trim().isEmpty ? '' : '\nNota: ${c.notas}'}',
        nombre: s.nombre.trim().isEmpty ? c.nombre : s.nombre,
        direccion: s.direccion.trim().isEmpty
            ? [c.direccion, c.sector, c.referencia].where((x) => (x ?? '').trim().isNotEmpty).join(', ')
            : s.direccion,
        telefono: s.telefono.trim().isEmpty ? (c.telefono ?? '') : s.telefono,
      );

  /// Al salir del teléfono: si es de un cliente de la lista, llena lo que falte.
  Future<void> buscarTelefono({required String telefono, required String nombre, required String direccion}) async {
    final s = state.value;
    if (s == null || DeliveryService.soloNumeros(telefono).length < 7) return;
    final base = DeliveryState(
      pedido: s.pedido,
      subtotal: s.subtotal,
      repartidores: s.repartidores,
      envio: s.envio,
      clienteId: s.clienteId,
      aviso: s.aviso,
      nombre: nombre,
      telefono: telefono,
      direccion: direccion,
    );
    final c = await _delivery.clientePorTelefono(telefono);
    if (!ref.mounted) return;
    if (c == null) {
      state = AsyncData(s.clienteId == null
          ? DeliveryState(
              pedido: s.pedido,
              subtotal: s.subtotal,
              repartidores: s.repartidores,
              envio: s.envio,
              aviso: 'Cliente nuevo: se guarda en la lista de clientes fijos al despachar.',
              nombre: nombre,
              telefono: telefono,
              direccion: direccion,
            )
          : base);
      return;
    }
    state = AsyncData(_llenar(base, c));
  }

  /// Guarda los datos y, si [despachar], lo manda con el repartidor e imprime la
  /// comanda. [listo] dice si quedó guardado; [aviso] es lo que hay que mostrar
  /// (un problema de la impresora no deshace el despacho).
  Future<({bool listo, String? aviso})> guardar({
    required String nombre,
    required String telefono,
    required String direccion,
    required String pagaCon,
    required String envio,
    required String repartidor,
    required bool despachar,
  }) async {
    final s = state.requireValue;
    final cargo = envio.trim().isEmpty ? 0 : parsearMonto(envio);
    if (cargo == null) return (listo: false, aviso: 'Escriba un envío válido (o 0).');
    final paga = pagaCon.trim().isEmpty ? 0 : parsearMonto(pagaCon);
    if (paga == null) return (listo: false, aviso: 'Escriba con cuánto paga, o déjelo vacío.');
    if (despachar && paga > 0 && paga < s.subtotal + cargo) {
      return (listo: false, aviso: 'Con ${formatoRD(paga)} no alcanza: el pedido es ${formatoRD(s.subtotal + cargo)}.');
    }
    try {
      // Si cambiaron el teléfono por otro que no es de ese cliente, se busca de nuevo.
      final porTelefono = await _delivery.clientePorTelefono(telefono);
      await _delivery.preparar(
        ref.sesion,
        ticketId,
        DatosDelivery(
          nombre: nombre,
          telefono: telefono,
          direccion: direccion,
          pagaCon: paga > 0 ? paga : null,
          cargoEnvio: cargo,
          repartidor: repartidor,
          clienteId: porTelefono?.id ?? s.clienteId,
        ),
      );
      if (despachar) {
        final t = await _delivery.despachar(ref.sesion, ticketId, repartidor: repartidor);
        return (listo: true, aviso: await ref.read(imprentaProvider).imprimirComanda(t));
      }
      return (listo: true, aviso: null);
    } on EmmaError catch (e) {
      return (listo: false, aviso: e.mensaje);
    }
  }

  Future<void> quitarDelivery() => _delivery.quitarDelivery(ticketId);
}
