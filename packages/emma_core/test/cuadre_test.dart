import 'dart:convert';

import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late CajaService caja;
  late VentaService ventas;
  late FiadoService fiado;
  late Sesion dueno;
  late int refresco; // RD$ 50.00

  setUp(() async {
    db = baseDePrueba();
    caja = CajaService(db);
    ventas = VentaService(db);
    fiado = FiadoService(db);
    dueno = await sesionDueno(db);
    refresco = await crearProducto(db, codigo: '7460001', nombre: 'Refresco', precio: 5000, costo: 3500);
  });

  tearDown(() => db.close());

  LineaCobro refrescos(int n) =>
      LineaCobro(productoId: refresco, descripcion: 'Refresco', cantidad: n * 1000, precioUnitario: 5000);

  test('el cuadre calcula el efectivo esperado y el faltante', () async {
    final luis = await crearCliente(db, nombre: 'Luis');
    await caja.abrir(dueno, 100000);
    await ventas.cobrar(dueno, SolicitudCobro(lineas: [refrescos(4)], formaPago: FormaPago.efectivo)); // +200
    await ventas.cobrar(dueno, SolicitudCobro(lineas: [refrescos(2)], formaPago: FormaPago.tarjeta)); // no cuenta
    await ventas.cobrar(dueno, SolicitudCobro(lineas: [refrescos(6)], formaPago: FormaPago.fiado, clienteId: luis));
    await fiado.abonar(dueno, luis, 15000); // +150
    await caja.registrarMovimiento(dueno, TipoMovCaja.salida, 30000, 'Pago al suplidor de pan'); // -300
    await caja.registrarMovimiento(dueno, TipoMovCaja.entrada, 5000, 'Cambio'); // +50

    final turno = (await caja.turnoAbierto())!;
    final antes = await caja.resumen(turno.id);
    expect(antes.efectivoEsperado, 110000);
    expect(antes.totalVentas, 60000);
    expect(antes.ventasTarjeta, 10000);
    expect(antes.ventasFiado, 30000);
    expect(antes.abonosEfectivo, 15000);
    expect(antes.cajero, 'Dueño');

    final cierre = await caja.cerrar(dueno, {1000: 1, 50: 1, 25: 1, 10: 2});
    expect(cierre.turno.efectivoContado, 109500);
    expect(cierre.turno.diferencia, -500);
    expect(jsonDecode(cierre.turno.detalleConteo!), {'1000': 1, '50': 1, '25': 1, '10': 2});
    expect(await caja.turnoAbierto(), isNull);

    final ev = await (db.select(db.eventosSalida)..where((e) => e.tipo.equals(TipoEvento.cajaCerrada))).getSingle();
    final d = jsonDecode(ev.datos) as Map<String, Object?>;
    expect(d['EfectivoContado'], 1095);
    expect(d['Diferencia'], -5);
    expect(d['Cajero'], 'Dueño');
  });

  test('entradas y salidas piden monto, concepto y la caja abierta', () async {
    await expectLater(caja.registrarMovimiento(dueno, TipoMovCaja.entrada, 100, 'x'), throwsA(isA<CajaCerrada>()));
    await caja.abrir(dueno, 0);
    await expectLater(caja.registrarMovimiento(dueno, TipoMovCaja.entrada, 0, 'x'), throwsA(isA<DatoInvalido>()));
    await expectLater(caja.registrarMovimiento(dueno, TipoMovCaja.salida, 100, '  '), throwsA(isA<DatoInvalido>()));
    final m = await caja.registrarMovimiento(dueno, TipoMovCaja.salida, 2550, ' Hielo ');
    expect(m.concepto, 'Hielo');
    expect(await caja.movimientos(m.turnoCajaId), hasLength(1));
  });

  test('no se anula una venta de un turno cerrado', () async {
    await caja.abrir(dueno, 0);
    final v = await ventas.cobrar(dueno, SolicitudCobro(lineas: [refrescos(1)], formaPago: FormaPago.efectivo));
    await caja.cerrar(dueno, {50: 1});
    await expectLater(ventas.anular(dueno, v.ventaId, 'tarde'), throwsA(isA<DatoInvalido>()));
  });

  test('el cuadre separa lo cobrado por cada repartidor', () async {
    await caja.abrir(dueno, 0);
    for (final (rep, n) in const [('Pedro', 2), ('Pedro', 1), ('Juan', 1)]) {
      await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [refrescos(n)], formaPago: FormaPago.efectivo, esDelivery: true, repartidor: rep),
      );
    }
    final r = await caja.resumen((await caja.turnoAbierto())!.id);
    expect(r.cantidadDelivery, 3);
    expect(r.ventasDelivery, 20000);
    expect([for (final p in r.porRepartidor) (p.repartidor, p.cantidad, p.total)], [('Pedro', 2, 15000), ('Juan', 1, 5000)]);
  });

  test('el historial trae los turnos con el nombre del cajero', () async {
    await caja.abrir(dueno, 0);
    await caja.cerrar(dueno, {});
    final h = await caja.historial();
    expect(h.single.cajero, 'Dueño');
    expect(h.single.turno.cierre, isNotNull);
  });

  test('anular una venta del turno abierto la saca del cuadre', () async {
    await caja.abrir(dueno, 0);
    final v = await ventas.cobrar(dueno, SolicitudCobro(lineas: [refrescos(2)], formaPago: FormaPago.efectivo));
    await ventas.anular(dueno, v.ventaId, 'se equivocó');
    final r = await caja.resumen((await caja.turnoAbierto())!.id);
    expect(r.cantidadVentas, 0);
    expect(r.ventasAnuladas, 1);
    expect(r.efectivoEsperado, 0);
  });
}
