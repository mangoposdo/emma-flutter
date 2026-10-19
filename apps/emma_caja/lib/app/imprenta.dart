import 'dart:typed_data';

import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

final imprentaProvider = Provider((ref) => Imprenta(ref));

/// Los tickets que salen por la impresora configurada en Configuración.
/// Si no hay impresora, no hace nada. Cada método devuelve null si salió bien
/// (o no hay impresora) o el mensaje para mostrar si falló.
class Imprenta {
  Imprenta(this._ref);

  final Ref _ref;

  Future<NegocioRow> _negocio() => _ref.read(negocioServiceProvider).negocio();

  static bool _hay(NegocioRow n) => (n.impresora ?? '').trim().isNotEmpty;

  Future<bool> hayImpresora() async => _hay(await _negocio());

  Future<String?> imprimir(Uint8List datos, {String nota = ''}) async {
    final n = await _negocio();
    if (!_hay(n)) return null;
    return enviar(n.impresora!, datos, nota: nota);
  }

  /// A una impresora en particular (la prueba de Configuración).
  Future<String?> enviar(String impresora, Uint8List datos, {String nota = ''}) async {
    try {
      await _ref.read(impresoraProvider).enviarRaw(impresora, datos);
      return null;
    } catch (e) {
      return 'No se pudo imprimir en "$impresora". Revise que la impresora esté encendida y con papel.$nota\n\n$e';
    }
  }

  Future<String?> abrirGaveta() => imprimir(TicketEscPos.abrirGaveta);

  /// El ticket de una venta. Si la impresora falla, la venta ya está guardada
  /// y el ticket queda pendiente para el botón amarillo.
  Future<String?> imprimirVenta(int ventaId) async {
    final ventas = _ref.read(ventaServiceProvider);
    final n = await _negocio();
    if (!_hay(n)) {
      // Sin impresora no se espera ningún ticket.
      await ventas.marcarTicketPendiente(ventaId, pendiente: false);
      return null;
    }
    final v = await ventas.porId(ventaId);
    if (v == null) return null;
    final deuda = v.venta.formaPago == FormaPago.fiado && v.venta.clienteId != null
        ? await _ref.read(fiadoServiceProvider).balance(v.venta.clienteId!)
        : null;
    final error = await enviar(
      n.impresora!,
      TicketEscPos.venta(n, TicketVenta.de(v), deudaCliente: deuda),
      nota: '\n\nLa venta quedó guardada. El ticket queda pendiente: imprímalo con el botón amarillo cuando la impresora esté lista.',
    );
    await ventas.marcarTicketPendiente(ventaId, pendiente: error != null);
    return error;
  }

  Future<String?> imprimirCierre(int turnoId) async {
    final n = await _negocio();
    if (!_hay(n)) return null;
    return enviar(n.impresora!, TicketEscPos.cierreCaja(n, await _ref.read(cajaServiceProvider).resumen(turnoId)));
  }

  Future<String?> imprimirAbono({required String cliente, required int monto, required int balance, required DateTime fecha}) async {
    final n = await _negocio();
    if (!_hay(n)) return null;
    final cajero = _ref.read(sesionProvider)?.nombre ?? '';
    return enviar(
      n.impresora!,
      TicketEscPos.abono(n, cliente: cliente, monto: monto, balance: balance, fecha: fecha, cajero: cajero),
    );
  }

  /// La comanda que lleva el repartidor.
  Future<String?> imprimirComanda(TicketAbierto pedido) async {
    final n = await _negocio();
    if (!_hay(n)) return null;
    final d = _ref.read(deliveryServiceProvider);
    return enviar(
      n.impresora!,
      TicketEscPos.comanda(n, pedido, await d.lineasComanda(pedido), await d.total(pedido)),
      nota: '\n\nEl delivery quedó despachado. Puede reimprimir la comanda en "En la calle".',
    );
  }
}
