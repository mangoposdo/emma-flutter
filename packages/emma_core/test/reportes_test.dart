import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late Sesion dueno;
  late int refresco; // precio 50, costo 35
  late int arroz; // 45 la libra, costo 30
  var ahora = horaPrueba;

  setUp(() async {
    ahora = horaPrueba;
    db = baseDePrueba(reloj: () => ahora);
    dueno = await sesionDueno(db);
    refresco = await crearProducto(db, codigo: '1', nombre: 'Refresco', precio: 5000, costo: 3500, existencia: 10000);
    arroz = await crearProducto(db, codigo: '2', nombre: 'Arroz', precio: 4500, costo: 3000, existencia: 20000, unidad: UnidadVenta.libra);
    await abrirTurno(db, dueno);
  });

  tearDown(() => db.close());

  Future<int> vender(List<LineaCobro> lineas, {int descuento = 0, int? clienteId, FormaPago forma = FormaPago.efectivo}) async =>
      (await VentaService(db).cobrar(
        dueno,
        SolicitudCobro(lineas: lineas, formaPago: forma, descuento: descuento, clienteId: clienteId),
      ))
          .ventaId;

  LineaCobro r(int n) => LineaCobro(productoId: refresco, descripcion: 'Refresco', cantidad: n * 1000, precioUnitario: 5000);
  LineaCobro a(int lb) => LineaCobro(productoId: arroz, descripcion: 'Arroz', cantidad: lb, precioUnitario: 4500);

  test('calcula la ganancia, el ticket promedio y los más vendidos; las anuladas no cuentan', () async {
    await vender([r(2), a(2000)]); // 100 + 90 = 190; costo 70 + 60
    await vender([r(1)], descuento: 1000, forma: FormaPago.tarjeta); // 40; costo 35
    final anulada = await vender([r(5)]);
    await VentaService(db).anular(dueno, anulada, 'error');

    final desde = soloDia(horaPrueba);
    final hasta = desde.add(const Duration(days: 1));
    final rep = ReporteService(db);
    final res = await rep.resumen(desde, hasta);
    expect(res.cantidadVentas, 2);
    expect(res.total, 23000);
    expect(res.costo, 16500);
    expect(res.ganancia, 6500);
    expect(res.ticketPromedio, 11500);
    expect(res.porFormaPago, {FormaPago.efectivo: 19000, FormaPago.tarjeta: 4000});

    final top = await rep.masVendidos(desde, hasta);
    expect(top.map((p) => (p.nombre, p.cantidad, p.total)), [('Refresco', 3000, 15000), ('Arroz', 2000, 9000)]);

    final dias = await rep.porDia(desde, hasta);
    expect(dias.single.cantidad, 2);
    expect(dias.single.ganancia, 6500);
  });

  test('el inventario se valoriza a costo y a precio, sin lo que está en negativo', () async {
    final inv = await ReporteService(db).inventarioValorizado();
    expect(inv.costo, 10 * 3500 + 20 * 3000);
    expect(inv.venta, 10 * 5000 + 20 * 4500);
    expect(inv.productos, 2);
  });

  test('dice cada cuánto compra cada cliente y quién no ha vuelto', () async {
    final rosa = await crearCliente(db, nombre: 'Rosa');
    await (db.update(db.clientes)..where((c) => c.id.equals(rosa))).write(const ClientesCompanion(esFijo: Value(true)));
    final luis = await crearCliente(db, nombre: 'Luis');
    final nuevo = await crearCliente(db, nombre: 'Nuevo');
    final sinCompras = await crearCliente(db, nombre: 'Fijo sin compras');
    await (db.update(db.clientes)..where((c) => c.id.equals(sinCompras))).write(const ClientesCompanion(esFijo: Value(true)));

    // Rosa viene cada 2 días; Luis vino cada 3 días hace un mes; Nuevo vino una vez ayer.
    final base = horaPrueba.subtract(const Duration(days: 40));
    for (var d = 0; d <= 38; d += 2) {
      ahora = base.add(Duration(days: d));
      await vender([r(1)], clienteId: rosa);
    }
    for (var d = 0; d <= 9; d += 3) {
      ahora = base.add(Duration(days: d));
      await vender([a(1000)], clienteId: luis);
    }
    ahora = horaPrueba.subtract(const Duration(days: 1));
    await vender([r(1)], clienteId: nuevo);
    ahora = horaPrueba;

    final lista = await ReporteService(db).recurrencia();
    final porNombre = {for (final x in lista) x.cliente.nombre: x};
    expect(porNombre['Rosa']!.estado, EstadoRecurrencia.alDia);
    expect(porNombre['Rosa']!.frecuenciaTexto, 'Cada 2 días');
    expect(porNombre['Rosa']!.productoFavorito, 'Refresco');
    expect(porNombre['Luis']!.estado, EstadoRecurrencia.perdido);
    expect(porNombre['Nuevo']!.estado, EstadoRecurrencia.nuevo);
    expect(porNombre['Fijo sin compras']!.estado, EstadoRecurrencia.sinCompras);
  });

  test('exporta las ventas a CSV', () async {
    await vender([r(1)]);
    final csv = await ReporteService(db).exportarVentasCsv(soloDia(horaPrueba), soloDia(horaPrueba).add(const Duration(days: 1)));
    expect(csv, contains('numero;fecha;cajero;cliente;forma_pago;subtotal;descuento;total;anulada'));
    expect(csv, contains('1;2026-10-18 10:30;Dueño;;Efectivo;50.00;0.00;50.00;no'));
  });
}
