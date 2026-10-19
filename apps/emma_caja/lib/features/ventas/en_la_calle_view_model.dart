import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/imprenta.dart';
import '../../app/providers.dart';

/// Lo que se escogió para cobrar un delivery que volvió (centavos).
class PagoDelivery {
  const PagoDelivery({required this.forma, this.recibido, this.descuento = 0, this.clienteFiadoId});

  final FormaPago forma;

  /// null = monto exacto.
  final int? recibido;
  final int descuento;
  final int? clienteFiadoId;
}

class EnLaCalleState {
  const EnLaCalleState({this.lista = const [], this.escogida});

  final List<DeliveryEnCamino> lista;
  final int? escogida;

  /// El escogido, o el único si hay uno solo.
  DeliveryEnCamino? get seleccionado =>
      escogida != null && escogida! < lista.length ? lista[escogida!] : (lista.length == 1 ? lista.single : null);

  String get resumen => lista.isEmpty
      ? 'No hay delivery en la calle.'
      : '${lista.length} en la calle  ·  Por cobrar: ${formatoRD(lista.fold(0, (s, d) => s + d.total))}  ·  '
          'Cambio que llevan: ${formatoRD(lista.fold(0, (s, d) => s + (d.cambio ?? 0)))}';
}

final enLaCalleViewModelProvider =
    AsyncNotifierProvider.autoDispose<EnLaCalleViewModel, EnLaCalleState>(EnLaCalleViewModel.new);

/// Los delivery que van en camino: cuánto hay que cobrar, con quién salió y hace cuánto.
class EnLaCalleViewModel extends AsyncNotifier<EnLaCalleState> {
  @override
  Future<EnLaCalleState> build() async => EnLaCalleState(lista: await ref.read(deliveryServiceProvider).enLaCalle());

  void escoger(int i) => state = AsyncData(EnLaCalleState(lista: state.requireValue.lista, escogida: i));

  Future<void> _recargar() async {
    final lista = await ref.read(deliveryServiceProvider).enLaCalle();
    if (ref.mounted) state = AsyncData(EnLaCalleState(lista: lista));
  }

  /// Cobra el delivery cuando el repartidor vuelve. Devuelve la venta.
  Future<VentaDetalle> cobrar(DeliveryEnCamino d, PagoDelivery p) async {
    final s = await ref.read(deliveryServiceProvider).solicitudDeCobro(
          d.pedido.id,
          forma: p.forma,
          recibido: p.recibido,
          descuento: p.descuento,
          clienteFiado: p.clienteFiadoId,
        );
    final r = await ref.read(ventaServiceProvider).cobrar(ref.sesion, s);
    await _recargar();
    return (await ref.read(ventaServiceProvider).porId(r.ventaId))!;
  }

  /// El repartidor volvió sin entregar: el pedido regresa al mostrador.
  Future<void> devolver(DeliveryEnCamino d, String motivo) async {
    await ref.read(deliveryServiceProvider).devolver(ref.sesion, d.pedido.id, motivo);
    await _recargar();
  }

  Future<String?> reimprimirComanda(DeliveryEnCamino d) => ref.read(imprentaProvider).imprimirComanda(d.pedido);

  /// Lo que debe el cliente y su límite, para el cobro con fiado.
  Future<String> creditoDe(int clienteId, int total) async {
    final c = await ref.read(fiadoServiceProvider).porId(clienteId);
    if (c == null) return '';
    final debe = await ref.read(fiadoServiceProvider).balance(clienteId);
    return c.limiteCredito > 0
        ? 'Debe ${formatoRD(debe)}. Límite ${formatoRD(c.limiteCredito)}. Después de esta compra debería ${formatoRD(debe + total)}.'
        : 'Debe ${formatoRD(debe)}. Sin límite de crédito. Después de esta compra debería ${formatoRD(debe + total)}.';
  }
}
