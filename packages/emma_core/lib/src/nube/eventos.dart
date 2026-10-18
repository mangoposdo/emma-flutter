/// Tipos de evento y formato de fechas del contrato con la nube (PRD, "Contrato
/// con la nube existente"). No cambiar sin cambiar el servidor.
library;

abstract final class TipoEvento {
  static const ventaRegistrada = 'venta.registrada';
  static const ventaAnulada = 'venta.anulada';
  static const cajaCerrada = 'caja.cerrada';
  static const fiadoAbono = 'fiado.abono';
  static const deliverySalio = 'delivery.salio';
  static const deliveryDevuelto = 'delivery.devuelto';
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// ISO-8601 en la hora local del colmado, sin zona: `2026-10-18T10:30:05`.
/// El servidor la guarda tal cual, para que la web muestre la hora del ticket.
String fechaLocalIso(DateTime f) {
  final l = f.isUtc ? f.toLocal() : f;
  return '${l.year.toString().padLeft(4, '0')}-${_dos(l.month)}-${_dos(l.day)}'
      'T${_dos(l.hour)}:${_dos(l.minute)}:${_dos(l.second)}';
}
