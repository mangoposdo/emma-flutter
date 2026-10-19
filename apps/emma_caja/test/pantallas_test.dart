import 'package:emma_caja/app/emma_caja_app.dart';
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/app/router.dart';
import 'package:emma_caja/comun/botones.dart';
import 'package:emma_caja/features/ventas/ventas_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

/// Arma la app completa en una pantalla de mostrador (1280 x 800) para que un
/// desborde o un error de diseño salga en las pruebas.
void main() {
  /// Deja terminar lo que hace la base y redibuja.
  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  Future<Banco> montar(WidgetTester tester, {bool conSesion = true, bool cajaAbierta = false}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final b = await tester.runAsync(Banco.crear);
    if (!conSesion) b!.c.read(sesionProvider.notifier).salir();
    if (cajaAbierta) await tester.runAsync(b!.abrirCaja);
    await tester.pumpWidget(UncontrolledProviderScope(container: b!.c, child: const EmmaCajaApp()));
    await esperar(tester);
    return b;
  }

  testWidgets('la entrada se arma con usuario, PIN y ENTRAR', (tester) async {
    final b = await montar(tester, conSesion: false);
    expect(find.text('ENTRAR'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);
    await tester.runAsync(b.db.close);
  });

  testWidgets('el menú y la venta se arman sin desbordes', (tester) async {
    final b = await montar(tester);
    expect(find.text('Ventas  (F1)'), findsOneWidget);
    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('TOTAL A COBRAR'), findsOneWidget);
    expect(find.text('Escanee o escriba el producto'), findsOneWidget);
    expect(find.text('+ Nuevo pedido'), findsOneWidget);
    // Las pestañas de pedidos van una al lado de la otra, del ancho de lo que dicen.
    final nuevo = find.ancestor(of: find.text('+ Nuevo pedido'), matching: find.byType(BotonRedondo));
    expect(tester.getSize(nuevo).width, lessThan(400));
    expect(tester.takeException(), isNull);
    await tester.runAsync(b.db.close);
  });

  testWidgets('al escribir sale la lista debajo de la casilla y un toque agrega', (tester) async {
    final b = await montar(tester, cajaAbierta: true);
    // El aviso del PIN de fábrica, como lo cerraría el cajero.
    while (find.text('Aceptar').evaluate().isNotEmpty) {
      await tester.tap(find.text('Aceptar'));
      await esperar(tester);
    }
    final casilla = find.widgetWithText(TextField, 'Escanee o escriba el producto');
    final abajo = tester.getBottomLeft(casilla).dy;
    await tester.enterText(casilla, 'coun');
    await tester.pump(VentasViewModel.esperaDelLector);
    await esperar(tester);
    final enLista = find.text('Refresco Country Club 2 L');
    expect(enLista, findsOneWidget);
    expect(tester.getTopLeft(enLista).dy, greaterThan(abajo));

    await tester.tap(enLista);
    await esperar(tester);
    final s = b.c.read(ventasViewModelProvider).requireValue;
    expect(s.busqueda, isEmpty);
    expect(s.lineas.single.producto.codigo, Banco.refresco);
    expect(tester.takeException(), isNull);
    await tester.runAsync(b.db.close);
  });

  for (final p in Pantalla.values) {
    testWidgets('${p.name} se arma sin desbordes en 1280 x 800', (tester) async {
      final b = await montar(tester);
      b.c.read(routerProvider).go(p.ruta);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.text(p.titulo), findsWidgets); // el menú sigue ahí
      await tester.runAsync(b.db.close);
    });
  }
}
