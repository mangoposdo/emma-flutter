import 'dart:io';

import 'package:drift/drift.dart';
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/features/reportes/reportes_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

/// Domingo 18 de octubre de 2026, a media mañana.
final _ahora = DateTime(2026, 10, 18, 10, 30);

/// Banco con la hora de los reportes fija en [_ahora].
Future<(Banco, ProviderContainer)> _preparar() async {
  final b = await Banco.crear();
  final c = ProviderContainer.test(overrides: [
    baseDeDatosProvider.overrideWithValue(b.db),
    carpetaDatosProvider.overrideWithValue(Directory.systemTemp),
    relojReportesProvider.overrideWithValue(() => _ahora),
  ]);
  c.read(sesionProvider.notifier).entrar(b.dueno);
  return (b, c);
}

Future<void> _venta(Banco b, int turno, DateTime fecha, FormaPago forma, List<(Producto, int)> lineas,
    {bool anulada = false}) async {
  final total = lineas.fold(0, (s, l) => s + totalLinea(l.$1.precio, l.$2));
  final id = await b.db.into(b.db.ventas).insert(VentasCompanion.insert(
        fecha: fecha,
        usuarioId: b.dueno.usuarioId,
        turnoCajaId: turno,
        subtotal: total,
        total: total,
        formaPago: forma,
        anulada: Value(anulada),
      ));
  for (final (p, cantidad) in lineas) {
    await b.db.into(b.db.ventaLineas).insert(VentaLineasCompanion.insert(
          ventaId: id,
          productoId: p.id,
          descripcion: p.nombre,
          cantidad: cantidad,
          precioUnitario: p.precio,
          costoUnitario: p.costo,
          total: totalLinea(p.precio, cantidad),
        ));
  }
}

/// Ventas de hoy, de esta semana, de este mes y del mes pasado, y un fiado.
Future<void> _sembrar(Banco b) async {
  await b.abrirCaja();
  final turno = (await b.db.select(b.db.turnosCaja).getSingle()).id;
  final refresco = await b.producto(Banco.refresco);
  final arroz = await b.producto(Banco.arroz);
  await _venta(b, turno, DateTime(2026, 10, 18, 9), FormaPago.efectivo, [(refresco, 2000)]);
  await _venta(b, turno, DateTime(2026, 10, 18, 10), FormaPago.efectivo, [(refresco, 1000)], anulada: true);
  await _venta(b, turno, DateTime(2026, 10, 14, 12), FormaPago.tarjeta, [(arroz, 2000)]);
  await _venta(b, turno, DateTime(2026, 10, 2, 8), FormaPago.efectivo, [(refresco, 1000), (arroz, 1000)]);
  await _venta(b, turno, DateTime(2026, 9, 30, 20), FormaPago.efectivo, [(refresco, 1000)]);
  final cliente = await b.db.into(b.db.clientes).insert(ClientesCompanion.insert(nombre: 'Doña Rosa'));
  await b.db.into(b.db.movimientosFiado).insert(MovimientosFiadoCompanion.insert(
        clienteId: cliente,
        fecha: DateTime(2026, 10, 10),
        tipo: TipoMovFiado.cargo,
        monto: 50000,
      ));
}

Future<ReportesState> _cargado(ProviderContainer c) async {
  c.listen(reportesViewModelProvider, (_, __) {});
  return c.read(reportesViewModelProvider.future);
}

void main() {
  group('rangos', () {
    test('hoy, esta semana (desde el lunes) y este mes', () {
      expect(rangoHoy(_ahora), (DateTime(2026, 10, 18), DateTime(2026, 10, 18)));
      expect(rangoSemana(_ahora), (DateTime(2026, 10, 12), DateTime(2026, 10, 18)));
      expect(rangoMes(_ahora), (DateTime(2026, 10, 1), DateTime(2026, 10, 18)));
    });

    test('el lunes la semana empieza ese mismo día; cruza el mes si hace falta', () {
      expect(rangoSemana(DateTime(2026, 10, 12, 23)), (DateTime(2026, 10, 12), DateTime(2026, 10, 12)));
      expect(rangoSemana(DateTime(2026, 10, 1)), (DateTime(2026, 9, 28), DateTime(2026, 10, 1)));
    });

    test('por ciento redondeado como P0', () {
      expect(porCiento(5000, 19000), 26);
      expect(porCiento(1, 8), 13);
      expect(porCiento(-1, 8), -13);
      expect(porCiento(7000, 28000), 25);
    });
  });

  test('al entrar carga Hoy con las cinco tarjetas', () async {
    final (b, c) = await _preparar();
    await _sembrar(b);
    final s = await _cargado(c);

    expect(s.desde, DateTime(2026, 10, 18));
    expect(s.hasta, DateTime(2026, 10, 18));
    expect([for (final t in s.tarjetas) (t.titulo, t.valor, t.pie)], [
      ('Vendido', 'RD\$ 190.00', '1 ventas'),
      ('Ganancia', 'RD\$ 50.00', '26% del total'),
      ('Ticket promedio', 'RD\$ 190.00', ''),
      ('Fiado en la calle', 'RD\$ 500.00', 'hoy'),
      ('Inventario a costo', 'RD\$ 3,430.00', 'a precio de venta RD\$ 4,530.00'),
    ]);
    expect(s.formasPago, 'Efectivo: RD\$ 190.00');
    expect(s.dias.single.dia, DateTime(2026, 10, 18));
    expect(s.masVendidos.single.nombre, 'Refresco Country Club 2 L');
  });

  test('esta semana, este mes y un rango escogido a mano', () async {
    final (b, c) = await _preparar();
    await _sembrar(b);
    await _cargado(c);
    final vm = c.read(reportesViewModelProvider.notifier);

    await vm.semana();
    var s = c.read(reportesViewModelProvider).value!;
    expect((s.desde, s.hasta), (DateTime(2026, 10, 12), DateTime(2026, 10, 18)));
    expect(s.tarjetas.first.valor, 'RD\$ 280.00');
    expect(s.tarjetas.first.pie, '2 ventas');
    expect(s.tarjetas[1].pie, '25% del total');
    expect(s.formasPago, 'Efectivo: RD\$ 190.00   Tarjeta: RD\$ 90.00');
    expect([for (final d in s.dias) (formatoDia(d.dia), d.cantidad, d.total, d.ganancia)], [
      ('mié 14/10/2026', 1, 9000, 2000),
      ('dom 18/10/2026', 1, 19000, 5000),
    ]);
    expect([for (final p in s.masVendidos) (p.nombre, p.cantidad, p.total)], [
      ('Refresco Country Club 2 L', 2000, 19000),
      ('Arroz Selecto', 2000, 9000),
    ]);

    await vm.mes();
    s = c.read(reportesViewModelProvider).value!;
    expect(s.desde, DateTime(2026, 10, 1));
    expect(s.tarjetas.first.pie, '3 ventas');

    // "Hasta" incluye todo el día; cambiar las fechas no carga hasta tocar Ver.
    vm.cambiarDesde(DateTime(2026, 9, 1));
    vm.cambiarHasta(DateTime(2026, 9, 30, 8));
    s = c.read(reportesViewModelProvider).value!;
    expect(s.tarjetas.first.pie, '3 ventas');
    await vm.ver();
    s = c.read(reportesViewModelProvider).value!;
    expect((s.desde, s.hasta), (DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
    expect(s.tarjetas.first.valor, 'RD\$ 95.00');
    expect(s.tarjetas.first.pie, '1 ventas');
    expect(s.nombreArchivo, 'ventas_2026-09-01_2026-09-30.csv');
  });

  test('sin ventas: ganancia sin por ciento y nada en el tooltip', () async {
    final (_, c) = await _preparar();
    final s = await _cargado(c);
    expect(s.tarjetas.first.pie, '0 ventas');
    expect(s.tarjetas[1].pie, '');
    expect(s.tarjetas[2].valor, 'RD\$ 0.00');
    expect(s.formasPago, '');
    expect(s.dias, isEmpty);
  });

  test('exportar escribe el CSV en UTF-8 con las anuladas', () async {
    final (b, c) = await _preparar();
    await _sembrar(b);
    final s = await _cargado(c);
    expect(s.nombreArchivo, 'ventas_2026-10-18_2026-10-18.csv');

    final carpeta = await Directory.systemTemp.createTemp('emma_reportes_');
    addTearDown(() => carpeta.delete(recursive: true));
    final ruta = '${carpeta.path}/ventas';
    final mensaje = await c.read(reportesViewModelProvider.notifier).exportar(ruta);
    expect(mensaje, 'Se exportaron 2 ventas a $ruta.csv');

    final bytes = await File('$ruta.csv').readAsBytes();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final lineas = (await File('$ruta.csv').readAsString()).trim().split('\n');
    expect(lineas.first, endsWith('numero;fecha;cajero;cliente;forma_pago;subtotal;descuento;total;anulada'));
    expect(lineas, hasLength(3));
    expect(lineas[1], endsWith(';si'));
    expect(lineas[2], contains('2026-10-18 09:00;Dueño;;Efectivo;190.00;0.00;190.00;no'));
  });
}
