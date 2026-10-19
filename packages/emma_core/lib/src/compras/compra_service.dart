import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../nube/eventos.dart';
import '../sesion.dart';
import 'factura_leida.dart';

/// Un producto de la compra: cuánto entró (milésimas) y a cuánto se compró cada
/// uno (centavos). [precio] cambia el precio de venta si no es null.
/// [textoFactura] es cómo salía en la factura leída: al guardar, Emma lo
/// recuerda para ese suplidor.
class LineaCompra {
  const LineaCompra({required this.productoId, required this.cantidad, required this.costo, this.precio, this.textoFactura});

  final int productoId;
  final int cantidad;
  final int costo;
  final int? precio;
  final String? textoFactura;

  int get total => totalLinea(costo, cantidad);
}

class SolicitudCompra {
  const SolicitudCompra({this.suplidor, this.factura, this.pago = PagoCompra.deLaCaja, this.nota, required this.lineas});

  /// Nombre del suplidor; si no está en la lista se agrega. Vacío = sin suplidor.
  final String? suplidor;
  final String? factura;
  final PagoCompra pago;
  final String? nota;
  final List<LineaCompra> lineas;
}

/// Una compra con su suplidor y sus productos.
class CompraDetalle {
  const CompraDetalle(this.compra, this.suplidor, this.lineas);

  final Compra compra;
  final String? suplidor;
  final List<CompraLinea> lineas;
}

/// Registro de compras: lo que llega del suplidor sube la existencia, deja el
/// costo nuevo (para la ganancia) y, si se pagó con el efectivo de la caja,
/// sale de la caja para que el cuadre dé.
class CompraService {
  CompraService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  Future<List<Suplidor>> suplidores() => (db.select(db.suplidores)
        ..where((s) => s.activo.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.nombre)]))
      .get();

  Future<Compra> registrar(Sesion sesion, SolicitudCompra s) async {
    requiereDueno(sesion.esDueno, 'registrar compras');
    if (s.lineas.isEmpty) throw const DatoInvalido('La compra no tiene productos.');
    if (s.lineas.any((l) => l.cantidad <= 0)) {
      throw const DatoInvalido('Todas las cantidades deben ser mayores que cero.');
    }
    if (s.lineas.any((l) => l.costo < 0)) throw const DatoInvalido('El costo no puede ser negativo.');
    if (s.lineas.any((l) => l.precio != null && l.precio! <= 0)) {
      throw const DatoInvalido('El precio de venta debe ser mayor que cero.');
    }
    final ahora = _reloj();

    return db.transaction(() async {
      int? suplidorId;
      String? nombreSuplidor;
      final ns = _limpio(s.suplidor);
      if (ns != null) {
        final existe = await (db.select(db.suplidores)..where((x) => x.nombre.equals(ns))).getSingleOrNull();
        if (existe == null) {
          suplidorId = await db.into(db.suplidores).insert(SuplidoresCompanion.insert(nombre: ns));
        } else {
          suplidorId = existe.id;
          await (db.update(db.suplidores)..where((x) => x.id.equals(existe.id)))
              .write(const SuplidoresCompanion(activo: Value(true)));
        }
        nombreSuplidor = ns;
      }

      final ids = s.lineas.map((l) => l.productoId).toSet().toList();
      final productos = {
        for (final p in await (db.select(db.productos)..where((p) => p.id.isIn(ids))).get()) p.id: p,
      };
      for (final l in s.lineas) {
        final p = productos[l.productoId];
        if (p == null || esServicio(p)) throw const DatoInvalido('Uno de los productos no existe.');
        if (p.unidad == UnidadVenta.unidad && l.cantidad % milesimasPorUnidad != 0) {
          throw DatoInvalido('${p.nombre} se cuenta por unidad; la cantidad debe ser entera.');
        }
      }
      final total = s.lineas.fold<int>(0, (a, l) => a + l.total);

      TurnoCaja? turno;
      if (s.pago == PagoCompra.deLaCaja) {
        turno = await db.turnoAbierto();
        if (turno == null) {
          throw const CajaCerrada('La caja está cerrada. Ábrala o marque que la compra se pagó por fuera.');
        }
        if (total <= 0) throw const DatoInvalido('Una compra pagada de la caja debe tener un total mayor que cero.');
      }

      final factura = _limpio(s.factura);
      final compraId = await db.into(db.compras).insert(ComprasCompanion.insert(
            fecha: ahora,
            suplidorId: Value(suplidorId),
            factura: Value(factura),
            pago: s.pago,
            total: total,
            usuarioId: sesion.usuarioId,
            nota: Value(_limpio(s.nota)),
          ));

      // Existencia en curso por producto, por si el mismo sale en dos líneas.
      final existencia = {for (final p in productos.values) p.id: p.existencia};
      final lineasEvento = <Map<String, Object?>>[];
      for (final l in s.lineas) {
        final p = productos[l.productoId]!;
        await db.into(db.compraLineas).insert(CompraLineasCompanion.insert(
              compraId: compraId,
              productoId: p.id,
              descripcion: p.nombre,
              cantidad: l.cantidad,
              costo: l.costo,
              total: l.total,
            ));
        final nueva = existencia[p.id]! + l.cantidad;
        existencia[p.id] = nueva;
        await (db.update(db.productos)..where((x) => x.id.equals(p.id))).write(ProductosCompanion(
          existencia: Value(nueva),
          costo: Value(l.costo),
          precio: l.precio == null ? const Value.absent() : Value(l.precio!),
        ));
        await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
              productoId: p.id,
              fecha: ahora,
              tipo: TipoMovInventario.compra,
              cantidad: l.cantidad,
              existenciaResultante: nueva,
              referencia: Value('Compra #$compraId'),
              usuarioId: Value(sesion.usuarioId),
            ));
        lineasEvento.add({
          'ProductoId': p.id,
          'Descripcion': p.nombre,
          'Cantidad': cantidadJson(l.cantidad),
          'Costo': montoJson(l.costo),
          'Total': montoJson(l.total),
        });
      }

      await _guardarAlias(suplidorId, s.lineas);

      final de = nombreSuplidor != null ? ' a $nombreSuplidor' : '';
      if (turno != null) {
        await db.into(db.movimientosCaja).insert(MovimientosCajaCompanion.insert(
              turnoCajaId: turno.id,
              fecha: ahora,
              tipo: TipoMovCaja.salida,
              monto: total,
              concepto: 'Compra #$compraId$de${factura != null ? ', factura $factura' : ''}',
              usuarioId: sesion.usuarioId,
            ));
      }
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Compra registrada',
        detalle: '#$compraId$de ${formatoRD(total)} (${etiquetaPagoCompra(s.pago)})',
        fecha: ahora,
      );
      await db.encolarEvento('compra.registrada', {
        'CompraId': compraId,
        'Fecha': fechaLocalIso(ahora),
        'Suplidor': nombreSuplidor,
        'Factura': factura,
        'Pago': switch (s.pago) {
          PagoCompra.deLaCaja => 'DeLaCaja',
          PagoCompra.porFuera => 'PorFuera',
          PagoCompra.credito => 'Credito',
        },
        'Total': montoJson(total),
        'Lineas': lineasEvento,
      }, ahora);
      return (db.select(db.compras)..where((c) => c.id.equals(compraId))).getSingle();
    });
  }

  /// Qué producto de Emma es cada renglón de una factura leída de una foto.
  Future<List<LineaEmparejada>> emparejar(FacturaLeida factura) async {
    final productos = await (db.select(db.productos)..where((p) => p.activo.equals(true))).get();
    final nombre = factura.suplidor?.trim().toLowerCase() ?? '';
    int? suplidorId;
    if (nombre.isNotEmpty) {
      final todos = await db.select(db.suplidores).get();
      suplidorId = todos.where((x) => x.nombre.toLowerCase() == nombre).firstOrNull?.id;
    }
    final alias = await db.select(db.aliasProductos).get();
    return Emparejador.emparejar(factura, productos, alias: alias, suplidorId: suplidorId);
  }

  Future<void> _guardarAlias(int? suplidorId, List<LineaCompra> lineas) async {
    for (final l in lineas) {
      final texto = Emparejador.normalizar(l.textoFactura);
      if (texto.isEmpty || texto.length > 200) continue;
      final existe = await (db.select(db.aliasProductos)
            ..where((a) => a.texto.equals(texto) & (suplidorId == null ? a.suplidorId.isNull() : a.suplidorId.equals(suplidorId))))
          .getSingleOrNull();
      if (existe == null) {
        await db.into(db.aliasProductos).insert(
            AliasProductosCompanion.insert(suplidorId: Value(suplidorId), texto: texto, productoId: l.productoId));
      } else {
        await (db.update(db.aliasProductos)..where((a) => a.id.equals(existe.id)))
            .write(AliasProductosCompanion(productoId: Value(l.productoId)));
      }
    }
  }

  /// Las compras más recientes, con su suplidor y productos.
  Future<List<CompraDetalle>> recientes({int cuantas = 100}) async {
    final q = db.select(db.compras).join([
      leftOuterJoin(db.suplidores, db.suplidores.id.equalsExp(db.compras.suplidorId)),
    ])
      ..orderBy([OrderingTerm.desc(db.compras.id)])
      ..limit(cuantas);
    final filas = await q.get();
    final res = <CompraDetalle>[];
    for (final f in filas) {
      final c = f.readTable(db.compras);
      final lineas = await (db.select(db.compraLineas)
            ..where((l) => l.compraId.equals(c.id))
            ..orderBy([(l) => OrderingTerm.asc(l.id)]))
          .get();
      res.add(CompraDetalle(c, f.readTableOrNull(db.suplidores)?.nombre, lineas));
    }
    return res;
  }

  static String? _limpio(String? s) {
    final x = s?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}

String etiquetaPagoCompra(PagoCompra p) => switch (p) {
      PagoCompra.deLaCaja => 'de la caja',
      PagoCompra.porFuera => 'por fuera',
      PagoCompra.credito => 'a crédito',
    };
