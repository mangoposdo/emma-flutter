import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late ProductoService productos;
  late Sesion dueno;

  setUp(() async {
    db = baseDePrueba();
    productos = ProductoService(db);
    dueno = await sesionDueno(db);
  });

  tearDown(() => db.close());

  test('crear un producto con existencia deja el movimiento inicial y la bitácora', () async {
    final p = await productos.guardar(
      dueno,
      const DatosProducto(codigo: ' 7460001 ', nombre: ' Leche 1 L ', categoria: 'Lácteos', costo: 7000, precio: 9000, existencia: 12000),
    );
    expect(p.codigo, '7460001');
    expect(p.nombre, 'Leche 1 L');
    expect(p.existencia, 12000);
    final movs = await productos.movimientos(p.id);
    expect(movs.single.tipo, TipoMovInventario.inventarioInicial);
    expect((await productos.listado()).single.categoria, 'Lácteos');
    expect((await db.select(db.bitacora).getSingle()).accion, 'Producto creado');
  });

  test('un producto puede no tener código', () async {
    final p = await productos.guardar(dueno, const DatosProducto(nombre: 'Pan de agua', precio: 1000));
    expect(p.codigo, isNull);
    expect((await productos.buscar('pan')).single.id, p.id);
  });

  test('el código repetido se rechaza', () async {
    await productos.guardar(dueno, const DatosProducto(codigo: '111', nombre: 'Uno', precio: 100));
    await expectLater(
      productos.guardar(dueno, const DatosProducto(codigo: '111', nombre: 'Dos', precio: 100)),
      throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Ya existe otro producto con el código 111.')),
    );
  });

  test('el cajero no puede cambiar productos ni ajustar ni importar', () async {
    final maria = await crearCajero(db);
    await expectLater(productos.guardar(maria, const DatosProducto(nombre: 'X', precio: 1)), throwsA(isA<PermisoDenegado>()));
    final id = await crearProducto(db, codigo: '1', nombre: 'Uno', precio: 100);
    await expectLater(productos.ajustar(maria, id, 1000, TipoMovInventario.ajuste), throwsA(isA<PermisoDenegado>()));
    await expectLater(productos.importarCsv(maria, 'a\n'), throwsA(isA<PermisoDenegado>()));
  });

  test('cambiar el precio queda en la bitácora', () async {
    final p = await productos.guardar(dueno, const DatosProducto(codigo: '9', nombre: 'Aceite', precio: 16500));
    await productos.guardar(dueno, DatosProducto(id: p.id, codigo: '9', nombre: 'Aceite', precio: 17000));
    final b = await (db.select(db.bitacora)..where((x) => x.accion.equals('Cambio de precio'))).getSingle();
    expect(b.detalle, 'Aceite: RD\$ 165.00 -> RD\$ 170.00');
  });

  test('los productos internos no se pueden usar ni cambiar', () async {
    await expectLater(
      productos.guardar(dueno, const DatosProducto(codigo: codigoVarios, nombre: 'X', precio: 1)),
      throwsA(isA<DatoInvalido>()),
    );
    final varios = await db.productoVarios();
    await expectLater(
      productos.guardar(dueno, DatosProducto(id: varios.id, nombre: 'Otro', precio: 5)),
      throwsA(isA<DatoInvalido>()),
    );
    expect(await productos.listado(incluirInactivos: true), isEmpty);
  });

  test('el ajuste de inventario queda registrado', () async {
    final id = await crearProducto(db, codigo: '1', nombre: 'Arroz', precio: 4500, existencia: 10000, unidad: UnidadVenta.libra);
    final p = await productos.ajustar(dueno, id, -2500, TipoMovInventario.perdida, nota: 'Se mojó');
    expect(p.existencia, 7500);
    final m = (await productos.movimientos(id)).first;
    expect(m.cantidad, -2500);
    expect(m.existenciaResultante, 7500);
    expect(m.referencia, 'Se mojó');
    final b = await (db.select(db.bitacora)..where((x) => x.accion.equals('Ajuste de inventario'))).getSingle();
    expect(b.detalle, 'Arroz: -2.5 (Pérdida) Se mojó');
    await expectLater(productos.ajustar(dueno, id, 0, TipoMovInventario.ajuste), throwsA(isA<DatoInvalido>()));
  });

  test('por agotarse: existencia en el mínimo o por debajo', () async {
    await productos.guardar(dueno, const DatosProducto(codigo: '1', nombre: 'Sal', precio: 1000, existencia: 2000, existenciaMinima: 3000));
    await productos.guardar(dueno, const DatosProducto(codigo: '2', nombre: 'Azúcar', precio: 1000, existencia: 9000, existenciaMinima: 3000));
    expect((await productos.bajoMinimo()).map((f) => f.producto.nombre), ['Sal']);
  });

  test('importa un CSV de Excel en español (punto y coma, coma decimal)', () async {
    await productos.guardar(dueno, const DatosProducto(codigo: '7460001', nombre: 'Viejo', precio: 100, existencia: 5000));
    const csv = '﻿codigo;nombre;categoria;costo;precio;existencia;minimo;unidad\n'
        '7460001;Refresco 2 L;Bebidas;70;95,50;99;6;unidad\n'
        '200;Arroz selecto;Granos;35;45;"50,5";10;libra\n'
        ';Pan de agua;;;10;;;\n'
        '300;;;;10;;;\n'
        '301;Sin precio;;;abc;;;\n';
    final r = await productos.importarCsv(dueno, csv);
    expect(r.creados, 2);
    expect(r.actualizados, 1);
    expect(r.errores, ['Fila 5: falta el nombre.', 'Fila 6: precio inválido "abc".']);

    final refresco = (await productos.porCodigo('7460001'))!;
    expect(refresco.nombre, 'Refresco 2 L');
    expect(refresco.precio, 9550);
    expect(refresco.existencia, 5000); // no se toca la existencia de uno que ya existe
    final arroz = (await productos.porCodigo('200'))!;
    expect(arroz.unidad, UnidadVenta.libra);
    expect(arroz.existencia, 50500);
    expect((await productos.buscar('pan de agua')).single.codigo, isNull);
  });

  test('exporta a CSV con punto y coma y montos sin miles', () async {
    await productos.guardar(dueno, const DatosProducto(codigo: '1', nombre: 'Café; molido', precio: 126000, costo: 100000));
    final csv = await productos.exportarCsv();
    expect(csv, startsWith('﻿codigo;nombre;categoria;costo;precio;existencia;minimo;unidad;activo\n'));
    expect(csv, contains('1;"Café; molido";;1000.00;1260.00;0;0;unidad;si'));
  });
}
