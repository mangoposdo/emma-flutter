import 'dart:io';

import 'package:emma_caja/app/cuidados.dart';
import 'package:emma_caja/app/emma_caja_app.dart';
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/comun/estilo.dart';
import 'package:emma_caja/comun/tabla.dart';
import 'package:emma_caja/features/caja/caja_view.dart';
import 'package:emma_caja/features/caja/caja_view_model.dart';
import 'package:emma_caja/features/caja/conteo_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

/// Sin nube ni archivos: cuenta los envíos y da un respaldo de mentira.
class _CuidadosDePrueba extends Cuidados {
  _CuidadosDePrueba(super.ref, {required this.respaldoFalla});

  final bool respaldoFalla;
  var envios = 0;

  @override
  Future<ResultadoSincronizacion?> enviarANube() async {
    envios++;
    return null;
  }

  @override
  Future<String> respaldoCompleto() async {
    if (respaldoFalla) throw const EmmaError('el disco está lleno');
    return 'Respaldo guardado en emma_prueba.db';
  }
}

/// La base del [Banco] con un contenedor propio: los cuidados de prueba y una
/// carpeta de datos que se borra al final.
class _Caja {
  _Caja(this.b, this.c, this.cuidados);

  final Banco b;
  final ProviderContainer c;
  final _CuidadosDePrueba cuidados;

  CajaViewModel get vm => c.read(cajaViewModelProvider.notifier);
  CajaState get s => c.read(cajaViewModelProvider).value!;

  static Future<_Caja> crear({bool comoCajero = false, bool respaldoFalla = false}) async {
    final b = await Banco.crear(comoCajero: comoCajero);
    final carpeta = Directory.systemTemp.createTempSync('emma_caja_prueba_');
    addTearDown(() => carpeta.deleteSync(recursive: true));
    late _CuidadosDePrueba cuidados;
    final c = ProviderContainer.test(overrides: [
      baseDeDatosProvider.overrideWithValue(b.db),
      carpetaDatosProvider.overrideWithValue(carpeta),
      cuidadosProvider.overrideWith((ref) => cuidados = _CuidadosDePrueba(ref, respaldoFalla: respaldoFalla)),
    ]);
    c.read(sesionProvider.notifier).entrar(b.c.read(sesionProvider)!);
    c.listen(cajaViewModelProvider, (_, __) {});
    await c.read(cajaViewModelProvider.future);
    c.read(cuidadosProvider);
    return _Caja(b, c, cuidados);
  }

  /// Venta de contado de [cantidad] refrescos (RD$ 95.00 cada uno) hecha por el dueño.
  Future<int> vender({int cantidad = 1, FormaPago forma = FormaPago.efectivo}) async {
    final p = await b.producto(Banco.refresco);
    final r = await VentaService(b.db).cobrar(
      b.dueno,
      SolicitudCobro(
        lineas: [LineaCobro(productoId: p.id, descripcion: p.nombre, cantidad: cantidad * 1000, precioUnitario: p.precio)],
        formaPago: forma,
      ),
    );
    await vm.recargar();
    return r.ventaId;
  }

  int monto(String fila) => s.filasResumen.firstWhere((f) => f.texto == fila).monto;
}

void main() {
  test('abre la caja con el fondo escrito y refresca el menú', () async {
    final k = await _Caja.crear();
    expect(k.s.abierta, isFalse);
    expect(k.s.historial, isEmpty);
    expect(await k.c.read(turnoAbiertoProvider.future), isNull);

    await expectLater(k.vm.abrir('mil'),
        throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Escriba el fondo inicial (puede ser 0).')));
    expect(k.s.abierta, isFalse);

    await k.vm.abrir('1,500');
    expect(k.s.abierta, isTrue);
    expect(k.s.textoTurno, startsWith('Abierta por ${k.b.dueno.nombre} el '));
    expect(k.s.textoTurno, matches(RegExp(r' el \d\d/\d\d/\d{4} a las \d\d:\d\d [ap]\. m\.$')));
    expect(k.monto('Fondo inicial'), 150000);
    expect(k.monto('Debe haber en la gaveta'), 150000);
    expect(await k.c.read(turnoAbiertoProvider.future), isNotNull); // el menú ya dice "Caja abierta desde..."

    await expectLater(k.vm.abrir('0'), throwsA(isA<DatoInvalido>()));
  });

  test('el resumen de la 0.7, con entradas, salidas y ventas', () async {
    final k = await _Caja.crear();
    await k.vm.abrir('1000');
    await k.vm.movimiento(TipoMovCaja.entrada, 50000, 'Cambio del banco');
    await k.vm.movimiento(TipoMovCaja.salida, 20000, 'Pago al suplidor de pan');
    await k.vender(cantidad: 2);
    await k.vender(forma: FormaPago.tarjeta);

    expect(k.s.filasResumen.map((f) => (f.texto, f.monto, f.negrita)), [
      ('Ventas (2)', 28500, true),
      ('   Efectivo', 19000, false),
      ('   Tarjeta', 9500, false),
      ('   Transferencia', 0, false),
      ('   Fiado', 0, false),
      ('Fondo inicial', 100000, false),
      ('+ Abonos en efectivo', 0, false),
      ('+ Entradas', 50000, false),
      ('- Salidas', 20000, false),
      ('Debe haber en la gaveta', 149000, true),
    ]);
    expect(k.s.ventas, hasLength(2));
    expect(k.s.ventas.first.venta.formaPago, FormaPago.tarjeta); // la más nueva arriba

    await expectLater(k.vm.movimiento(TipoMovCaja.salida, 1000, '  '), throwsA(isA<DatoInvalido>()));
    expect(await k.vm.preguntaAntesDeCerrar(), isNull);
  });

  test('cierre con faltante: el mensaje, el historial, la nube y el respaldo', () async {
    final k = await _Caja.crear();
    await k.vm.abrir('1000');
    await k.vender(); // debe haber 1,095.00

    final r = await k.vm.cerrar({1000: 1, 5: 1}, '  Faltó el cambio  ');
    expect(r.errorImpresion, isNull);
    expect(
      r.mensaje,
      'Caja cerrada.\n\nDebía haber: RD\$ 1,095.00\nSe contó: RD\$ 1,005.00\nFALTANTE: RD\$ 90.00\n\n'
      'Respaldo guardado en emma_prueba.db',
    );
    expect(k.cuidados.envios, 1);
    expect(k.s.abierta, isFalse);
    expect(k.s.historial, hasLength(1));
    final t = k.s.historial.single.turno;
    expect((t.efectivoEsperado, t.efectivoContado, t.diferencia, t.notas), (109500, 100500, -9000, 'Faltó el cambio'));
    expect(await k.c.read(turnoAbiertoProvider.future), isNull);

    // Cerrar otra vez: ya está cerrada.
    await expectLater(k.vm.cerrar(const {}, null), throwsA(isA<CajaCerrada>()));
  });

  test('cierre con sobrante y cuadrado; si el respaldo falla lo dice', () async {
    final k = await _Caja.crear(respaldoFalla: true);
    await k.vm.abrir('500');
    final sobra = await k.vm.cerrar({500: 1, 1: 3}, null);
    expect(sobra.mensaje, contains('Debía haber: RD\$ 500.00\nSe contó: RD\$ 503.00\nSOBRANTE: RD\$ 3.00\n\n'));
    expect(sobra.mensaje, endsWith('No se pudo hacer el respaldo: el disco está lleno'));

    await k.vm.abrir('200');
    final cuadra = await k.vm.cerrar({100: 2}, null);
    expect(cuadra.mensaje, contains('Se contó: RD\$ 200.00\nLa caja cuadra.\n\n'));
    // Los cuadres anteriores, el más nuevo arriba.
    expect(k.s.historial.map((h) => h.turno.efectivoContado), [20000, 50300]);
  });

  test('conteo: subtotales, total, la cantidad mal escrita y la pregunta', () async {
    final k = await _Caja.crear();
    k.c.listen(conteoViewModelProvider, (_, __) {});
    final vm = k.c.read(conteoViewModelProvider.notifier);
    ConteoState s() => k.c.read(conteoViewModelProvider);

    expect(ConteoState.denominaciones.map(ConteoState.etiqueta).toList(), [
      'Billetes de 2,000', 'Billetes de 1,000', 'Billetes de 500', 'Billetes de 200', 'Billetes de 100',
      'Billetes de 50', 'Monedas de 25', 'Monedas de 10', 'Monedas de 5', 'Monedas de 1',
    ]);
    expect(s().totalTexto, 'RD\$ 0.00');
    vm.cambiar(2000, '2');
    vm.cambiar(25, ' 3 ');
    vm.cambiar(1, '0');
    expect(s().subtotalTexto(2000), '4,000.00');
    expect(s().subtotalTexto(1), '');
    expect(s().totalTexto, 'RD\$ 4,075.00');
    expect(vm.revisar(), isNull);
    expect(vm.pregunta, 'Se contaron RD\$ 4,075.00. ¿Cerrar la caja?');
    vm.cambiarNotas('  ');
    expect(vm.resultado.conteo, {2000: 2, 25: 3, 1: 0});
    expect(vm.resultado.notas, isNull);

    vm.cambiar(100, 'dos');
    vm.cambiar(5, '-1');
    expect(vm.revisar(), 'Revise la cantidad de 100.');
    expect(s().totalTexto, 'RD\$ 4,075.00'); // lo mal escrito no suma
    vm.cambiar(100, '');
    expect(vm.revisar(), 'Revise la cantidad de 5.');
  });

  test('anular: el cajero ve la venta y debe llamar al dueño', () async {
    final k = await _Caja.crear(comoCajero: true);
    await k.b.abrirCaja();
    await k.vm.recargar();
    await k.vender();

    final v = (await k.vm.verVenta(0))!;
    expect(v.preguntarAnular, isFalse);
    expect(v.mensaje, startsWith('Venta #${v.id}  '));
    expect(v.mensaje, contains('Efectivo\n\n1 x Refresco Country Club 2 L  RD\$ 95.00\n\nTotal: RD\$ 95.00'));
    expect(v.mensaje, endsWith('\n\nPara anular una venta llame al dueño.'));
    await expectLater(k.vm.anular(v.id, 'Se equivocó'), throwsA(isA<PermisoDenegado>()));
    expect(k.s.ventas.single.venta.anulada, isFalse);
  });

  test('anular: el dueño confirma, pone el motivo y la venta sale anulada', () async {
    final k = await _Caja.crear();
    await k.vm.abrir('1000');
    await k.vender(cantidad: 3);

    final v = (await k.vm.verVenta(0))!;
    expect(v.preguntarAnular, isTrue);
    expect(v.mensaje, contains('3 x Refresco Country Club 2 L  RD\$ 285.00'));
    expect(v.mensaje, endsWith('\n\n¿Desea ANULAR esta venta? Los productos vuelven al inventario.'));

    await expectLater(k.vm.anular(v.id, ' '), throwsA(isA<DatoInvalido>()));
    await k.vm.anular(v.id, 'Cliente se arrepintió');
    expect(k.s.ventas.single.venta.anulada, isTrue);
    expect(k.monto('Ventas (0)'), 0);
    expect(k.monto('Debe haber en la gaveta'), 100000);
    expect((await k.b.producto(Banco.refresco)).existencia, 24000); // volvió al inventario

    final otra = (await k.vm.verVenta(0))!;
    expect(otra.preguntarAnular, isFalse);
    expect(otra.mensaje, endsWith('\n\nANULADA: Cliente se arrepintió'));
  });

  test('reimprimir un cuadre sin impresora', () async {
    final k = await _Caja.crear();
    await k.vm.abrir('0');
    await k.vm.cerrar(const {}, null);
    expect(await k.vm.reimprimir(0), (texto: 'No hay impresora configurada.', esError: false));
    expect(await k.vm.reimprimir(5), isNull);
  });

  pruebasDePantalla();
}

/// La pantalla dentro de un área como la de la ventana principal (16 px de margen).
Widget _pantalla(ProviderContainer c, Widget hijo) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: temaCaja(),
        home: Scaffold(backgroundColor: Estilo.fondo, body: Padding(padding: const EdgeInsets.all(16), child: hijo)),
      ),
    );

void _tamano(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// La letra de la app (Archivo), para que las medidas sean las de verdad.
Future<void> _cargarLetra() async {
  final archivo = File('../../packages/emma_marca/assets/fuentes/Archivo.ttf');
  final datos = archivo.readAsBytesSync();
  await (FontLoader('packages/emma_marca/Archivo')..addFont(Future.value(ByteData.sublistView(datos)))).load();
}

void pruebasDePantalla() {
  setUpAll(_cargarLetra);
  for (final alto in [768.0, 560.0]) {
    testWidgets('la pantalla se dibuja cerrada, abierta y con el conteo (alto $alto)', (tester) async {
      _tamano(tester, Size(1156, alto));
      final k = (await tester.runAsync(_Caja.crear))!;
      await tester.pumpWidget(_pantalla(k.c, const CajaView()));
      await tester.pump();
      expect(find.text('La caja está cerrada'), findsOneWidget);
      expect(find.text('Cuadres anteriores (doble clic para reimprimir)'), findsOneWidget);
      // Los cuadres anteriores llenan hasta abajo (16 px de margen).
      expect(tester.getRect(find.byWidgetPredicate((w) => w is Tabla<TurnoConCajero>)).bottom, alto - 16);

      await tester.runAsync(() async {
        await k.vm.abrir('1000');
        for (var i = 0; i < 20; i++) {
          await k.vender();
        }
      });
      await tester.pump();
      expect(find.text('Ventas de este turno (doble clic para ver o anular)'), findsOneWidget);
      expect(find.text('Debe haber en la gaveta'), findsOneWidget);
      expect(find.text('RD\$ 2,900.00'), findsOneWidget);

      await tester.ensureVisible(find.text('Cerrar caja y cuadrar'));
      await tester.tap(find.text('Cerrar caja y cuadrar'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Cerrar caja: contar el efectivo'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(find.text('RD\$ 2,000.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Cerrar caja: contar el efectivo'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
