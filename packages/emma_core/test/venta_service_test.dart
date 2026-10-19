import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late VentaService ventas;
  late Sesion dueno;
  late int refresco; // RD$ 50.00 la unidad, costo RD$ 35.00, 24 en existencia
  late int arroz; // RD$ 35.00 la libra, costo RD$ 28.00, 10 lb

  setUp(() async {
    db = baseDePrueba();
    ventas = VentaService(db);
    dueno = await sesionDueno(db);
    refresco = await crearProducto(db,
        codigo: '7460001', nombre: 'Refresco 20 oz', precio: 5000, costo: 3500, existencia: 24000);
    arroz = await crearProducto(db,
        codigo: '200',
        nombre: 'Arroz',
        precio: 3500,
        costo: 2800,
        existencia: 10000,
        unidad: UnidadVenta.libra);
  });

  tearDown(() => db.close());

  LineaCobro dosRefrescos() =>
      LineaCobro(productoId: refresco, descripcion: 'Refresco 20 oz', cantidad: 2000, precioUnitario: 5000);
  LineaCobro mediaLibraArroz() =>
      LineaCobro(productoId: arroz, descripcion: 'Arroz', cantidad: 500, precioUnitario: 3500);

  group('cobrar en efectivo', () {
    setUp(() => abrirTurno(db, dueno));

    test('guarda venta, líneas, inventario y evento; calcula la devuelta', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(
          lineas: [dosRefrescos(), mediaLibraArroz()],
          formaPago: FormaPago.efectivo,
          montoRecibido: 20000,
        ),
      );

      // 2 x 50.00 + 0.5 lb x 35.00 = 117.50; paga con 200 -> devuelta 82.50
      expect(r.total, 11750);
      expect(r.montoRecibido, 20000);
      expect(r.devuelta, 8250);
      expect(r.abreGaveta, isTrue);

      final v = await (db.select(db.ventas)..where((x) => x.id.equals(r.ventaId))).getSingle();
      expect(v.subtotal, 11750);
      expect(v.total, 11750);
      expect(v.formaPago, FormaPago.efectivo);
      expect(v.devuelta, 8250);
      expect(v.ticketPendiente, isTrue, reason: 'queda pendiente hasta que la impresora confirme');
      expect(v.fecha, horaPrueba);

      final lineas = await (db.select(db.ventaLineas)..where((l) => l.ventaId.equals(r.ventaId))).get();
      expect(lineas, hasLength(2));
      expect(lineas.first.costoUnitario, 3500);
      expect(lineas.last.total, 1750);

      expect((await producto(db, refresco)).existencia, 22000);
      expect((await producto(db, arroz)).existencia, 9500);

      final movs = await db.select(db.movimientosInventario).get();
      expect(movs, hasLength(2));
      expect(movs.map((m) => m.tipo), everyElement(TipoMovInventario.venta));
      expect(movs.first.cantidad, -2000);
      expect(movs.first.existenciaResultante, 22000);
      expect(movs.first.referencia, 'Venta #${r.ventaId}');
    });

    test('el evento venta.registrada sale con los campos en PascalCase', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(
          lineas: [dosRefrescos(), mediaLibraArroz()],
          formaPago: FormaPago.efectivo,
          montoRecibido: 20000,
          nombreCliente: '  Doña Rosa ',
        ),
      );

      final eventos = await db.select(db.eventosSalida).get();
      expect(eventos, hasLength(1));
      final e = eventos.single;
      expect(e.tipo, 'venta.registrada');
      expect(e.enviadoEn, isNull);

      final d = jsonDecode(e.datos) as Map<String, dynamic>;
      expect(d['Id'], r.ventaId);
      expect(d['Fecha'], '2026-10-18T10:30:05');
      expect(d['Total'], 117.5);
      expect(d['Descuento'], 0);
      expect(d['FormaPago'], 'Efectivo');
      expect(d['Cajero'], 'Dueño');
      expect(d['NombreCliente'], 'Doña Rosa');
      expect(d['ClienteId'], isNull);
      expect(d['EsDelivery'], false);
      final lineas = d['Lineas'] as List<dynamic>;
      expect(lineas, hasLength(2));
      expect(lineas[1], {
        'ProductoId': arroz,
        'Descripcion': 'Arroz',
        'Cantidad': 0.5,
        'PrecioUnitario': 35,
        'CostoUnitario': 28,
        'Total': 17.5,
      });
    });

    test('Enter con la casilla vacía cobra el monto exacto', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo),
      );
      expect(r.montoRecibido, 10000);
      expect(r.devuelta, 0);
    });

    test('si falta dinero no guarda nada', () async {
      await expectLater(
        ventas.cobrar(
          dueno,
          SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo, montoRecibido: 5000),
        ),
        throwsA(isA<DatoInvalido>()),
      );
      expect(await contar(db, 'ventas'), 0);
      expect(await contar(db, 'eventos_salida'), 0);
      expect((await producto(db, refresco)).existencia, 24000);
    });

    test('descuento en pesos baja el total y queda en la bitácora', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo, descuento: 1000),
      );
      expect(r.total, 9000);
      final b = await db.select(db.bitacora).get();
      expect(b.single.accion, 'Descuento');
    });

    test('el descuento no puede pasar la venta', () async {
      await expectLater(
        ventas.cobrar(
          dueno,
          SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo, descuento: 10001),
        ),
        throwsA(isA<DatoInvalido>()),
      );
    });

    test('tarjeta y transferencia no llevan devuelta', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.tarjeta, montoRecibido: 99999),
      );
      expect(r.montoRecibido, 10000);
      expect(r.devuelta, 0);
      expect(r.abreGaveta, isFalse);
    });

    test('venta suelta (Varios) no toca inventario', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [LineaCobro.varios(5000)], formaPago: FormaPago.efectivo),
      );
      expect(r.total, 5000);
      expect(await contar(db, 'movimientos_inventario'), 0);
      final varios = await db.productoVarios();
      expect(varios.existencia, 0);
      final linea = await db.select(db.ventaLineas).getSingle();
      expect(linea.productoId, varios.id);
      expect(linea.descripcion, 'Varios');
      expect(linea.costoUnitario, 0);
    });

    test('libra por monto: \$50 de arroz cobra exactamente 50.00', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(
          lineas: [LineaCobro.porMonto(productoId: arroz, descripcion: 'Arroz', monto: 5000, precioUnitario: 3500)],
          formaPago: FormaPago.efectivo,
        ),
      );
      expect(r.total, 5000);
      // 50 / 35 = 1.4286 lb -> 1.429 lb
      expect((await producto(db, arroz)).existencia, 10000 - 1429);
    });

    test('el mismo producto en dos líneas descuenta bien la existencia', () async {
      await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos(), dosRefrescos()], formaPago: FormaPago.efectivo),
      );
      expect((await producto(db, refresco)).existencia, 20000);
      final movs = await db.select(db.movimientosInventario).get();
      expect(movs.map((m) => m.existenciaResultante), [22000, 20000]);
    });

    test('si un producto falla, la transacción no deja nada a medias', () async {
      await expectLater(
        ventas.cobrar(
          dueno,
          SolicitudCobro(
            lineas: [
              dosRefrescos(),
              LineaCobro(productoId: 9999, descripcion: 'Fantasma', cantidad: 1000, precioUnitario: 100),
            ],
            formaPago: FormaPago.efectivo,
          ),
        ),
        throwsA(isA<DatoInvalido>()),
      );
      expect(await contar(db, 'ventas'), 0);
      expect(await contar(db, 'venta_lineas'), 0);
      expect(await contar(db, 'movimientos_inventario'), 0);
      expect(await contar(db, 'eventos_salida'), 0);
      expect((await producto(db, refresco)).existencia, 24000);
    });

    test('cobrar un pedido abierto lo borra en la misma transacción', () async {
      final ticketId = await db.into(db.ticketsAbiertos).insert(TicketsAbiertosCompanion.insert(
            numero: 1,
            usuarioId: dueno.usuarioId,
            creado: horaPrueba,
            actualizado: horaPrueba,
          ));
      await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo, ticketAbiertoId: ticketId),
      );
      expect(await contar(db, 'tickets_abiertos'), 0);
    });

    test('marcar ticket impreso lo saca de pendientes', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo),
      );
      expect((await ventas.ventasConTicketPendiente()).map((v) => v.id), [r.ventaId]);
      await ventas.marcarTicketImpreso(r.ventaId);
      expect(await ventas.ventasConTicketPendiente(), isEmpty);
    });
  });

  test('no se vende con la caja cerrada', () async {
    await expectLater(
      ventas.cobrar(dueno, SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo)),
      throwsA(isA<CajaCerrada>()),
    );
    expect(await contar(db, 'ventas'), 0);
  });

  test('no se cobra una venta sin líneas', () async {
    await abrirTurno(db, dueno);
    await expectLater(
      ventas.cobrar(dueno, const SolicitudCobro(lineas: [], formaPago: FormaPago.efectivo)),
      throwsA(isA<DatoInvalido>()),
    );
  });

  group('fiado con límite', () {
    late int juan; // límite RD$ 500.00

    setUp(() async {
      await abrirTurno(db, dueno);
      juan = await crearCliente(db, nombre: 'Juan Pérez', limite: 50000);
    });

    SolicitudCobro fiar(int clienteId, int monto) => SolicitudCobro(
          lineas: [LineaCobro.varios(monto)],
          formaPago: FormaPago.fiado,
          clienteId: clienteId,
        );

    test('dentro del límite: suma a la deuda con un cargo', () async {
      final r = await ventas.cobrar(dueno, fiar(juan, 30000));
      expect(r.montoRecibido, 0);
      expect(r.devuelta, 0);
      expect(r.abreGaveta, isFalse);
      expect(await db.deudaCliente(juan), 30000);

      final m = await db.select(db.movimientosFiado).getSingle();
      expect(m.tipo, TipoMovFiado.cargo);
      expect(m.monto, 30000);
      expect(m.ventaId, r.ventaId);

      final v = await (db.select(db.ventas)..where((x) => x.id.equals(r.ventaId))).getSingle();
      expect(v.clienteId, juan);
      expect(v.nombreCliente, 'Juan Pérez');

      final d = jsonDecode((await db.select(db.eventosSalida).getSingle()).datos) as Map<String, dynamic>;
      expect(d['FormaPago'], 'Fiado');
      expect(d['ClienteId'], juan);
    });

    test('llegar justo al límite se permite', () async {
      await ventas.cobrar(dueno, fiar(juan, 50000));
      expect(await db.deudaCliente(juan), 50000);
    });

    test('pasar el límite no deja cobrar ni guarda nada', () async {
      await ventas.cobrar(dueno, fiar(juan, 45000));

      await expectLater(
        ventas.cobrar(dueno, fiar(juan, 10000)),
        throwsA(isA<LimiteFiadoExcedido>()
            .having((e) => e.debe, 'debe', 45000)
            .having((e) => e.limite, 'limite', 50000)
            .having((e) => e.quedaria, 'quedaria', 55000)
            .having((e) => e.mensaje, 'mensaje', contains('RD\$ 450.00'))),
      );
      expect(await contar(db, 'ventas'), 1);
      expect(await contar(db, 'eventos_salida'), 1);
      expect(await db.deudaCliente(juan), 45000);
    });

    test('límite 0 = sin límite', () async {
      final pedro = await crearCliente(db, nombre: 'Pedro', limite: 0);
      await ventas.cobrar(dueno, fiar(pedro, 9999900));
      expect(await db.deudaCliente(pedro), 9999900);
    });

    test('para fiar hay que escoger cliente', () async {
      await expectLater(
        ventas.cobrar(dueno, SolicitudCobro(lineas: [LineaCobro.varios(100)], formaPago: FormaPago.fiado)),
        throwsA(isA<DatoInvalido>()),
      );
    });

    test('un cliente desactivado no puede fiar', () async {
      await (db.update(db.clientes)..where((c) => c.id.equals(juan)))
          .write(const ClientesCompanion(activo: Value(false)));
      await expectLater(ventas.cobrar(dueno, fiar(juan, 100)), throwsA(isA<DatoInvalido>()));
    });
  });

  group('anular', () {
    setUp(() => abrirTurno(db, dueno));

    test('el dueño anula: vuelve el inventario, bitácora y evento', () async {
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos(), mediaLibraArroz(), LineaCobro.varios(2500)], formaPago: FormaPago.efectivo),
      );
      expect((await producto(db, refresco)).existencia, 22000);

      await ventas.anular(dueno, r.ventaId, '  Se equivocó de producto ');

      final v = await (db.select(db.ventas)..where((x) => x.id.equals(r.ventaId))).getSingle();
      expect(v.anulada, isTrue);
      expect(v.motivoAnulacion, 'Se equivocó de producto');
      expect(v.anuladaPorId, dueno.usuarioId);
      expect(v.fechaAnulacion, horaPrueba);

      expect((await producto(db, refresco)).existencia, 24000);
      expect((await producto(db, arroz)).existencia, 10000);

      final devoluciones = await (db.select(db.movimientosInventario)
            ..where((m) => m.tipo.equalsValue(TipoMovInventario.anulacionVenta)))
          .get();
      expect(devoluciones, hasLength(2), reason: 'Varios no lleva inventario');

      final b = await db.select(db.bitacora).getSingle();
      expect(b.accion, 'Anular venta');
      expect(b.usuarioId, dueno.usuarioId);
      expect(b.detalle, contains('Se equivocó de producto'));

      final eventos = await (db.select(db.eventosSalida)..where((e) => e.tipo.equals('venta.anulada'))).get();
      final d = jsonDecode(eventos.single.datos) as Map<String, dynamic>;
      expect(d, {
        'Id': r.ventaId,
        'Total': 142.5,
        'MotivoAnulacion': 'Se equivocó de producto',
        'AnuladaPor': 'Dueño',
        'Fecha': '2026-10-18T10:30:05',
      });
    });

    test('anular un fiado le quita la deuda al cliente', () async {
      final juan = await crearCliente(db, nombre: 'Juan', limite: 50000);
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.fiado, clienteId: juan),
      );
      expect(await db.deudaCliente(juan), 10000);

      await ventas.anular(dueno, r.ventaId, 'Devolvió los refrescos');

      expect(await db.deudaCliente(juan), 0);
      final m = await (db.select(db.movimientosFiado)
            ..where((x) => x.tipo.equalsValue(TipoMovFiado.anulacionCargo)))
          .getSingle();
      expect(m.monto, 10000);
      expect(m.ventaId, r.ventaId);
    });

    test('el cajero no puede anular y no cambia nada', () async {
      final cajero = await crearCajero(db);
      final r = await ventas.cobrar(
        cajero,
        SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo),
      );
      await expectLater(ventas.anular(cajero, r.ventaId, 'quiero'), throwsA(isA<PermisoDenegado>()));
      final v = await (db.select(db.ventas)..where((x) => x.id.equals(r.ventaId))).getSingle();
      expect(v.anulada, isFalse);
      expect((await producto(db, refresco)).existencia, 22000);
    });

    test('pide motivo', () async {
      final r = await ventas.cobrar(dueno, SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo));
      await expectLater(ventas.anular(dueno, r.ventaId, '   '), throwsA(isA<DatoInvalido>()));
    });

    test('no se anula dos veces', () async {
      final r = await ventas.cobrar(dueno, SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo));
      await ventas.anular(dueno, r.ventaId, 'Error');
      await expectLater(ventas.anular(dueno, r.ventaId, 'Otra vez'), throwsA(isA<DatoInvalido>()));
      expect((await producto(db, refresco)).existencia, 24000, reason: 'no devuelve dos veces');
    });

    test('una venta anulada no sale en tickets pendientes', () async {
      final r = await ventas.cobrar(dueno, SolicitudCobro(lineas: [dosRefrescos()], formaPago: FormaPago.efectivo));
      await ventas.anular(dueno, r.ventaId, 'Error');
      expect(await ventas.ventasConTicketPendiente(), isEmpty);
    });
  });
}
