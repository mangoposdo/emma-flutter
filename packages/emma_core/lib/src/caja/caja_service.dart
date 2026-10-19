import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../nube/eventos.dart';
import '../sesion.dart';

/// Un turno con el nombre de quien lo abrió.
class TurnoConCajero {
  const TurnoConCajero(this.turno, this.cajero);

  final TurnoCaja turno;
  final String cajero;
}

/// Cobrado por un repartidor en el turno.
class CobradoRepartidor {
  const CobradoRepartidor(this.repartidor, this.cantidad, this.total);

  final String repartidor;
  final int cantidad;

  /// Centavos.
  final int total;
}

/// Todo lo que entra al cuadre de un turno. Montos en centavos.
class ResumenTurno {
  const ResumenTurno({
    required this.turno,
    required this.cajero,
    required this.cantidadVentas,
    required this.ventasAnuladas,
    required this.ventasEfectivo,
    required this.ventasTarjeta,
    required this.ventasTransferencia,
    required this.ventasFiado,
    required this.abonosEfectivo,
    required this.abonosOtros,
    required this.entradas,
    required this.salidas,
    required this.cantidadDelivery,
    required this.ventasDelivery,
    required this.porRepartidor,
  });

  final TurnoCaja turno;
  final String cajero;
  final int cantidadVentas;
  final int ventasAnuladas;
  final int ventasEfectivo;
  final int ventasTarjeta;
  final int ventasTransferencia;
  final int ventasFiado;
  final int abonosEfectivo;
  final int abonosOtros;
  final int entradas;
  final int salidas;
  final int cantidadDelivery;
  final int ventasDelivery;
  final List<CobradoRepartidor> porRepartidor;

  int get totalVentas => ventasEfectivo + ventasTarjeta + ventasTransferencia + ventasFiado;

  /// Lo que debe haber en la gaveta.
  int get efectivoEsperado => turno.fondoInicial + ventasEfectivo + abonosEfectivo + entradas - salidas;
}

/// Turnos de caja: abrir, entradas y salidas de efectivo, y el cuadre.
class CajaService {
  CajaService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  /// Billetes y monedas dominicanos para el conteo del cuadre, en pesos.
  static const denominaciones = [2000, 1000, 500, 200, 100, 50, 25, 10, 5, 1];

  final EmmaDatabase db;
  final Reloj _reloj;

  /// El turno abierto, o null si la caja está cerrada.
  Future<TurnoCaja?> turnoAbierto() => db.turnoAbierto();

  Future<TurnoCaja> _requiereTurno([String? mensaje]) async {
    final t = await db.turnoAbierto();
    if (t == null) throw mensaje == null ? const CajaCerrada() : CajaCerrada(mensaje);
    return t;
  }

  /// Abre la caja con el fondo inicial (centavos). Solo puede haber un turno
  /// abierto a la vez.
  Future<TurnoCaja> abrir(Sesion sesion, int fondoInicial) async {
    if (fondoInicial < 0) throw const DatoInvalido('El fondo no puede ser negativo.');
    final fecha = _reloj();

    return db.transaction(() async {
      if (await db.turnoAbierto() != null) {
        throw const DatoInvalido('La caja ya está abierta.');
      }
      final id = await db.into(db.turnosCaja).insert(TurnosCajaCompanion.insert(
            usuarioId: sesion.usuarioId,
            apertura: fecha,
            fondoInicial: fondoInicial,
          ));
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Abrir caja',
        detalle: 'Turno #$id con fondo de ${formatoRD(fondoInicial)}.',
        fecha: fecha,
      );
      return (db.select(db.turnosCaja)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  /// Entrada o salida de efectivo que no es una venta (pago a un suplidor, gasto).
  Future<MovimientoCaja> registrarMovimiento(Sesion sesion, TipoMovCaja tipo, int monto, String concepto) async {
    if (monto <= 0) throw const DatoInvalido('El monto debe ser mayor que cero.');
    final c = concepto.trim();
    if (c.isEmpty) throw const DatoInvalido('Escriba el concepto del movimiento.');
    final fecha = _reloj();
    return db.transaction(() async {
      final turno = await _requiereTurno('La caja está cerrada. Abra la caja para continuar.');
      final id = await db.into(db.movimientosCaja).insert(MovimientosCajaCompanion.insert(
            turnoCajaId: turno.id,
            fecha: fecha,
            tipo: tipo,
            monto: monto,
            concepto: c,
            usuarioId: sesion.usuarioId,
          ));
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: tipo == TipoMovCaja.entrada ? 'Entrada de efectivo' : 'Salida de efectivo',
        detalle: '${formatoRD(monto)} $c',
        fecha: fecha,
      );
      return (db.select(db.movimientosCaja)..where((m) => m.id.equals(id))).getSingle();
    });
  }

  Future<List<MovimientoCaja>> movimientos(int turnoId) => (db.select(db.movimientosCaja)
        ..where((m) => m.turnoCajaId.equals(turnoId))
        ..orderBy([(m) => OrderingTerm.asc(m.id)]))
      .get();

  Future<String> _nombreUsuario(int id) async =>
      (await (db.select(db.usuarios)..where((u) => u.id.equals(id))).getSingleOrNull())?.nombre ?? '';

  Future<ResumenTurno> resumen(int turnoId) async {
    final turno = await (db.select(db.turnosCaja)..where((t) => t.id.equals(turnoId))).getSingle();
    final ventas = await (db.select(db.ventas)..where((v) => v.turnoCajaId.equals(turnoId))).get();
    final validas = ventas.where((v) => !v.anulada).toList();
    final abonos = await (db.select(db.movimientosFiado)
          ..where((f) => f.turnoCajaId.equals(turnoId) & f.tipo.equalsValue(TipoMovFiado.abono)))
        .get();
    final movs = await movimientos(turnoId);

    int suma(FormaPago fp) => validas.where((v) => v.formaPago == fp).fold(0, (a, v) => a + v.total);
    final delivery = validas.where((v) => v.esDelivery).toList();
    final porRep = <String, (int, int)>{};
    for (final v in delivery) {
      final nombre = v.repartidor ?? 'Sin repartidor';
      final (n, t) = porRep[nombre] ?? (0, 0);
      porRep[nombre] = (n + 1, t + v.total);
    }
    final repartidores = [for (final e in porRep.entries) CobradoRepartidor(e.key, e.value.$1, e.value.$2)]
      ..sort((a, b) => b.total.compareTo(a.total));

    return ResumenTurno(
      turno: turno,
      cajero: await _nombreUsuario(turno.usuarioId),
      cantidadVentas: validas.length,
      ventasAnuladas: ventas.length - validas.length,
      ventasEfectivo: suma(FormaPago.efectivo),
      ventasTarjeta: suma(FormaPago.tarjeta),
      ventasTransferencia: suma(FormaPago.transferencia),
      ventasFiado: suma(FormaPago.fiado),
      abonosEfectivo:
          abonos.where((a) => a.formaPagoAbono == FormaPago.efectivo).fold(0, (s, a) => s + a.monto),
      abonosOtros: abonos.where((a) => a.formaPagoAbono != FormaPago.efectivo).fold(0, (s, a) => s + a.monto),
      entradas: movs.where((m) => m.tipo == TipoMovCaja.entrada).fold(0, (s, m) => s + m.monto),
      salidas: movs.where((m) => m.tipo == TipoMovCaja.salida).fold(0, (s, m) => s + m.monto),
      cantidadDelivery: delivery.length,
      ventasDelivery: delivery.fold(0, (s, v) => s + v.total),
      porRepartidor: repartidores,
    );
  }

  /// Cierra el turno con el conteo: {denominación en pesos: cantidad}.
  /// Devuelve el resumen con lo contado y la diferencia.
  Future<ResumenTurno> cerrar(Sesion sesion, Map<int, int> conteo, {String? notas}) async {
    if (conteo.values.any((n) => n < 0)) {
      throw const DatoInvalido('El conteo no puede tener cantidades negativas.');
    }
    final fecha = _reloj();
    final id = await db.transaction(() async {
      final abierto = await _requiereTurno('La caja está cerrada. Abra la caja para continuar.');
      final r = await resumen(abierto.id);
      final contado = conteo.entries.fold<int>(0, (s, e) => s + e.key * 100 * e.value);
      final diferencia = contado - r.efectivoEsperado;
      final detalle = {
        for (final e in conteo.entries.where((e) => e.value > 0)) '${e.key}': e.value,
      };
      final n = _limpio(notas);
      await (db.update(db.turnosCaja)..where((t) => t.id.equals(abierto.id))).write(TurnosCajaCompanion(
        cierre: Value(fecha),
        efectivoEsperado: Value(r.efectivoEsperado),
        efectivoContado: Value(contado),
        diferencia: Value(diferencia),
        detalleConteo: Value(jsonEncode(detalle)),
        notas: Value(n),
      ));
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Cierre de caja',
        detalle: 'Esperado ${formatoRD(r.efectivoEsperado)}, contado ${formatoRD(contado)}',
        fecha: fecha,
      );
      await db.encolarEvento(TipoEvento.cajaCerrada, {
        'Id': abierto.id,
        'Apertura': fechaLocalIso(abierto.apertura),
        'Cierre': fechaLocalIso(fecha),
        'FondoInicial': montoJson(abierto.fondoInicial),
        'EfectivoEsperado': montoJson(r.efectivoEsperado),
        'EfectivoContado': montoJson(contado),
        'Diferencia': montoJson(diferencia),
        'CantidadVentas': r.cantidadVentas,
        'TotalVentas': montoJson(r.totalVentas),
        'VentasEfectivo': montoJson(r.ventasEfectivo),
        'VentasTarjeta': montoJson(r.ventasTarjeta),
        'VentasTransferencia': montoJson(r.ventasTransferencia),
        'VentasFiado': montoJson(r.ventasFiado),
        'Cajero': r.cajero,
        'CantidadDelivery': r.cantidadDelivery,
        'VentasDelivery': montoJson(r.ventasDelivery),
      }, fecha);
      return abierto.id;
    });
    return resumen(id);
  }

  /// Los últimos turnos, del más nuevo al más viejo.
  Future<List<TurnoConCajero>> historial({int cantidad = 60}) async {
    final q = db.select(db.turnosCaja).join([
      leftOuterJoin(db.usuarios, db.usuarios.id.equalsExp(db.turnosCaja.usuarioId)),
    ])
      ..orderBy([OrderingTerm.desc(db.turnosCaja.id)])
      ..limit(cantidad);
    final filas = await q.get();
    return [
      for (final f in filas)
        TurnoConCajero(f.readTable(db.turnosCaja), f.readTableOrNull(db.usuarios)?.nombre ?? ''),
    ];
  }

  static String? _limpio(String? t) {
    final x = t?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
