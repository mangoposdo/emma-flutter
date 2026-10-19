import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:emma_caja/features/productos/editor_producto.dart';
import 'package:emma_caja/features/productos/productos_view.dart';
import 'package:emma_caja/features/productos/productos_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

/// Abre la pantalla: el ViewModel vive mientras alguien lo escucha.
Future<ProductosViewModel> abrir(Banco b) async {
  b.c.listen(productosViewModelProvider, (_, __) {});
  await b.c.read(productosViewModelProvider.future);
  return b.c.read(productosViewModelProvider.notifier);
}

ProductosEstado estado(Banco b) => b.c.read(productosViewModelProvider).value!;

List<String> nombres(Banco b) => [for (final f in estado(b).filas) f.producto.nombre];

Future<void> cambiar(Banco b, String codigo, ProductosCompanion datos) =>
    (b.db.update(b.db.productos)..where((p) => p.codigo.equals(codigo))).write(datos);

/// La pantalla dentro de una ventana como la de la caja, sobre la base del banco.
Future<Banco> montar(WidgetTester t, {bool comoCajero = false, Size tamano = const Size(1710, 1080)}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final b = (await t.runAsync(() => Banco.crear(comoCajero: comoCajero)))!;
  await t.pumpWidget(UncontrolledProviderScope(
    container: b.c,
    child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: ProductosView()))),
  ));
  await esperar(t);
  return b;
}

/// Deja correr la base (que es asíncrona de verdad) y dibuja.
Future<void> esperar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

Finder camposDelDialogo() => find.descendant(of: find.byType(Dialog), matching: find.byType(EditableText));

Directory carpetaTemporal() {
  final d = Directory.systemTemp.createTempSync('emma_productos_');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

void main() {
  test('carga la lista en orden y el resumen', () async {
    final b = await Banco.crear();
    await abrir(b);
    final s = estado(b);
    expect(s.esDueno, isTrue);
    expect(nombres(b), ['Arroz Selecto', 'Refresco Country Club 2 L']);
    expect(s.bajos, 0);
    expect(s.resumen, '2 productos mostrados');
    expect(s.escogida, isNull);
  });

  test('busca por nombre o código y esconde los desactivados', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);

    await vm.buscar('arroz');
    expect(nombres(b), ['Arroz Selecto']);
    await vm.buscar('746');
    expect(nombres(b), ['Refresco Country Club 2 L']);
    await vm.buscar('');
    expect(nombres(b), hasLength(2));

    await cambiar(b, Banco.arroz, const ProductosCompanion(activo: Value(false)));
    await vm.recargar();
    expect(nombres(b), ['Refresco Country Club 2 L']);
    await vm.verInactivos(true);
    expect(nombres(b), ['Arroz Selecto', 'Refresco Country Club 2 L']);
    expect(estado(b).filas.first.producto.activo, isFalse);
  });

  test('por agotarse: se cuenta en todo el inventario y se filtra por nombre', () async {
    final b = await Banco.crear();
    await cambiar(b, Banco.refresco, const ProductosCompanion(existenciaMinima: Value(30000)));
    final vm = await abrir(b);

    var s = estado(b);
    expect(s.bajos, 1);
    expect(s.resumen, '2 productos mostrados  ·  1 por agotarse (en amarillo)');
    expect([for (final f in s.filas) f.bajoMinimo], [false, true]);

    await vm.soloBajoMinimo(true);
    expect(nombres(b), ['Refresco Country Club 2 L']);
    await vm.buscar('arroz');
    s = estado(b);
    expect(s.filas, isEmpty);
    expect(s.bajos, 1);
    expect(s.resumen, '0 productos mostrados  ·  1 por agotarse (en amarillo)');
    // Con "Solo por agotarse" se busca por el nombre, no por el código.
    await vm.buscar('746');
    expect(estado(b).filas, isEmpty);
    await vm.buscar('country');
    expect(nombres(b), ['Refresco Country Club 2 L']);

    // Un desactivado no cuenta como "por agotarse".
    await cambiar(b, Banco.refresco, const ProductosCompanion(activo: Value(false)));
    await vm.soloBajoMinimo(false);
    expect(estado(b).bajos, 0);
  });

  test('la fila escogida se queda al volver a buscar', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    vm.escoger(1);
    expect(estado(b).seleccionado?.codigo, Banco.refresco);
    await vm.buscar('refresco');
    expect(estado(b).escogida, 0);
    await vm.buscar('arroz');
    expect(estado(b).seleccionado, isNull);
  });

  test('ajustar existencia: conteo físico, pérdida y llegó mercancía', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final refresco = await b.producto(Banco.refresco);

    await vm.ajustar(refresco.id, TipoMovInventario.ajuste, 20000, 'Conteo del lunes');
    expect((await b.producto(Banco.refresco)).existencia, 20000);
    await vm.ajustar(refresco.id, TipoMovInventario.perdida, 2000, null);
    expect((await b.producto(Banco.refresco)).existencia, 18000);
    await vm.ajustar(refresco.id, TipoMovInventario.compra, 5000, null);
    expect((await b.producto(Banco.refresco)).existencia, 23000);
    // Contar lo mismo que hay no anota nada.
    await vm.ajustar(refresco.id, TipoMovInventario.ajuste, 23000, null);

    final movs = await vm.movimientos(refresco.id);
    expect([
      for (final m in movs) (m.tipo, m.cantidad, m.existenciaResultante)
    ], [
      (TipoMovInventario.compra, 5000, 23000),
      (TipoMovInventario.perdida, -2000, 18000),
      (TipoMovInventario.ajuste, -4000, 20000),
    ]);
    expect(movs.last.referencia, 'Conteo del lunes');
    expect(estado(b).filas.firstWhere((f) => f.producto.id == refresco.id).producto.existencia, 23000);

    // Por unidad no lleva decimales; por libra sí.
    await expectLater(vm.ajustar(refresco.id, TipoMovInventario.perdida, 1500, null), throwsA(isA<DatoInvalido>()));
    final arroz = await b.producto(Banco.arroz);
    await vm.ajustar(arroz.id, TipoMovInventario.perdida, 1500, null);
    expect((await b.producto(Banco.arroz)).existencia, 48500);
  });

  test('el cajero ve todo pero no crea, ajusta ni importa', () async {
    final b = await Banco.crear(comoCajero: true);
    final vm = await abrir(b);
    expect(estado(b).esDueno, isFalse);
    expect(nombres(b), hasLength(2));

    final refresco = await b.producto(Banco.refresco);
    await expectLater(vm.ajustar(refresco.id, TipoMovInventario.perdida, 1000, null), throwsA(isA<PermisoDenegado>()));
    await expectLater(b.c.read(editorProductoProvider).guardar(const DatosProducto(nombre: 'Pan', precio: 500)),
        throwsA(isA<PermisoDenegado>()));
    final archivo = File('${carpetaTemporal().path}/p.csv')..writeAsStringSync('codigo,nombre,precio\n1,Pan,5\n');
    await expectLater(vm.importar(archivo.path), throwsA(isA<PermisoDenegado>()));
    // Ver movimientos y exportar sí puede.
    expect(await vm.movimientos(refresco.id), isEmpty);
  });

  test('el formulario guarda con categoría nueva y la encuentra al editar', () async {
    final b = await Banco.crear();
    final editor = b.c.read(editorProductoProvider);
    final p = await editor.guardar(const DatosProducto(
      codigo: '7461234567890',
      nombre: 'Pan de agua',
      categoria: 'Panadería',
      costo: 300,
      precio: 500,
      existencia: 40000,
      tasaItbis: 1800,
      esRapido: true,
    ));
    expect((p.existencia, p.tasaItbis, p.esRapido, p.activo), (40000, 1800, true, true));
    expect(await editor.nombreCategoria(p.categoriaId), 'Panadería');
    expect(await editor.nombreCategoria(null), isNull);
    expect((await editor.porId(p.id))?.nombre, 'Pan de agua');
    await expectLater(
        editor.guardar(const DatosProducto(codigo: Banco.refresco, nombre: 'Otro', precio: 100)),
        throwsA(
            isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Ya existe otro producto con el código 7460001.')));
  });

  test('importar CSV en UTF-8 con BOM: resumen y filas con problemas', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final archivo = File('${carpetaTemporal().path}/productos.csv')
      ..writeAsBytesSync([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('codigo;nombre;categoria;costo;precio;existencia;minimo;unidad\n'
            '9001;Café Santo Domingo;Café;100;150;10;2;unidad\n'
            ';Sin precio;;;;;;\n'
            '${Banco.refresco};Refresco Country Club 2 L;Bebidas;72;100;99;6;unidad\n'),
      ]);

    final msg = await vm.importar(archivo.path);
    expect(msg, 'Productos nuevos: 1\nActualizados: 1\n\nFilas con problemas (1):\nFila 3: precio inválido "".');
    expect(nombres(b), ['Arroz Selecto', 'Café Santo Domingo', 'Refresco Country Club 2 L']);
    final refresco = await b.producto(Banco.refresco);
    expect((refresco.precio, refresco.existencia), (10000, 24000));
  });

  test('importar CSV de Excel viejo (latin1) y leer el texto', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final archivo = File('${carpetaTemporal().path}/viejo.csv')
      ..writeAsBytesSync(latin1.encode('codigo,nombre,categoria,costo,precio\n9002,Jugo de Piña,Bebidas,50,75\n'));
    expect(await vm.importar(archivo.path), 'Productos nuevos: 1\nActualizados: 0');
    expect(nombres(b), contains('Jugo de Piña'));

    expect(leerTextoCsv([0xEF, 0xBB, 0xBF, ...utf8.encode('año')]), 'año');
    expect(leerTextoCsv(utf8.encode('año')), 'año');
    expect(leerTextoCsv(latin1.encode('año')), 'año');
    await expectLater(vm.importar('${archivo.path}.no-existe'), throwsA(isA<DatoInvalido>()));
  });

  test('exportar: CSV con BOM, nombre del día y extensión', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    expect(nombreExportacion(DateTime(2026, 10, 3)), 'productos_2026-10-03.csv');

    final ruta = '${carpetaTemporal().path}/productos';
    final destino = await vm.exportar(ruta);
    expect(destino, '$ruta.csv');
    final bytes = File(destino).readAsBytesSync();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final texto = utf8.decode(bytes.skip(3).toList());
    expect(texto, startsWith('codigo;nombre;categoria;costo;precio;existencia;minimo;unidad;activo'));
    expect(texto, contains('7460001;Refresco Country Club 2 L;;70.00;95.00;24;0;unidad;si'));
  });

  group('pantalla', () {
    testWidgets('nuevo producto: si el precio es menor que el costo y dicen que no, vuelve con lo escrito', (t) async {
      final b = await montar(t);
      expect(find.text('2 productos mostrados'), findsOneWidget);

      await t.tap(find.text('Nuevo producto'));
      await esperar(t);
      expect(find.text('Existencia inicial'), findsOneWidget);
      expect(find.text('Para corregir la existencia de un producto que ya existe use "Ajustar existencia".'),
          findsOneWidget);
      // Código, nombre, categoría, costo, precio, existencia inicial, mínimo.
      await t.enterText(camposDelDialogo().at(1), 'Galletas');
      await t.enterText(camposDelDialogo().at(3), '50');
      await t.enterText(camposDelDialogo().at(4), '40');
      await t.tap(find.text('Aceptar'));
      await esperar(t);
      expect(find.text('El precio es menor que el costo. ¿Guardar de todos modos?'), findsOneWidget);
      await t.tap(find.text('No'));
      await esperar(t);
      expect(find.text('Nuevo producto'), findsNWidgets(2), reason: 'el formulario vuelve a salir');
      expect(t.widget<EditableText>(camposDelDialogo().at(1)).controller.text, 'Galletas');
      expect(t.widget<EditableText>(camposDelDialogo().at(4)).controller.text, '40');
      await t.enterText(camposDelDialogo().at(4), '60');
      await t.tap(find.text('Aceptar'));
      await esperar(t);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('3 productos mostrados  ·  1 por agotarse (en amarillo)'), findsOneWidget);
      expect((await t.runAsync(() => b.contar('productos')))!, 5, reason: 'más Varios y el envío');
    });

    testWidgets('ajustar, ver movimientos y doble clic para editar', (t) async {
      await montar(t);
      await t.tap(find.text('Refresco Country Club 2 L'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Ajustar existencia'));
      await esperar(t);
      expect(find.text('Ajustar: Refresco Country Club 2 L'), findsOneWidget);
      expect(
          find.text(
              'Existencia actual: 24. En "Conteo físico" escriba lo que contó; en los otros, cuánto entra o sale.'),
          findsOneWidget);
      await t.enterText(camposDelDialogo().first, '20');
      await t.tap(find.text('Aceptar'));
      await esperar(t);
      expect(find.text('20'), findsOneWidget);

      await t.tap(find.text('Ver movimientos'));
      await esperar(t);
      expect(find.text('Movimientos: Refresco Country Club 2 L'), findsOneWidget);
      expect(find.text('-4'), findsOneWidget);
      expect(find.text('Ajuste'), findsOneWidget);
      await t.tap(find.byIcon(Icons.close));
      await esperar(t);

      await t.tap(find.text('Arroz Selecto'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text('Arroz Selecto'));
      await esperar(t);
      expect(find.text('Editar producto'), findsOneWidget);
      expect(find.text('Existencia inicial'), findsNothing);
      expect(t.widget<EditableText>(camposDelDialogo().at(1)).controller.text, 'Arroz Selecto');
      await t.tap(find.text('Cancelar'));
      await esperar(t);
    });

    testWidgets('el cajero tiene apagados Nuevo, Editar, Ajustar e Importar', (t) async {
      await montar(t, comoCajero: true, tamano: const Size(1156, 768));
      TextButton boton(String texto) =>
          t.widget<TextButton>(find.ancestor(of: find.text(texto), matching: find.byType(TextButton)));
      for (final texto in ['Nuevo producto', 'Editar', 'Ajustar existencia', 'Importar desde Excel (CSV)']) {
        expect(boton(texto).onPressed, isNull, reason: texto);
      }
      expect(boton('Ver movimientos').onPressed, isNotNull);
      expect(boton('Exportar a Excel').onPressed, isNotNull);
      await t.tap(find.text('Arroz Selecto'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text('Arroz Selecto'));
      await esperar(t);
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
