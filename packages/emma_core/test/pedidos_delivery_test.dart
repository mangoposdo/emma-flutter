import 'dart:convert';

import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late TicketService tickets;
  late DeliveryService delivery;
  late VentaService ventas;
  late Sesion dueno;
  late int refresco; // RD$ 95.00
  late int queso; // RD$ 220.00 la libra

  setUp(() async {
    db = baseDePrueba();
    tickets = TicketService(db);
    delivery = DeliveryService(db);
    ventas = VentaService(db);
    dueno = await sesionDueno(db);
    refresco = await crearProducto(db, codigo: '7460001', nombre: 'Refresco', precio: 9500, existencia: 24000);
    queso = await crearProducto(db, codigo: '204', nombre: 'Queso de freír', precio: 22000, unidad: UnidadVenta.libra);
  });

  tearDown(() => db.close());

  group('pedidos abiertos', () {
    test('se guardan con el número libre más bajo y sus productos', () async {
      final p1 = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 2000)]);
      final p2 = await tickets.guardar(dueno, nombreCliente: ' Doña Rosa ', lineas: const []);
      expect(p1.numero, 1);
      expect(p2.numero, 2);
      expect(TicketService.titulo(p2), 'Doña Rosa');
      expect(TicketService.titulo(p1), 'Pedido 1');

      await tickets.borrar(p1.id);
      final p3 = await tickets.guardar(dueno, lineas: const []);
      expect(p3.numero, 1);

      final guardado = (await tickets.porId(p2.id))!;
      expect(guardado.nombreCliente, 'Doña Rosa');
      expect((await tickets.abiertos()).map((t) => t.numero), [1, 2]);
    });

    test('las líneas guardan la venta suelta y la libra por monto', () async {
      final varios = await db.productoVarios();
      final t = await tickets.guardar(dueno, lineas: [
        LineaPedido(productoId: varios.id, cantidad: 1000, precio: 5000),
        LineaPedido(productoId: queso, cantidad: cantidadPorMonto(10000, 22000), monto: 10000),
        LineaPedido(productoId: refresco, cantidad: 3000),
      ]);
      final ls = TicketService.lineas((await tickets.porId(t.id))!);
      expect(ls[0].precio, 5000);
      expect(ls[1].monto, 10000);
      expect(await tickets.total(t), 5000 + 10000 + 28500);
    });

    test('al cobrar el pedido se borra y la venta guarda el nombre del cliente', () async {
      await abrirTurno(db, dueno);
      final t = await tickets.guardar(dueno, nombreCliente: 'Doña Rosa', lineas: [LineaPedido(productoId: refresco, cantidad: 1000)]);
      final p = (await db.select(db.productos).get()).firstWhere((x) => x.id == refresco);
      final r = await ventas.cobrar(
        dueno,
        SolicitudCobro(
          lineas: [for (final l in TicketService.lineas(t)) l.aCobro(p)],
          formaPago: FormaPago.efectivo,
          nombreCliente: t.nombreCliente,
          ticketAbiertoId: t.id,
        ),
      );
      expect(await tickets.porId(t.id), isNull);
      expect((await ventas.porId(r.ventaId))!.nombreParaMostrar, 'Doña Rosa');
    });

    test('si la venta falla el pedido sigue abierto', () async {
      final t = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 1000)]);
      // Caja cerrada: falla.
      await expectLater(
        ventas.cobrar(dueno, SolicitudCobro(
          lineas: [LineaCobro(productoId: refresco, descripcion: 'Refresco', cantidad: 1000, precioUnitario: 9500)],
          formaPago: FormaPago.efectivo,
          ticketAbiertoId: t.id,
        )),
        throwsA(isA<CajaCerrada>()),
      );
      expect(await tickets.porId(t.id), isNotNull);
    });
  });

  group('delivery', () {
    test('sale, se cobra al volver con el envío y guarda al cliente para la próxima', () async {
      await abrirTurno(db, dueno);
      final t = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 2000)]);
      await delivery.preparar(dueno, t.id, const DatosDelivery(
        nombre: 'Carmen', telefono: '809-555-1234', direccion: 'Calle 5 #12, casa verde', pagaCon: 50000, cargoEnvio: 5000, repartidor: 'Pedro'));

      final carmen = (await delivery.clientePorTelefono('8095551234'))!;
      expect(carmen.nombre, 'Carmen');
      expect(carmen.esFijo, isTrue);
      expect(carmen.direccion, 'Calle 5 #12, casa verde');

      final salio = await delivery.despachar(dueno, t.id);
      expect(salio.estadoDelivery, EstadoDelivery.enCamino);
      expect(salio.deliveryId, isNotNull);
      expect(await tickets.abiertos(), isEmpty); // ya no sale en el mostrador

      final calle = await delivery.enLaCalle();
      expect(calle.single.total, 24000);
      expect(calle.single.cambio, 26000);

      final ev = await (db.select(db.eventosSalida)..where((e) => e.tipo.equals(TipoEvento.deliverySalio))).getSingle();
      expect(jsonDecode(ev.datos), containsPair('Total', 240));

      final s = await delivery.solicitudDeCobro(t.id, forma: FormaPago.efectivo, recibido: 50000);
      final r = await ventas.cobrar(dueno, s);
      expect(r.total, 24000);
      expect(r.devuelta, 26000);
      final v = (await ventas.porId(r.ventaId))!;
      expect(v.venta.esDelivery, isTrue);
      expect(v.venta.repartidor, 'Pedro');
      expect(v.venta.clienteId, carmen.id);
      expect(v.lineas.map((l) => l.descripcion), ['Refresco', 'Envío a domicilio']);
      expect(await delivery.enLaCalle(), isEmpty);
      // El envío no toca inventario.
      final envio = await db.productoEnvio();
      expect(envio.existencia, 0);

      // La próxima vez el teléfono trae el nombre y la dirección.
      final otra = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 1000)]);
      await delivery.preparar(dueno, otra.id, const DatosDelivery(telefono: '555-1234 ', direccion: 'Igual'));
      expect((await tickets.porId(otra.id))!.nombreCliente, 'Carmen');
    });

    test('devuelto vuelve al mostrador', () async {
      final t = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 1000)]);
      await delivery.preparar(dueno, t.id, const DatosDelivery(direccion: 'Al lado del colmado'));
      await delivery.despachar(dueno, t.id, repartidor: 'Juan');
      await expectLater(tickets.guardar(dueno, id: t.id, lineas: const []), throwsA(isA<DatoInvalido>()));
      await delivery.devolver(dueno, t.id, 'No estaba en la casa');
      expect((await tickets.abiertos()).single.id, t.id);
      expect(await delivery.enLaCalle(), isEmpty);
      final ev = await (db.select(db.eventosSalida)..where((e) => e.tipo.equals(TipoEvento.deliveryDevuelto))).getSingle();
      expect(jsonDecode(ev.datos), containsPair('Motivo', 'No estaba en la casa'));
    });

    test('reglas: dirección, datos antes de despachar, productos', () async {
      final t = await tickets.guardar(dueno, lineas: const []);
      await expectLater(delivery.preparar(dueno, t.id, const DatosDelivery(direccion: ' ')), throwsA(isA<DatoInvalido>()));
      await expectLater(delivery.despachar(dueno, t.id), throwsA(isA<DatoInvalido>()));
      await delivery.preparar(dueno, t.id, const DatosDelivery(direccion: 'Aquí'));
      await expectLater(delivery.despachar(dueno, t.id), throwsA(isA<DatoInvalido>()));
      await delivery.quitarDelivery(t.id);
      expect((await tickets.porId(t.id))!.esDelivery, isFalse);
    });

    test('la comanda lleva la dirección completa y el cambio', () async {
      final negocio = await db.negocio();
      final t = await tickets.guardar(dueno, lineas: [LineaPedido(productoId: refresco, cantidad: 2000)]);
      await delivery.preparar(dueno, t.id, const DatosDelivery(
        nombre: 'Carmen', telefono: '809-555-1234', direccion: 'Calle 5 #12, casa verde detrás de la bomba', pagaCon: 100000, cargoEnvio: 5000));
      final salio = await delivery.despachar(dueno, t.id, repartidor: 'Pedro');
      final bytes = TicketEscPos.comanda(negocio, salio, await delivery.lineasComanda(salio), await delivery.total(salio));
      final texto = latin1.decode(bytes, allowInvalid: true);
      expect(texto, contains('DELIVERY'));
      expect(texto, contains('2 x Refresco'));
      expect(texto, contains('casa verde'));
      expect(texto, contains('LLEVAR CAMBIO'));
      expect(texto, contains('760.00'));
    });

    test('los repartidores registrados salen primero y los quitados no salen', () async {
      final pedro = await delivery.guardarRepartidor(dueno, const DatosRepartidor(nombre: 'Pedro'));
      await delivery.guardarRepartidor(dueno, const DatosRepartidor(nombre: 'Ana', telefono: '809'));
      await expectLater(delivery.guardarRepartidor(dueno, const DatosRepartidor(nombre: 'pedro')), throwsA(isA<DatoInvalido>()));
      await abrirTurno(db, dueno);
      await ventas.cobrar(dueno, SolicitudCobro(
        lineas: [LineaCobro(productoId: refresco, descripcion: 'Refresco', cantidad: 1000, precioUnitario: 9500)],
        formaPago: FormaPago.efectivo, esDelivery: true, repartidor: 'Chino'));
      expect(await delivery.repartidores(), ['Ana', 'Pedro', 'Chino']);
      await delivery.guardarRepartidor(dueno, DatosRepartidor(id: pedro.id, nombre: 'Pedro', activo: false));
      expect(await delivery.repartidores(), ['Ana', 'Chino']);
      expect((await delivery.listaRepartidores()).map((r) => r.nombre), ['Ana']);
    });
  });
}
