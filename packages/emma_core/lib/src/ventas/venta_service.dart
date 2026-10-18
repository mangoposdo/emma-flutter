import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../nube/eventos.dart';
import '../sesion.dart';

/// Una línea lista para cobrar. Cantidad en milésimas, montos en centavos.
class LineaCobro {
  const LineaCobro._({
    required this.productoId,
    required this.descripcion,
    required this.cantidad,
    required this.precioUnitario,
    required this.total,
  });

  /// Cantidad por precio (unidad o libra).
  factory LineaCobro({
    required int productoId,
    required String descripcion,
    required int cantidad,
    required int precioUnitario,
  }) =>
      LineaCobro._(
        productoId: productoId,
        descripcion: descripcion,
        cantidad: cantidad,
        precioUnitario: precioUnitario,
        total: totalLinea(precioUnitario, cantidad),
      );

  /// Producto por libra vendido por monto ("$50"): el total es el monto exacto
  /// y la cantidad se calcula.
  factory LineaCobro.porMonto({
    required int productoId,
    required String descripcion,
    required int monto,
    required int precioUnitario,
  }) =>
      LineaCobro._(
        productoId: productoId,
        descripcion: descripcion,
        cantidad: cantidadPorMonto(monto, precioUnitario),
        precioUnitario: precioUnitario,
        total: monto,
      );

  /// Venta suelta: un monto sin producto. No toca inventario.
  factory LineaCobro.varios(int monto) => LineaCobro._(
        productoId: null,
        descripcion: 'Varios',
        cantidad: milesimasPorUnidad,
        precioUnitario: monto,
        total: monto,
      );

  /// null = producto interno "Varios".
  final int? productoId;
  final String descripcion;
  final int cantidad;
  final int precioUnitario;
  final int total;
}

class SolicitudCobro {
  const SolicitudCobro({
    required this.lineas,
    required this.formaPago,
    this.descuento = 0,
    this.montoRecibido,
    this.clienteId,
    this.nombreCliente,
    this.ticketAbiertoId,
    this.esDelivery = false,
    this.repartidor,
    this.direccionEntrega,
    this.deliveryId,
  });

  final List<LineaCobro> lineas;
  final FormaPago formaPago;

  /// En pesos (centavos), no en por ciento.
  final int descuento;

  /// Solo efectivo. null = monto exacto (Enter con la casilla vacía).
  final int? montoRecibido;
  final int? clienteId;
  final String? nombreCliente;

  /// Pedido abierto que se cobra: se borra en la misma transacción.
  final int? ticketAbiertoId;
  final bool esDelivery;
  final String? repartidor;
  final String? direccionEntrega;
  final String? deliveryId;
}

class ResultadoCobro {
  const ResultadoCobro({
    required this.ventaId,
    required this.total,
    required this.montoRecibido,
    required this.devuelta,
    required this.formaPago,
  });

  final int ventaId;
  final int total;
  final int montoRecibido;
  final int devuelta;
  final FormaPago formaPago;

  /// La pantalla abre la gaveta solo si es efectivo (y si está activado).
  bool get abreGaveta => formaPago == FormaPago.efectivo;
}

/// Registrar, cobrar y anular ventas. Todo lo que cambia datos va en una
/// sola transacción: si algo falla, no queda nada a medias.
class VentaService {
  VentaService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  Future<ResultadoCobro> cobrar(Sesion sesion, SolicitudCobro s) async {
    if (s.lineas.isEmpty) throw const DatoInvalido('No hay productos en la venta.');
    for (final l in s.lineas) {
      if (l.cantidad <= 0 || l.total <= 0) {
        throw DatoInvalido('La línea "${l.descripcion}" tiene cantidad o monto en cero.');
      }
    }
    final subtotal = s.lineas.fold<int>(0, (a, l) => a + l.total);
    if (s.descuento < 0) throw const DatoInvalido('El descuento no puede ser negativo.');
    if (s.descuento > subtotal) {
      throw const DatoInvalido('El descuento no puede ser mayor que la venta.');
    }
    final total = subtotal - s.descuento;

    final int recibido;
    final int devuelta;
    switch (s.formaPago) {
      case FormaPago.efectivo:
        recibido = s.montoRecibido ?? total;
        if (recibido < total) {
          throw DatoInvalido('Falta dinero: el cliente dio ${formatoRD(recibido)} '
              'y la venta es ${formatoRD(total)}.');
        }
        devuelta = recibido - total;
      case FormaPago.tarjeta:
      case FormaPago.transferencia:
        recibido = total;
        devuelta = 0;
      case FormaPago.fiado:
        if (s.clienteId == null) {
          throw const DatoInvalido('Para fiar hay que escoger un cliente.');
        }
        recibido = 0;
        devuelta = 0;
    }

    final fecha = _reloj();

    return db.transaction(() async {
      final turno = await db.turnoAbierto();
      if (turno == null) throw const CajaCerrada();

      Cliente? cliente;
      if (s.clienteId != null) {
        cliente = await (db.select(db.clientes)..where((c) => c.id.equals(s.clienteId!)))
            .getSingleOrNull();
        if (cliente == null || !cliente.activo) {
          throw const DatoInvalido('Ese cliente no existe.');
        }
      }

      if (s.formaPago == FormaPago.fiado) {
        final debe = await db.deudaCliente(cliente!.id);
        final limite = cliente.limiteCredito;
        if (limite > 0 && debe + total > limite) {
          throw LimiteFiadoExcedido(debe: debe, limite: limite, quedaria: debe + total);
        }
      }

      final varios = await db.productoVarios();
      final productos = <int, Producto>{};
      for (final l in s.lineas) {
        final id = l.productoId ?? varios.id;
        if (productos.containsKey(id)) continue;
        final prod = await (db.select(db.productos)..where((p) => p.id.equals(id)))
            .getSingleOrNull();
        if (prod == null) {
          throw DatoInvalido('El producto "${l.descripcion}" ya no existe.');
        }
        productos[id] = prod;
      }

      final nombreCliente = cliente?.nombre ?? _limpio(s.nombreCliente);

      final ventaId = await db.into(db.ventas).insert(VentasCompanion.insert(
            fecha: fecha,
            usuarioId: sesion.usuarioId,
            turnoCajaId: turno.id,
            clienteId: Value(cliente?.id),
            nombreCliente: Value(nombreCliente),
            subtotal: subtotal,
            descuento: Value(s.descuento),
            total: total,
            formaPago: s.formaPago,
            montoRecibido: Value(recibido),
            devuelta: Value(devuelta),
            // Queda pendiente hasta que la impresora confirme
            // (marcarTicketImpreso). Si la app se cae antes, sigue pendiente.
            ticketPendiente: const Value(true),
            esDelivery: Value(s.esDelivery),
            repartidor: Value(_limpio(s.repartidor)),
            direccionEntrega: Value(_limpio(s.direccionEntrega)),
            deliveryId: Value(s.deliveryId),
          ));

      // Existencia en curso por producto, por si el mismo sale en dos líneas.
      final existencia = {for (final e in productos.entries) e.key: e.value.existencia};
      final lineasEvento = <Map<String, Object?>>[];

      for (final l in s.lineas) {
        final prod = productos[l.productoId ?? varios.id]!;
        final esVarios = prod.codigo == codigoVarios;
        final costo = esVarios ? 0 : prod.costo;

        await db.into(db.ventaLineas).insert(VentaLineasCompanion.insert(
              ventaId: ventaId,
              productoId: prod.id,
              descripcion: l.descripcion,
              cantidad: l.cantidad,
              precioUnitario: l.precioUnitario,
              costoUnitario: costo,
              total: l.total,
            ));

        if (!esVarios) {
          final nueva = existencia[prod.id]! - l.cantidad;
          existencia[prod.id] = nueva;
          await (db.update(db.productos)..where((p) => p.id.equals(prod.id)))
              .write(ProductosCompanion(existencia: Value(nueva)));
          await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
                productoId: prod.id,
                fecha: fecha,
                tipo: TipoMovInventario.venta,
                cantidad: -l.cantidad,
                existenciaResultante: nueva,
                referencia: Value('Venta #$ventaId'),
                usuarioId: Value(sesion.usuarioId),
              ));
        }

        lineasEvento.add({
          'ProductoId': prod.id,
          'Descripcion': l.descripcion,
          'Cantidad': cantidadJson(l.cantidad),
          'PrecioUnitario': montoJson(l.precioUnitario),
          'CostoUnitario': montoJson(costo),
          'Total': montoJson(l.total),
        });
      }

      if (s.formaPago == FormaPago.fiado) {
        await db.into(db.movimientosFiado).insert(MovimientosFiadoCompanion.insert(
              clienteId: cliente!.id,
              fecha: fecha,
              tipo: TipoMovFiado.cargo,
              monto: total,
              ventaId: Value(ventaId),
              turnoCajaId: Value(turno.id),
              usuarioId: Value(sesion.usuarioId),
            ));
      }

      if (s.descuento > 0) {
        await db.anotarBitacora(
          usuarioId: sesion.usuarioId,
          accion: 'Descuento',
          detalle: 'Venta #$ventaId: descuento de ${formatoRD(s.descuento)} '
              'sobre ${formatoRD(subtotal)}.',
          fecha: fecha,
        );
      }

      if (s.ticketAbiertoId != null) {
        await (db.delete(db.ticketsAbiertos)..where((t) => t.id.equals(s.ticketAbiertoId!))).go();
      }

      await db.encolarEvento(TipoEvento.ventaRegistrada, {
        'Id': ventaId,
        'Fecha': fechaLocalIso(fecha),
        'Total': montoJson(total),
        'Descuento': montoJson(s.descuento),
        'FormaPago': s.formaPago.etiqueta,
        'Cajero': sesion.nombre,
        'NombreCliente': nombreCliente,
        'ClienteId': cliente?.id,
        'EsDelivery': s.esDelivery,
        'Repartidor': _limpio(s.repartidor),
        'DeliveryId': s.deliveryId,
        'Lineas': lineasEvento,
      }, fecha);

      return ResultadoCobro(
        ventaId: ventaId,
        total: total,
        montoRecibido: recibido,
        devuelta: devuelta,
        formaPago: s.formaPago,
      );
    });
  }

  /// Solo el dueño. Devuelve el inventario, quita la deuda si fue fiado,
  /// anota en la bitácora y avisa a la nube.
  Future<void> anular(Sesion sesion, int ventaId, String motivo) async {
    if (!sesion.esDueno) throw const PermisoDenegado('Solo el dueño puede anular ventas.');
    final m = motivo.trim();
    if (m.isEmpty) throw const DatoInvalido('Escriba el motivo de la anulación.');
    final fecha = _reloj();

    await db.transaction(() async {
      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId)))
          .getSingleOrNull();
      if (venta == null) throw const DatoInvalido('Esa venta no existe.');
      if (venta.anulada) throw const DatoInvalido('Esa venta ya está anulada.');

      await (db.update(db.ventas)..where((v) => v.id.equals(ventaId))).write(VentasCompanion(
        anulada: const Value(true),
        fechaAnulacion: Value(fecha),
        anuladaPorId: Value(sesion.usuarioId),
        motivoAnulacion: Value(m),
      ));

      final lineas = await (db.select(db.ventaLineas)..where((l) => l.ventaId.equals(ventaId))).get();
      for (final l in lineas) {
        final prod = await (db.select(db.productos)..where((p) => p.id.equals(l.productoId)))
            .getSingle();
        if (prod.codigo == codigoVarios) continue;
        final nueva = prod.existencia + l.cantidad;
        await (db.update(db.productos)..where((p) => p.id.equals(prod.id)))
            .write(ProductosCompanion(existencia: Value(nueva)));
        await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
              productoId: prod.id,
              fecha: fecha,
              tipo: TipoMovInventario.anulacionVenta,
              cantidad: l.cantidad,
              existenciaResultante: nueva,
              referencia: Value('Anulación venta #$ventaId'),
              usuarioId: Value(sesion.usuarioId),
            ));
      }

      if (venta.formaPago == FormaPago.fiado && venta.clienteId != null) {
        await db.into(db.movimientosFiado).insert(MovimientosFiadoCompanion.insert(
              clienteId: venta.clienteId!,
              fecha: fecha,
              tipo: TipoMovFiado.anulacionCargo,
              monto: venta.total,
              ventaId: Value(ventaId),
              turnoCajaId: Value(venta.turnoCajaId),
              usuarioId: Value(sesion.usuarioId),
              nota: Value(m),
            ));
      }

      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Anular venta',
        detalle: 'Venta #$ventaId por ${formatoRD(venta.total)}. Motivo: $m',
        fecha: fecha,
      );

      await db.encolarEvento(TipoEvento.ventaAnulada, {
        'Id': ventaId,
        'Total': montoJson(venta.total),
        'MotivoAnulacion': m,
        'AnuladaPor': sesion.nombre,
        'Fecha': fechaLocalIso(fecha),
      }, fecha);
    });
  }

  /// Llamar cuando la impresora confirma el ticket.
  Future<void> marcarTicketImpreso(int ventaId) =>
      (db.update(db.ventas)..where((v) => v.id.equals(ventaId)))
          .write(const VentasCompanion(ticketPendiente: Value(false)));

  /// Para el botón amarillo "Imprimir tickets pendientes".
  Future<List<Venta>> ventasConTicketPendiente() => (db.select(db.ventas)
        ..where((v) => v.ticketPendiente.equals(true) & v.anulada.equals(false))
        ..orderBy([(v) => OrderingTerm.asc(v.id)]))
      .get();

  static String? _limpio(String? t) {
    final x = t?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
