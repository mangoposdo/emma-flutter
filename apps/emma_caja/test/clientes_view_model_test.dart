import 'dart:io';

import 'package:emma_caja/app/emma_caja_app.dart';
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/comun/estilo.dart';
import 'package:emma_caja/features/clientes/cliente_formulario_view_model.dart';
import 'package:emma_caja/features/clientes/cliente_picker.dart';
import 'package:emma_caja/features/clientes/cliente_picker_view_model.dart';
import 'package:emma_caja/features/clientes/clientes_view.dart';
import 'package:emma_caja/features/clientes/clientes_view_model.dart';
import 'package:emma_caja/features/clientes/recurrencia_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

/// Clientes de prueba: dos que deben y cuatro que no, con nombres que en el
/// orden de Windows no van como en la base (mayúsculas y tildes).
class _Clientes {
  _Clientes(this.ana, this.pedro, this.carla, this.zoila, this.beto, this.alvaro);

  final Cliente ana;
  final Cliente pedro;
  final Cliente carla;
  final Cliente zoila;
  final Cliente beto;
  final Cliente alvaro;

  static Future<_Clientes> crear(Banco b) async {
    final f = FiadoService(b.db);
    Future<Cliente> uno(String nombre, {bool fijo = false, String? telefono, String? sector}) =>
        f.guardarCliente(b.dueno, DatosCliente(nombre: nombre, esFijo: fijo, telefono: telefono, sector: sector));
    final c = _Clientes(
      await uno('Ana', telefono: '809-555-1111'),
      await uno('Pedro', fijo: true, sector: 'Los Mina'),
      await uno('Carla', fijo: true),
      await uno('Zoila'),
      await uno('beto'),
      await uno('Álvaro'),
    );
    await b.abrirCaja();
    await _fiar(b, c.ana, 50000);
    await _fiar(b, c.pedro, 30000);
    return c;
  }
}

Future<void> _fiar(Banco b, Cliente c, int monto) => VentaService(b.db).cobrar(
      b.dueno,
      SolicitudCobro(lineas: [LineaCobro.varios(monto)], formaPago: FormaPago.fiado, clienteId: c.id),
    );

/// Mantiene vivo el ViewModel (es autoDispose) y espera la primera carga.
Future<ClientesViewModel> _abrir(ProviderContainer c) async {
  c.listen(clientesViewModelProvider, (_, __) {});
  await c.read(clientesViewModelProvider.future);
  return c.read(clientesViewModelProvider.notifier);
}

List<String> _nombres(ProviderContainer c) =>
    c.read(clientesViewModelProvider).value!.filas.map((f) => f.cliente.nombre).toList();

void main() {
  test('primero el que más debe, después los fijos, después por nombre como en Windows', () async {
    final b = await Banco.crear();
    await _Clientes.crear(b);
    await _abrir(b.c);

    expect(_nombres(b.c), ['Ana', 'Pedro', 'Carla', 'Álvaro', 'beto', 'Zoila']);
    final s = b.c.read(clientesViewModelProvider).value!;
    expect(s.resumen, 'Total fiado en la calle: RD\$ 800.00  ·  2 clientes deben');

    final ana = s.filas[0];
    expect(ana.debe, 50000);
    expect(ana.diasSinPagar, 0);
    expect(ana.ultimoAbono, isNull);
    expect(ana.ultimaCompra, isNotNull);
    expect(ana.limiteTexto, 'Sin límite');
    expect(ana.nombre, 'Ana');
    expect(s.filas[1].nombre, '★ Pedro');
    final carla = s.filas[2];
    expect(carla.debe, 0);
    expect(carla.diasSinPagar, isNull);
    expect(carla.ultimaCompra, isNull);
  });

  test('búsqueda por nombre o teléfono y los dos filtros; el total no cambia', () async {
    final b = await Banco.crear();
    await _Clientes.crear(b);
    final vm = await _abrir(b.c);

    await vm.cambiarSoloDeben(true);
    expect(_nombres(b.c), ['Ana', 'Pedro']);

    await vm.cambiarSoloFijos(true);
    expect(_nombres(b.c), ['Pedro']);

    await vm.cambiarSoloDeben(false);
    expect(_nombres(b.c), ['Pedro', 'Carla']);

    await vm.cambiarSoloFijos(false);
    await vm.buscar('555');
    expect(_nombres(b.c), ['Ana']);

    await vm.buscar('ar');
    expect(_nombres(b.c), ['Carla', 'Álvaro']);
    expect(b.c.read(clientesViewModelProvider).value!.resumen, 'Total fiado en la calle: RD\$ 800.00  ·  2 clientes deben');
  });

  test('el límite sale como monto, y "Sin límite" si es 0', () async {
    final b = await Banco.crear();
    await FiadoService(b.db).guardarCliente(b.dueno, const DatosCliente(nombre: 'Luis', limiteCredito: 150000));
    await _abrir(b.c);
    expect(b.c.read(clientesViewModelProvider).value!.filas.single.limiteTexto, '1,500.00');
  });

  test('el abono baja la deuda, queda la fecha del abono y se mantiene la selección', () async {
    final b = await Banco.crear();
    final cl = await _Clientes.crear(b);
    final vm = await _abrir(b.c);
    vm.escoger(0);
    expect(b.c.read(clientesViewModelProvider).value!.seleccionada!.cliente.id, cl.ana.id);

    expect(await vm.debe(cl.ana), 50000);
    expect(await vm.debe(cl.carla), 0);
    final error = await vm.abonar(cl.ana, 20000, FormaPago.efectivo, 'Parte de la quincena');
    expect(error, isNull); // sin impresora no se imprime nada

    final s = b.c.read(clientesViewModelProvider).value!;
    expect(s.resumen, 'Total fiado en la calle: RD\$ 600.00  ·  2 clientes deben');
    expect(s.seleccionada!.cliente.id, cl.ana.id);
    expect(s.seleccionada!.debe, 30000);
    expect(s.seleccionada!.ultimoAbono, isNotNull);

    final lineas = await vm.estadoCuenta(cl.ana);
    expect(lineas.map((l) => l.concepto), [startsWith('Compra #'), 'Abono - Parte de la quincena']);
    expect(lineas.last.abono, 20000);
    expect(lineas.last.balance, 30000);

    // Pagar todo: ya no debe y sale de la cuenta de los que deben.
    await vm.abonar(cl.ana, 30000, FormaPago.transferencia, null);
    final despues = b.c.read(clientesViewModelProvider).value!;
    expect(despues.resumen, 'Total fiado en la calle: RD\$ 300.00  ·  1 clientes deben');
    expect(despues.filas.first.cliente.id, cl.pedro.id);
  });

  test('el abono no puede pasar de lo que debe ni hacerse con la caja cerrada', () async {
    final b = await Banco.crear();
    final cl = await _Clientes.crear(b);
    final vm = await _abrir(b.c);

    await expectLater(vm.abonar(cl.ana, 60000, FormaPago.efectivo, null),
        throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Ana solo debe RD\$ 500.00.')));

    await CajaService(b.db).cerrar(b.dueno, const {});
    await expectLater(vm.abonar(cl.ana, 1000, FormaPago.efectivo, null), throwsA(isA<CajaCerrada>()));
  });

  test('el formulario guarda el cliente y solo el dueño da límite', () async {
    final b = await Banco.crear(comoCajero: true);
    b.c.listen(clienteFormularioViewModelProvider, (_, __) {});
    final vm = b.c.read(clienteFormularioViewModelProvider.notifier);

    final c = await vm.guardar(const DatosCliente(nombre: 'Rosa', cumpleanos: '5/8'));
    expect(c.cumpleanos, '05/08');
    expect(b.c.read(clienteFormularioViewModelProvider)!.id, c.id);

    await expectLater(vm.guardar(const DatosCliente(nombre: 'Rosa', cumpleanos: '31/02')),
        throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Cumpleaños: escriba día/mes, por ejemplo 15/08.')));
    await expectLater(vm.guardar(const DatosCliente(nombre: 'Luis', limiteCredito: 100000)), throwsA(isA<PermisoDenegado>()));
  });

  test('escoger cliente: por teléfono sale solo ese; "Nuevo cliente" pone el nombre o el teléfono', () async {
    final b = await Banco.crear();
    final cl = await _Clientes.crear(b);
    final p = clientePickerViewModelProvider('8095551111');
    b.c.listen(p, (_, __) {});
    final s = await b.c.read(p.future);
    expect(s.clientes.map((c) => c.id), [cl.ana.id]);
    expect(s.seleccionado!.id, cl.ana.id);
    expect(ClientePickerState.detalle(cl.pedro), 'Los Mina');
    expect(ClientePickerState.detalle(cl.ana), '809-555-1111');
    expect(ClientePickerState.titulo(cl.pedro), '★ Pedro');

    final vm = b.c.read(p.notifier);
    await vm.buscar('');
    final todos = b.c.read(p).value!;
    expect(todos.clientes.first.esFijo, isTrue); // los fijos primero
    expect(todos.escogido, 0);
    vm.escoger(99);
    expect(b.c.read(p).value!.escogido, todos.clientes.length - 1);

    final porTelefono = vm.datosNuevo(' 809-555-2222 ');
    expect(porTelefono.nombre, '');
    expect(porTelefono.telefono, '809-555-2222');
    expect(porTelefono.esFijo, isTrue);
    final porNombre = vm.datosNuevo('Doña Carmen');
    expect(porNombre.nombre, 'Doña Carmen');
    expect(porNombre.telefono, isNull);
  });

  test('recurrencia: 180 días y solo fijos de entrada, con el resumen de la 0.7', () async {
    final b = await Banco.crear();
    await _Clientes.crear(b);
    final p = recurrenciaViewModelProvider;
    b.c.listen(p, (_, __) {});
    final s = await b.c.read(p.future);
    expect(s.dias, 180);
    expect(s.soloFijos, isTrue);
    expect(s.lista.map((r) => r.cliente.nombre), containsAll(['Pedro', 'Carla']));
    expect(s.resumen, '1 clientes compraron  ·  0 no han vuelto  ·  0 perdidos  ·  Entre todos: RD\$ 300.00');

    await b.c.read(p.notifier).cambiarSoloFijos(false);
    expect(b.c.read(p).value!.resumen,
        '2 clientes compraron  ·  0 no han vuelto  ·  0 perdidos  ·  Entre todos: RD\$ 800.00');
    await b.c.read(p.notifier).cambiarPeriodo(30);
    expect(b.c.read(p).value!.dias, 30);
    expect(RecurrenciaState.periodoTexto(30), 'Últimos 30 días');
  });

  test('el ViewModel usa la sesión: sin sesión no abona', () async {
    final b = await Banco.crear();
    final cl = await _Clientes.crear(b);
    final vm = await _abrir(b.c);
    b.c.read(sesionProvider.notifier).salir();
    await expectLater(vm.abonar(cl.ana, 1000, FormaPago.efectivo, null), throwsA(isA<EmmaError>()));
  });

  pruebasDePantalla();
}

Widget _pantalla(ProviderContainer c, Widget hijo) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: temaCaja(),
        home: Scaffold(backgroundColor: Estilo.fondo, body: Padding(padding: const EdgeInsets.all(16), child: hijo)),
      ),
    );

/// Una letra real para medir: Archivo con su nombre y también como la letra
/// del sistema de macOS, que es la que usa el tema en escritorio.
Future<void> _cargarLetra() async {
  final datos = File('../../packages/emma_marca/assets/fuentes/Archivo.ttf').readAsBytesSync();
  for (final familia in const ['packages/emma_marca/Archivo', '.AppleSystemUIFont']) {
    await (FontLoader(familia)..addFont(Future.value(ByteData.sublistView(datos)))).load();
  }
}

/// Deja terminar lo que hace la base y redibuja.
Future<void> _esperar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pumpAndSettle();
}

void pruebasDePantalla() {
  setUpAll(_cargarLetra);

  testWidgets('la pantalla, el estado de cuenta y la recurrencia se dibujan', (tester) async {
    tester.view.physicalSize = const Size(1156, 736);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = (await tester.runAsync(Banco.crear))!;
    await tester.runAsync(() => _Clientes.crear(b));
    await tester.runAsync(() => _abrir(b.c));

    await tester.pumpWidget(_pantalla(b.c, const ClientesView()));
    await _esperar(tester);
    expect(find.text('Clientes y fiado'), findsOneWidget);
    expect(find.text('★ Pedro'), findsOneWidget);
    expect(find.text('Sin límite'), findsNWidgets(6));
    expect(find.text('Total fiado en la calle: RD\$ 800.00  ·  2 clientes deben'), findsOneWidget);

    await tester.tap(find.text('Recibir abono'));
    await _esperar(tester);
    expect(find.text('Seleccione el cliente.'), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Estado de cuenta'));
    await _esperar(tester);
    expect(find.text('Estado de cuenta: Ana'), findsOneWidget);
    expect(find.text('Debe: RD\$ 500.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recibir abono'));
    await _esperar(tester);
    expect(find.text('Abono de Ana'), findsOneWidget);
    expect(find.text('Debe RD\$ 500.00.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recurrencia de compra'));
    await _esperar(tester);
    expect(find.text('Recurrencia de compra de los clientes'), findsOneWidget);
    expect(find.text('Últimos 180 días'), findsOneWidget);
    expect(find.textContaining('1 clientes compraron'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Recurrencia de compra de los clientes'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('escoger cliente: Enter escoge el primero de la lista', (tester) async {
    final b = (await tester.runAsync(Banco.crear))!;
    await tester.runAsync(() => _Clientes.crear(b));
    Cliente? escogido;
    await tester.pumpWidget(_pantalla(
      b.c,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () async => escogido = await escogerCliente(context, ref, texto: 'Ped'),
          child: const Text('Abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('Abrir'));
    await _esperar(tester);
    expect(find.text('Escoger cliente'), findsOneWidget);
    expect(find.text('★ Pedro'), findsOneWidget);
    expect(find.text('Los Mina'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Escoger cliente'), findsNothing);
    expect(escogido?.nombre, 'Pedro');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
