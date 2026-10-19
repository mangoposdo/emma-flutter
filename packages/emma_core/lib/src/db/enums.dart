/// Valores fijos que se guardan como texto en la base (se guarda `name`).
/// No cambiar el nombre de un valor sin una migración: rompe los datos guardados.
library;

enum Rol { dueno, cajero }

enum UnidadVenta { unidad, libra }

enum FormaPago { efectivo, tarjeta, transferencia, fiado }

extension FormaPagoTexto on FormaPago {
  /// Como lo espera la nube y como sale en el ticket.
  String get etiqueta => switch (this) {
        FormaPago.efectivo => 'Efectivo',
        FormaPago.tarjeta => 'Tarjeta',
        FormaPago.transferencia => 'Transferencia',
        FormaPago.fiado => 'Fiado',
      };
}

enum TipoMovInventario {
  venta,
  anulacionVenta,
  ajuste,
  perdida,
  compra,
  inventarioInicial,
}

enum TipoMovFiado { cargo, abono, anulacionCargo }

enum TipoMovCaja { entrada, salida }

/// Cómo se pagó una compra: con el efectivo de la caja, por fuera (banco,
/// dinero del dueño) o a crédito con el suplidor.
enum PagoCompra { deLaCaja, porFuera, credito }

enum EstadoDelivery { tomado, enCamino }

enum IntensidadTicket { normal, masOscura, maxima }
