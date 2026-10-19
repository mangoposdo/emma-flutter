import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../formato.dart';
import '../sesion.dart';
import 'csv.dart';

class VentaDiaria {
  const VentaDiaria(this.dia, this.cantidad, this.total, this.ganancia);

  final DateTime dia;
  final int cantidad;

  /// Centavos.
  final int total;
  final int ganancia;
}

class ProductoVendido {
  const ProductoVendido(this.productoId, this.nombre, this.cantidad, this.total, this.ganancia);

  final int productoId;
  final String nombre;

  /// Milésimas.
  final int cantidad;

  /// Centavos.
  final int total;
  final int ganancia;
}

class ResumenPeriodo {
  const ResumenPeriodo({
    required this.desde,
    required this.hasta,
    required this.cantidadVentas,
    required this.total,
    required this.costo,
    required this.porFormaPago,
  });

  final DateTime desde;
  final DateTime hasta;
  final int cantidadVentas;

  /// Centavos.
  final int total;
  final int costo;
  final Map<FormaPago, int> porFormaPago;

  int get ganancia => total - costo;
  int get ticketPromedio => cantidadVentas == 0 ? 0 : (total + cantidadVentas ~/ 2) ~/ cantidadVentas;
}

class InventarioValorizado {
  const InventarioValorizado(this.costo, this.venta, this.productos);

  /// Centavos.
  final int costo;
  final int venta;
  final int productos;
}

enum EstadoRecurrencia { sinCompras, nuevo, alDia, atrasado, perdido }

/// Cada cuánto compra un cliente y si ya debería haber vuelto.
class RecurrenciaCliente {
  const RecurrenciaCliente({
    required this.cliente,
    this.compras = 0,
    this.total = 0,
    this.primera,
    this.ultima,
    this.cadaCuantosDias,
    this.diasSinVenir,
    required this.estado,
    this.productoFavorito = '',
  });

  final Cliente cliente;
  final int compras;

  /// Centavos.
  final int total;
  final DateTime? primera;
  final DateTime? ultima;

  /// Días promedio entre una compra y la siguiente, en décimas (75 = 7.5 días).
  /// null con menos de 2 días distintos de compra.
  final int? cadaCuantosDias;
  final int? diasSinVenir;
  final EstadoRecurrencia estado;
  final String productoFavorito;

  int get promedio => compras == 0 ? 0 : (total + compras ~/ 2) ~/ compras;

  String get estadoTexto => switch (estado) {
        EstadoRecurrencia.sinCompras => 'Sin compras',
        EstadoRecurrencia.nuevo => 'Nuevo',
        EstadoRecurrencia.alDia => 'Al día',
        EstadoRecurrencia.atrasado => 'No ha vuelto',
        EstadoRecurrencia.perdido => 'Perdido',
      };

  String get frecuenciaTexto {
    final d = cadaCuantosDias;
    if (d == null) return '';
    if (d <= 15) return 'Casi todos los días';
    return 'Cada ${(d + 5) ~/ 10} días';
  }
}

class ReporteService {
  ReporteService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  Future<List<(Venta, List<VentaLinea>)>> _ventas(DateTime desde, DateTime hasta) async {
    final ventas = await (db.select(db.ventas)
          ..where((v) =>
              v.anulada.equals(false) & v.fecha.isBiggerOrEqualValue(desde) & v.fecha.isSmallerThanValue(hasta)))
        .get();
    if (ventas.isEmpty) return [];
    final lineas = await (db.select(db.ventaLineas)..where((l) => l.ventaId.isIn(ventas.map((v) => v.id)))).get();
    final porVenta = <int, List<VentaLinea>>{};
    for (final l in lineas) {
      porVenta.putIfAbsent(l.ventaId, () => []).add(l);
    }
    return [for (final v in ventas) (v, porVenta[v.id] ?? const [])];
  }

  /// El descuento baja el total, no el costo.
  static int _costo(List<VentaLinea> lineas) => lineas.fold(0, (s, l) => s + totalLinea(l.costoUnitario, l.cantidad));

  Future<ResumenPeriodo> resumen(DateTime desde, DateTime hasta) async {
    final vs = await _ventas(desde, hasta);
    final porForma = <FormaPago, int>{};
    for (final (v, _) in vs) {
      porForma[v.formaPago] = (porForma[v.formaPago] ?? 0) + v.total;
    }
    return ResumenPeriodo(
      desde: desde,
      hasta: hasta,
      cantidadVentas: vs.length,
      total: vs.fold(0, (s, e) => s + e.$1.total),
      costo: vs.fold(0, (s, e) => s + _costo(e.$2)),
      porFormaPago: porForma,
    );
  }

  Future<List<VentaDiaria>> porDia(DateTime desde, DateTime hasta) async {
    final vs = await _ventas(desde, hasta);
    final dias = <DateTime, List<(Venta, List<VentaLinea>)>>{};
    for (final e in vs) {
      dias.putIfAbsent(soloDia(e.$1.fecha), () => []).add(e);
    }
    final claves = dias.keys.toList()..sort();
    return [
      for (final d in claves)
        VentaDiaria(
          d,
          dias[d]!.length,
          dias[d]!.fold(0, (s, e) => s + e.$1.total),
          dias[d]!.fold(0, (s, e) => s + e.$1.total - _costo(e.$2)),
        ),
    ];
  }

  Future<List<ProductoVendido>> masVendidos(DateTime desde, DateTime hasta, {int top = 20}) async {
    final vs = await _ventas(desde, hasta);
    final porProducto = <int, List<VentaLinea>>{};
    for (final (_, ls) in vs) {
      for (final l in ls) {
        porProducto.putIfAbsent(l.productoId, () => []).add(l);
      }
    }
    final res = [
      for (final e in porProducto.entries)
        ProductoVendido(
          e.key,
          e.value.first.descripcion,
          e.value.fold(0, (s, l) => s + l.cantidad),
          e.value.fold(0, (s, l) => s + l.total),
          e.value.fold(0, (s, l) => s + l.total - totalLinea(l.costoUnitario, l.cantidad)),
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return res.take(top).toList();
  }

  /// Valor del inventario a costo y a precio de venta.
  Future<InventarioValorizado> inventarioValorizado() async {
    final ps = await (db.select(db.productos)
          ..where((p) => p.activo.equals(true) & (p.codigo.isNull() | p.codigo.isNotIn(const [codigoVarios, codigoEnvio]))))
        .get();
    final con = ps.where((p) => p.existencia > 0);
    return InventarioValorizado(
      con.fold(0, (s, p) => s + totalLinea(p.costo, p.existencia)),
      con.fold(0, (s, p) => s + totalLinea(p.precio, p.existencia)),
      ps.length,
    );
  }

  /// Recurrencia de compra de los clientes en los últimos [dias] días.
  /// "No ha vuelto" = pasaron más del doble de sus días normales entre compras
  /// (mínimo 7); "Perdido" = más de 30 días y más de cuatro veces lo normal.
  Future<List<RecurrenciaCliente>> recurrencia({int dias = 180, bool soloFijos = false}) async {
    final hoy = soloDia(_reloj());
    final desde = hoy.subtract(Duration(days: dias));
    final clientes = await (db.select(db.clientes)
          ..where((c) => c.activo.equals(true) & (soloFijos ? c.esFijo.equals(true) : const Constant(true))))
        .get();
    final ventas = await (db.select(db.ventas)
          ..where((v) => v.anulada.equals(false) & v.clienteId.isNotNull() & v.fecha.isBiggerOrEqualValue(desde))
          ..orderBy([(v) => OrderingTerm.asc(v.fecha)]))
        .get();
    final lineas = ventas.isEmpty
        ? <VentaLinea>[]
        : await (db.select(db.ventaLineas)..where((l) => l.ventaId.isIn(ventas.map((v) => v.id)))).get();
    final lineasPorVenta = <int, List<VentaLinea>>{};
    for (final l in lineas) {
      lineasPorVenta.putIfAbsent(l.ventaId, () => []).add(l);
    }
    final porCliente = <int, List<Venta>>{};
    for (final v in ventas) {
      porCliente.putIfAbsent(v.clienteId!, () => []).add(v);
    }
    final internos = {'Varios', 'Envío a domicilio'};

    final res = <RecurrenciaCliente>[];
    for (final c in clientes) {
      final vs = porCliente[c.id];
      if (vs == null) {
        if (c.esFijo) res.add(RecurrenciaCliente(cliente: c, estado: EstadoRecurrencia.sinCompras));
        continue;
      }
      final diasCompra = vs.map((v) => soloDia(v.fecha)).toSet().toList()..sort();
      int? cada;
      if (diasCompra.length >= 2) {
        final total = diasCompra.last.difference(diasCompra.first).inDays;
        // En décimas, redondeado (igual que la 0.7: un decimal).
        cada = (total * 10 * 2 + (diasCompra.length - 1)) ~/ ((diasCompra.length - 1) * 2);
      }
      final sinVenir = hoy.difference(diasCompra.last).inDays;
      final normal = (cada ?? 70) < 10 ? 10 : (cada ?? 70); // décimas, mínimo 1 día
      final EstadoRecurrencia estado;
      if (cada == null && sinVenir <= 14) {
        estado = EstadoRecurrencia.nuevo;
      } else if (sinVenir > 30 && sinVenir * 10 > normal * 4) {
        estado = EstadoRecurrencia.perdido;
      } else if (sinVenir * 10 > (normal * 2 > 70 ? normal * 2 : 70)) {
        estado = EstadoRecurrencia.atrasado;
      } else {
        estado = EstadoRecurrencia.alDia;
      }
      final gastos = <String, int>{};
      for (final v in vs) {
        for (final l in lineasPorVenta[v.id] ?? const <VentaLinea>[]) {
          if (internos.contains(l.descripcion)) continue;
          gastos[l.descripcion] = (gastos[l.descripcion] ?? 0) + l.total;
        }
      }
      final favorito = gastos.isEmpty ? '' : (gastos.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      res.add(RecurrenciaCliente(
        cliente: c,
        compras: vs.length,
        total: vs.fold(0, (s, v) => s + v.total),
        primera: vs.first.fecha,
        ultima: vs.last.fecha,
        cadaCuantosDias: cada,
        diasSinVenir: sinVenir,
        estado: estado,
        productoFavorito: favorito,
      ));
    }
    res.sort((a, b) {
      final at = (b.estado == EstadoRecurrencia.atrasado ? 1 : 0).compareTo(a.estado == EstadoRecurrencia.atrasado ? 1 : 0);
      return at != 0 ? at : b.total.compareTo(a.total);
    });
    return res;
  }

  /// Las ventas del período en CSV para Excel.
  Future<String> exportarVentasCsv(DateTime desde, DateTime hasta) async {
    final q = db.select(db.ventas).join([
      leftOuterJoin(db.clientes, db.clientes.id.equalsExp(db.ventas.clienteId)),
      leftOuterJoin(db.usuarios, db.usuarios.id.equalsExp(db.ventas.usuarioId)),
    ])
      ..where(db.ventas.fecha.isBiggerOrEqualValue(desde) & db.ventas.fecha.isSmallerThanValue(hasta))
      ..orderBy([OrderingTerm.desc(db.ventas.id)]);
    final filas = await q.get();
    String fecha(DateTime f) =>
        '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')} '
        '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
    return armarCsv(
      const ['numero', 'fecha', 'cajero', 'cliente', 'forma_pago', 'subtotal', 'descuento', 'total', 'anulada'],
      [
        for (final f in filas)
          [
            '${f.readTable(db.ventas).id}',
            fecha(f.readTable(db.ventas).fecha),
            f.readTableOrNull(db.usuarios)?.nombre,
            f.readTableOrNull(db.clientes)?.nombre ?? f.readTable(db.ventas).nombreCliente,
            f.readTable(db.ventas).formaPago.etiqueta,
            montoCsv(f.readTable(db.ventas).subtotal),
            montoCsv(f.readTable(db.ventas).descuento),
            montoCsv(f.readTable(db.ventas).total),
            f.readTable(db.ventas).anulada ? 'si' : 'no',
          ],
      ],
    );
  }
}
