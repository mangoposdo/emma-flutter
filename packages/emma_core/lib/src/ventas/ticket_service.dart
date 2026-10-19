import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../sesion.dart';
import 'venta_service.dart';

/// Un producto de un pedido abierto, como se guarda en la base.
class LineaPedido {
  const LineaPedido({required this.productoId, required this.cantidad, this.precio, this.monto});

  final int productoId;

  /// Milésimas.
  final int cantidad;

  /// Solo los servicios ("Varios", envío): el monto que se cobra.
  final int? precio;

  /// Libra vendida por monto ("$50"): el total exacto.
  final int? monto;

  Map<String, Object?> toJson() => {
        'productoId': productoId,
        'cantidad': cantidad,
        if (precio != null) 'precio': precio,
        if (monto != null) 'monto': monto,
      };

  factory LineaPedido.fromJson(Map<String, Object?> j) => LineaPedido(
        productoId: j['productoId']! as int,
        cantidad: j['cantidad']! as int,
        precio: j['precio'] as int?,
        monto: j['monto'] as int?,
      );

  LineaPedido conCantidad(int c) => LineaPedido(productoId: productoId, cantidad: c, precio: precio);

  /// Total con el precio de hoy del producto.
  int totalCon(Producto p) {
    if (esServicio(p)) return totalLinea(precio ?? 0, cantidad);
    if (monto != null) return monto!;
    return totalLinea(p.precio, cantidad);
  }

  /// La línea lista para [VentaService.cobrar].
  LineaCobro aCobro(Producto p) {
    if (esServicio(p)) return LineaCobro.servicio(productoId: p.id, descripcion: p.nombre, monto: precio ?? 0);
    if (monto != null) {
      return LineaCobro.porMonto(productoId: p.id, descripcion: p.nombre, monto: monto!, precioUnitario: p.precio);
    }
    return LineaCobro(productoId: p.id, descripcion: p.nombre, cantidad: cantidad, precioUnitario: p.precio);
  }
}

/// Pedidos abiertos: varias ventas a medio hacer al mismo tiempo, guardadas en
/// la base. No se pierden si se va la luz o se cierra el programa.
class TicketService {
  TicketService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  /// Los que se están atendiendo en el mostrador (no los delivery en camino).
  Future<List<TicketAbierto>> abiertos() => (db.select(db.ticketsAbiertos)
        ..where((t) => t.estadoDelivery.isNull() | t.estadoDelivery.equalsValue(EstadoDelivery.enCamino).not())
        ..orderBy([(t) => OrderingTerm.asc(t.numero)]))
      .get();

  Future<TicketAbierto?> porId(int id) =>
      (db.select(db.ticketsAbiertos)..where((t) => t.id.equals(id))).getSingleOrNull();

  static List<LineaPedido> lineas(TicketAbierto t) => [
        for (final j in jsonDecode(t.lineas) as List<Object?>) LineaPedido.fromJson((j! as Map).cast<String, Object?>()),
      ];

  /// Guarda el pedido. Si [id] es null crea uno con el número libre más bajo
  /// (Pedido 1, Pedido 2...).
  Future<TicketAbierto> guardar(
    Sesion sesion, {
    int? id,
    String? nombreCliente,
    required List<LineaPedido> lineas,
    int? clienteId,
  }) async {
    final ahora = _reloj();
    return db.transaction(() async {
      var t = id == null ? null : await porId(id);
      if (t != null && t.estadoDelivery == EstadoDelivery.enCamino) {
        throw const DatoInvalido('Ese pedido ya salió con el delivery. Márquelo como devuelto para cambiarlo.');
      }
      final datos = TicketsAbiertosCompanion(
        nombreCliente: Value(_limpio(nombreCliente)),
        clienteId: Value(clienteId),
        lineas: Value(jsonEncode([for (final l in lineas) l.toJson()])),
        actualizado: Value(ahora),
      );
      if (t == null) {
        final usados = (await db.select(db.ticketsAbiertos).get()).map((x) => x.numero).toSet();
        var numero = 1;
        while (usados.contains(numero)) {
          numero++;
        }
        final nuevo = await db.into(db.ticketsAbiertos).insert(datos.copyWith(
              numero: Value(numero),
              usuarioId: Value(sesion.usuarioId),
              creado: Value(ahora),
            ));
        return (await porId(nuevo))!;
      }
      await (db.update(db.ticketsAbiertos)..where((x) => x.id.equals(t.id))).write(datos);
      return (await porId(t.id))!;
    });
  }

  Future<void> borrar(int id) => (db.delete(db.ticketsAbiertos)..where((t) => t.id.equals(id))).go();

  /// Total con los precios de hoy, más el envío.
  Future<int> total(TicketAbierto t) async {
    final ls = lineas(t);
    final productos = await _productos(ls.map((l) => l.productoId));
    final suma = ls.fold<int>(0, (s, l) => s + (productos[l.productoId] == null ? 0 : l.totalCon(productos[l.productoId]!)));
    return suma + t.cargoEnvio;
  }

  Future<Map<int, Producto>> _productos(Iterable<int> ids) async {
    final lista = ids.toSet().toList();
    if (lista.isEmpty) return {};
    final ps = await (db.select(db.productos)..where((p) => p.id.isIn(lista))).get();
    return {for (final p in ps) p.id: p};
  }

  /// "🛵 Doña Rosa" o "Pedido 2".
  static String titulo(TicketAbierto t) =>
      (t.esDelivery ? '🛵 ' : '') + (_limpio(t.nombreCliente) ?? 'Pedido ${t.numero}');

  static String? _limpio(String? s) {
    final x = s?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
