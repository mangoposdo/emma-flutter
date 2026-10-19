import 'dart:io';

import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/features/compras/compras_view.dart';
import 'package:emma_caja/features/compras/compras_view_model.dart';
import 'package:emma_caja/features/compras/preparar_factura.dart';
import 'package:emma_caja/features/productos/editor_producto.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'ayudantes.dart';

/// Abre la pantalla: el ViewModel vive mientras alguien lo escucha.
Future<ComprasViewModel> abrir(Banco b) async {
  b.c.listen(comprasViewModelProvider, (_, __) {});
  final vm = b.c.read(comprasViewModelProvider.notifier);
  await vm.listo;
  return vm;
}

ComprasEstado estado(Banco b) => b.c.read(comprasViewModelProvider);

Future<int?> sinPrecio(LineaCompraVista _, String __) async => null;

Future<Producto?> nadaQueCrear(String _) async => null;

Future<bool> si(String _) async => true;

/// Escanear, Enter, cantidad, Enter, costo, Enter.
Future<void> agregar(ComprasViewModel vm, String codigo, String cantidad, String costo,
    {PedirPrecio? pedirPrecio}) async {
  expect(await vm.escanear(codigo, crear: nadaQueCrear), isNull);
  expect(vm.cantidad(cantidad), isNull);
  expect(await vm.costo(costo, pedirPrecio: pedirPrecio ?? sinPrecio), isNull);
}

/// La pantalla dentro de una ventana como la de la caja, sobre la base del banco.
Future<Banco> montar(WidgetTester t, {Size tamano = const Size(1156, 768)}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final b = (await t.runAsync(() => Banco.crear()))!;
  await t.pumpWidget(UncontrolledProviderScope(
    container: b.c,
    child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: ComprasView()))),
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

const casillaEscanear = 2;
const casillaCantidad = 3;
const casillaCosto = 4;

/// Cuál casilla de la pantalla tiene el foco: 0 suplidor, 1 factura, 2 escanear, 3 cantidad, 4 costo.
int? casillaConFoco(WidgetTester t) {
  final campos =
      t.widgetList<EditableText>(find.descendant(of: find.byType(ComprasView), matching: find.byType(EditableText)));
  final i = campos.toList().indexWhere((e) => e.focusNode.hasFocus);
  return i < 0 ? null : i;
}

String textoDe(WidgetTester t, int casilla) => t
    .widgetList<EditableText>(find.descendant(of: find.byType(ComprasView), matching: find.byType(EditableText)))
    .elementAt(casilla)
    .controller
    .text;

/// Escribe en la casilla que tiene el foco y pulsa Enter.
Future<void> escribirYEnter(WidgetTester t, String texto) async {
  t.testTextInput.enterText(texto);
  await t.pump();
  await t.testTextInput.receiveAction(TextInputAction.done);
  await esperar(t);
}

Directory carpetaTemporal() {
  final d = Directory.systemTemp.createTempSync('emma_compras_');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

Future<Producto> crearProducto(Banco b, String nombre, {String? codigo, int precio = 10000, int costo = 0}) => b.c
    .read(editorProductoProvider)
    .guardar(DatosProducto(codigo: codigo, nombre: nombre, precio: precio, costo: costo));

void main() {
  test('escanear, cantidad y costo con el ritmo de la 0.7', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);

    expect(await vm.escanear(Banco.refresco, crear: nadaQueCrear), isNull);
    var s = estado(b);
    expect(s.pendiente?.codigo, Banco.refresco);
    expect((s.seleccion, s.cantidadInicial, s.costoInicial), (1, '', '70'));
    expect(s.seleccionado,
        'Refresco Country Club 2 L   ·   Hay 24   ·   Costo anterior RD\$ 70.00   ·   Se vende a RD\$ 95.00');
    expect((s.rotuloCantidad, s.rotuloCosto), ('CANTIDAD', 'COSTO C/U'));

    expect(vm.cantidad(''), 'Escriba cuántos llegaron.');
    expect(vm.cantidad('0'), 'Escriba cuántos llegaron.');
    expect(vm.cantidad('1.5'), 'Refresco Country Club 2 L se cuenta por unidad; escriba un número entero.');
    expect(await vm.costo('68', pedirPrecio: sinPrecio), isNull, reason: 'sin cantidad no hace nada');
    expect(estado(b).lineas, isEmpty);
    expect(vm.cantidad('12'), isNull);
    expect(estado(b).cantidadPendiente, 12000);
    expect(await vm.costo('abc', pedirPrecio: sinPrecio), 'Escriba a cuánto le salió cada uno.');
    expect(estado(b).pendiente, isNotNull);

    final pedido = estado(b).pedidoCodigo;
    expect(await vm.costo('68', pedirPrecio: sinPrecio), isNull);
    s = estado(b);
    expect(s.pendiente, isNull);
    expect((s.pedidoCodigo, s.textoCodigo), (pedido + 1, ''),
        reason: 'la casilla de escanear se vacía y recupera el foco');
    expect(s.escogida, 0);
    final l = s.lineas.single;
    expect((l.cantidad, l.costo, l.total), (12000, 6800, 81600));
    expect(l.detalle, 'Había 24 · costo anterior 70.00');
    expect((l.cantidadTexto, l.precioTexto, l.ganancia, l.dejaGanancia), ('12', '95.00', '+28%', true));
    expect((s.total, s.resumen), (81600, '1 producto'));

    // El mismo producto al mismo costo se suma; a otro costo va en otra línea.
    await agregar(vm, Banco.refresco, '6', '68');
    expect(estado(b).lineas.single.cantidad, 18000);
    await agregar(vm, Banco.refresco, '2', '70');
    expect(estado(b).lineas.map((l) => (l.cantidad, l.costo)), [(18000, 6800), (2000, 7000)]);
    expect(estado(b).escogida, 1);

    // Por libra: otros rótulos y la cantidad lleva decimales.
    expect(await vm.escanear(Banco.arroz, crear: nadaQueCrear), isNull);
    s = estado(b);
    expect((s.rotuloCantidad, s.rotuloCosto, s.costoInicial), ('LIBRAS', 'COSTO LA LIBRA', '35'));
    expect(vm.cantidad('2.5'), isNull);
    expect(await vm.costo('35.50', pedirPrecio: sinPrecio), isNull);
    s = estado(b);
    expect(s.lineas.last.cantidadTexto, '2.5 lb');
    expect(s.lineas.last.total, 8875);
    expect(s.resumen, '3 productos');
    expect((s.rotuloCantidad, s.rotuloCosto), ('LIBRAS', 'COSTO LA LIBRA'), reason: 'se quedan como en la 0.7');
  });

  test('si el costo nuevo no deja ganancia pregunta el precio de venta', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final preguntas = <String>[];
    Future<int?> precio(int? respuesta, LineaCompraVista l, String nota) async {
      preguntas.add('${l.nombre}|$nota');
      return respuesta;
    }

    await agregar(vm, Banco.refresco, '1', '95', pedirPrecio: (l, n) => precio(11000, l, n));
    expect(
        preguntas, ['Refresco Country Club 2 L|Ahora le cuesta RD\$ 95.00 y se vende a RD\$ 95.00: no deja ganancia.']);
    var l = estado(b).lineas.single;
    expect((l.precioNuevo, l.precioTexto, l.ganancia), (11000, '110.00 (nuevo)', '+14%'));

    // El botón "Se vende a": volver al precio de siempre deja la línea sin precio nuevo.
    await vm.precio(0, pedirPrecio: (l, n) => precio(9500, l, n));
    expect(
        preguntas.last, 'Refresco Country Club 2 L|Costo RD\$ 95.00. El precio nuevo se guarda junto con la compra.');
    l = estado(b).lineas.single;
    expect((l.precioNuevo, l.precioTexto, l.ganancia, l.dejaGanancia), (null, '95.00', '+0%', false));

    // Cancelar deja el precio como está; con costo cero no se pregunta.
    await agregar(vm, Banco.refresco, '1', '100', pedirPrecio: (l, n) => precio(null, l, n));
    expect(estado(b).lineas.last.ganancia, '-5%');
    preguntas.clear();
    await agregar(vm, Banco.arroz, '1', '0', pedirPrecio: (l, n) => precio(1, l, n));
    expect(preguntas, isEmpty);
  });

  test('buscar por nombre, no encontrado y código de barras nuevo', () async {
    final b = await Banco.crear();
    await crearProducto(b, 'Refresco Rojo', codigo: '7469999');
    final vm = await abrir(b);

    expect(await vm.escanear('refresco', crear: nadaQueCrear), isNull);
    var s = estado(b);
    expect(s.pendiente, isNull);
    expect(s.busqueda?.map((p) => p.nombre), ['Refresco Country Club 2 L', 'Refresco Rojo']);
    final pedido = s.pedidoCodigo;
    vm.cerrarBusqueda();
    s = estado(b);
    expect(s.busqueda, isNull);
    expect((s.pedidoCodigo, s.textoCodigo), (pedido + 1, null), reason: 'recupera el foco sin borrar lo escrito');

    expect(await vm.escanear('refresco', crear: nadaQueCrear), isNull);
    vm.elegir(estado(b).busqueda![1]);
    expect(estado(b).pendiente?.nombre, 'Refresco Rojo');
    expect(estado(b).busqueda, isNull);
    vm.limpiarPendiente();
    expect((estado(b).pendiente, estado(b).textoCodigo), (null, ''));

    expect(await vm.escanear('  rojo ', crear: nadaQueCrear), isNull);
    expect(estado(b).pendiente?.nombre, 'Refresco Rojo', reason: 'un solo resultado se escoge solo');
    vm.limpiarPendiente();

    expect(await vm.escanear('xyz', crear: nadaQueCrear),
        'No se encontró "xyz". Si es nuevo, créelo en Productos o escanee su código.');
    expect(await vm.escanear('12345', crear: nadaQueCrear), startsWith('No se encontró "12345"'));

    final ofrecidos = <String>[];
    expect(
        await vm.escanear('1234567890', crear: (c) async {
          ofrecidos.add(c);
          return null;
        }),
        isNull);
    expect(ofrecidos, ['1234567890']);
    expect(estado(b).pendiente, isNull);

    expect(await vm.escanear('1234567890', crear: (c) => crearProducto(b, 'Galletas Club Social', codigo: c)), isNull);
    expect(estado(b).pendiente?.nombre, 'Galletas Club Social', reason: 'el producto creado sigue en la compra');
  });

  test('guardar de la caja: con la caja cerrada no deja; abierta, sale del cuadre', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    expect(await b.c.read(turnoAbiertoProvider.future), isNull);

    await agregar(vm, Banco.refresco, '12', '68');
    vm.escribirSuplidor('Distribuidora Ramos');
    vm.escribirFactura('A-77');
    expect(await vm.guardar(preguntar: si), 'La caja está cerrada. Ábrala o marque que la compra se pagó por fuera.');
    expect(estado(b).lineas, hasLength(1));
    expect(estado(b).guardando, isFalse);

    await b.abrirCaja();
    expect(await vm.guardar(preguntar: si), isNull);
    final s = estado(b);
    expect(s.aviso, 'Compra #1 guardada: RD\$ 816.00. Se sacó de la caja.');
    expect(s.lineas, isEmpty);
    expect((s.suplidor, s.factura, s.pago), ('', '', PagoCompra.deLaCaja));
    expect(s.suplidores, ['Distribuidora Ramos']);
    expect(tituloCompra(s.recientes.single), '#1 · Distribuidora Ramos');
    expect(detalleCompra(s.recientes.single), endsWith(' · de la caja · fact. A-77'));
    final refresco = await b.producto(Banco.refresco);
    expect((refresco.existencia, refresco.costo), (36000, 6800));
    expect(await b.contar('movimientos_caja'), 1);
    // La barra del menú se entera de la caja.
    expect(await b.c.read(turnoAbiertoProvider.future), isNotNull);
  });

  test('a crédito o por fuera no toca la caja; con un producto a medias no guarda', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);

    expect(await vm.guardar(preguntar: si), isNull, reason: 'sin productos no hace nada');
    expect(await b.contar('compras'), 0);

    vm.pago(PagoCompra.credito);
    await agregar(vm, Banco.refresco, '1', '95', pedirPrecio: (_, __) async => 11000);
    expect(await vm.escanear(Banco.arroz, crear: nadaQueCrear), isNull);
    expect(await vm.guardar(preguntar: si),
        'Termine el producto que está escribiendo (cantidad y costo con Enter) o pulse Esc.');
    vm.limpiarPendiente();
    expect(await vm.guardar(preguntar: si), isNull);
    expect(estado(b).aviso, 'Compra #1 guardada: RD\$ 95.00.');
    expect(estado(b).pago, PagoCompra.deLaCaja);
    expect(detalleCompra(estado(b).recientes.single), endsWith(' · a crédito'));
    expect((await b.producto(Banco.refresco)).precio, 11000, reason: 'el precio nuevo se guarda con la compra');

    vm.pago(PagoCompra.porFuera);
    await agregar(vm, Banco.arroz, '10', '36');
    expect(await vm.guardar(preguntar: si), isNull);
    expect(estado(b).aviso, 'Compra #2 guardada: RD\$ 360.00.');
    expect(tituloCompra(estado(b).recientes.first), '#2 · Sin suplidor');
    expect(await b.contar('movimientos_caja'), 0);
  });

  test('vaciar pregunta si hay productos; quitar una línea', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final preguntas = <String>[];
    Future<bool> responder(bool r, String p) async {
      preguntas.add(p);
      return r;
    }

    await vm.vaciar(preguntar: (p) => responder(true, p));
    expect(preguntas, isEmpty);

    await agregar(vm, Banco.refresco, '1', '70');
    await agregar(vm, Banco.arroz, '5', '35');
    vm.escogerLinea(0);
    vm.quitar(0);
    expect(estado(b).lineas.single.nombre, 'Arroz Selecto');
    expect(estado(b).escogida, isNull);

    expect(await vm.escanear(Banco.refresco, crear: nadaQueCrear), isNull);
    await vm.vaciar(preguntar: (p) => responder(false, p));
    expect(preguntas, ['¿Vaciar esta compra sin guardarla?']);
    expect(estado(b).pendiente, isNull, reason: 'el producto a medias se suelta aunque digan que no');
    expect(estado(b).lineas, hasLength(1));
    await vm.vaciar(preguntar: (p) => responder(true, p));
    expect(estado(b).lineas, isEmpty);
    expect(estado(b).total, 0);
  });

  test('factura leída: lo seguro entra, lo parecido se marca y lo demás queda por escoger', () async {
    final b = await Banco.crear();
    await b.db.into(b.db.suplidores).insert(SuplidoresCompanion.insert(nombre: 'Distribuidora Ramos'));
    final vm = await abrir(b);

    const factura = FacturaLeida(
      suplidor: 'DISTRIBUIDORA RAMOS',
      factura: 'F-100',
      lineas: [
        LineaFacturaLeida(descripcion: 'REFRESCO COUNTRY 2L', codigo: Banco.refresco, cantidad: 12000, costo: 6800),
        LineaFacturaLeida(descripcion: 'Arroz Selecto Grano Largo', cantidad: 25000, costo: 3600),
        LineaFacturaLeida(descripcion: 'HABICHUELAS ROJAS GOYA', cantidad: 6000, costo: 9000),
      ],
      total: 81600 + 90000 + 54000,
    );
    expect(await vm.llenarDeFactura(factura), isNull);
    var s = estado(b);
    expect((s.suplidor, s.factura), ('Distribuidora Ramos', 'F-100'));
    expect(s.aviso,
        'Factura leída: 2 de 3 productos ya están en la compra. Revise los 1 marcados en amarillo. Falta decir cuál producto es en 1.');
    expect(s.lineas.map((l) => (l.nombre, l.cantidad, l.costo, l.revisar)), [
      ('Refresco Country Club 2 L', 12000, 6800, false),
      ('Arroz Selecto', 25000, 3600, true),
    ]);
    expect(s.lineas[1].detalle,
        'En la factura: "Arroz Selecto Grano Largo" · revise que sea este producto (si no, quítelo y escoja otro)');
    expect(s.leida?.descripcion, 'HABICHUELAS ROJAS GOYA');
    expect(s.cuentaEmparejar, 'DE LA FACTURA · 1 DE 1 POR ESCOGER');
    expect(s.lineaEmparejar, 'HABICHUELAS ROJAS GOYA   ·   6.00 × RD\$ 90.00');
    expect((s.textoCodigo, s.busqueda), ('HABICHUELAS', null));

    // "Crear producto": el formulario sale con el nombre y el costo de la factura.
    final pedidos = <(String?, String, int)>[];
    await vm.crearDeFactura(crear: (codigo, nombre, costo) {
      pedidos.add((codigo, nombre, costo));
      return crearProducto(b, nombre, costo: costo, precio: 12000);
    });
    expect(pedidos, [(null, 'Habichuelas Rojas Goya', 9000)]);
    s = estado(b);
    expect(s.pendiente?.nombre, 'Habichuelas Rojas Goya');
    expect((s.cantidadInicial, s.costoInicial), ('6', '90'), reason: 'ya vienen de la factura');
    expect(vm.cantidad(s.cantidadInicial), isNull);
    expect(await vm.costo(s.costoInicial, pedirPrecio: sinPrecio), isNull);
    s = estado(b);
    expect(s.leida, isNull);
    expect(s.lineas.last.textoFactura, 'HABICHUELAS ROJAS GOYA');
    expect(s.total, factura.total);

    vm.pago(PagoCompra.credito);
    expect(await vm.guardar(preguntar: si), isNull);
    expect(await b.contar('alias_productos'), 3, reason: 'Emma recuerda cómo lo escribe este suplidor');

    // La próxima vez, el texto aprendido entra seguro.
    expect(
        await vm.llenarDeFactura(const FacturaLeida(
          suplidor: 'Distribuidora Ramos',
          lineas: [LineaFacturaLeida(descripcion: 'Arroz Selecto Grano Largo', cantidad: 1000, costo: 3600)],
        )),
        isNull);
    s = estado(b);
    expect(s.lineas.single.revisar, isFalse);
    expect(s.aviso, 'Factura leída: 1 de 1 productos ya están en la compra.');
  });

  test('factura leída: saltar, preguntar al guardar, escanear el renglón y avisos', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final preguntas = <String>[];
    Future<bool> no(String p) async {
      preguntas.add(p);
      return false;
    }

    expect(await vm.llenarDeFactura(const FacturaLeida(lineas: [], nota: 'Borrosa')),
        'No se encontraron productos en esa foto.\n\nBorrosa\n\nPruebe con una foto más clara, de frente y con buena luz.');
    expect(await vm.llenarDeFactura(const FacturaLeida(lineas: [])),
        'No se encontraron productos en esa foto.\n\nPruebe con una foto más clara, de frente y con buena luz.');

    vm.escribirSuplidor('El de siempre');
    vm.escribirFactura('X-1');
    expect(
        await vm.llenarDeFactura(const FacturaLeida(
          suplidor: 'Otro',
          factura: 'F-9',
          lineas: [
            LineaFacturaLeida(descripcion: 'REFRESCO ROJO 20OZ', cantidad: 24000, costo: 2500),
            LineaFacturaLeida(descripcion: 'Refresco Country', codigo: Banco.refresco, cantidad: 1500, costo: 7000),
            LineaFacturaLeida(descripcion: 'ARROZ SELECTO', cantidad: 10000, costo: 3500),
          ],
        )),
        isNull);
    var s = estado(b);
    expect((s.suplidor, s.factura), ('El de siempre', 'X-1'), reason: 'no se pisa lo que ya escribió');
    expect(s.aviso, 'Factura leída: 1 de 3 productos ya están en la compra. Falta decir cuál producto es en 2.');
    expect(s.leida?.descripcion, 'REFRESCO ROJO 20OZ');
    expect(s.cuentaEmparejar, 'DE LA FACTURA · 1 DE 2 POR ESCOGER');
    expect(s.textoCodigo, 'REFRESCO');
    expect(s.busqueda?.map((p) => p.codigo), [Banco.refresco], reason: 'de ayuda busca por la primera palabra');

    expect(await vm.guardar(preguntar: no), isNull);
    expect(preguntas, ['Todavía faltan 2 renglones de la factura por escoger. ¿Guardar la compra sin ellos?']);
    expect(await b.contar('compras'), 0);

    await vm.saltarDeFactura();
    s = estado(b);
    expect(s.leida?.descripcion, 'Refresco Country', reason: '1.5 de algo que va por unidad no entra solo');
    expect(s.cuentaEmparejar, 'DE LA FACTURA · 2 DE 2 POR ESCOGER');
    expect(s.busqueda?.map((p) => p.codigo), [Banco.refresco]);

    // Escanearlo a mano toma la cantidad y el costo del renglón.
    expect(await vm.escanear(Banco.refresco, crear: nadaQueCrear), isNull);
    s = estado(b);
    expect((s.cantidadInicial, s.costoInicial), ('1.5', '70'));
    expect(vm.cantidad('2'), isNull);
    expect(await vm.costo('70', pedirPrecio: sinPrecio), isNull);
    s = estado(b);
    expect(s.leida, isNull);
    expect(s.lineas.last.textoFactura, 'Refresco Country');

    // Si todo entra y la suma no cuadra con la factura, se avisa.
    await vm.vaciar(preguntar: si);
    expect(
        await vm.llenarDeFactura(const FacturaLeida(
          lineas: [LineaFacturaLeida(descripcion: 'x', codigo: Banco.refresco, cantidad: 12000, costo: 6800)],
          total: 90000,
          nota: 'Falta una página',
        )),
        isNull);
    expect(estado(b).aviso,
        'Factura leída: 1 de 1 productos ya están en la compra. Ojo: la factura dice RD\$ 900.00 y la suma da RD\$ 816.00. Nota: Falta una página');

    // Vaciar termina la factura.
    await vm.llenarDeFactura(
        const FacturaLeida(lineas: [LineaFacturaLeida(descripcion: 'Nada parecido', cantidad: 1000, costo: 100)]));
    expect(estado(b).leida, isNotNull);
    await vm.vaciar(preguntar: si);
    expect(estado(b).leida, isNull);
    expect(estado(b).porEmparejar, isEmpty);
    expect(estado(b).lineas, isEmpty);
  });

  test('leer factura: pregunta si ya hay productos y avisa lo que no sale', () async {
    final b = await Banco.crear();
    final vm = await abrir(b);
    final dir = carpetaTemporal();
    var escogidos = 0;
    Future<String?> escoger(String? ruta) async {
      escogidos++;
      return ruta;
    }

    await agregar(vm, Banco.refresco, '1', '70');
    expect(await vm.escanear(Banco.arroz, crear: nadaQueCrear), isNull);
    expect(await vm.leerFactura(preguntar: (_) async => false, escoger: () => escoger(null)), isNull);
    expect(escogidos, 0, reason: 'si dicen que no, ni se escoge el archivo');
    expect(estado(b).pendiente, isNull);

    expect(await vm.leerFactura(preguntar: si, escoger: () => escoger(null)), isNull);
    expect(escogidos, 1);

    final foto = File('${dir.path}/factura.png')..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 20)));
    expect(await vm.leerFactura(preguntar: si, escoger: () => escoger(foto.path)),
        'Para leer facturas, la caja tiene que estar conectada a la nube (Configuración > Conectar a la nube).');
    expect(estado(b).leyendo, isFalse);

    final mala = File('${dir.path}/factura.jpg')..writeAsStringSync('esto no es una foto');
    expect(await vm.leerFactura(preguntar: si, escoger: () => escoger(mala.path)),
        'No se pudo abrir ese archivo. Escoja una foto (JPG o PNG) o un PDF.');
    final pdf = File('${dir.path}/factura.pdf')..writeAsBytesSync(Uint8List(8 * 1024 * 1024 + 1));
    expect(await vm.leerFactura(preguntar: si, escoger: () => escoger(pdf.path)), 'El PDF pesa más de 8 MB.');
  });

  test('preparar la foto: tal cual si está bien; si no, derecha, achicada y en JPEG', () async {
    final dir = carpetaTemporal();
    final chica = img.encodePng(img.Image(width: 100, height: 50));
    File('${dir.path}/chica.png').writeAsBytesSync(chica);
    final (bytes, tipo) = await prepararFactura('${dir.path}/chica.png');
    expect(bytes, chica);
    expect(tipo, 'image/png');

    File('${dir.path}/grande.png').writeAsBytesSync(img.encodePng(img.Image(width: 3000, height: 1500)));
    final (achicada, tipoAchicada) = await prepararFactura('${dir.path}/grande.png');
    expect(tipoAchicada, 'image/jpeg');
    final a = img.decodeImage(achicada)!;
    expect((a.width, a.height), (ladoMaximoFactura, 1200));

    final deLado = img.Image(width: 100, height: 50);
    deLado.exif.imageIfd.orientation = 6;
    File('${dir.path}/de_lado.jpg').writeAsBytesSync(img.encodeJpg(deLado));
    final (derecha, _) = await prepararFactura('${dir.path}/de_lado.jpg');
    final d = img.decodeImage(derecha)!;
    expect((d.width, d.height), (50, 100));
    expect(img.decodeJpgExif(derecha)?.imageIfd.orientation, isNull);

    File('${dir.path}/f.PDF').writeAsBytesSync([1, 2, 3]);
    final (pdf, tipoPdf) = await prepararFactura('${dir.path}/f.PDF');
    expect(pdf, [1, 2, 3]);
    expect(tipoPdf, 'application/pdf');
    await expectLater(prepararFactura('${dir.path}/no-existe.jpg'), throwsA(isA<DatoInvalido>()));
  });

  test('textos de apoyo', () {
    expect([montoCorto(7000), montoCorto(7050), montoCorto(7025), montoCorto(5)], ['70', '70.5', '70.25', '0.05']);
    expect([cantidadCorta(1429), cantidadCorta(24000), cantidadCorta(-500)], ['1.43', '24', '-0.5']);
    expect(enTitulo(' ARROZ SELECTO 25LB '), 'Arroz Selecto 25Lb');
    expect(enTitulo("COCA-COLA D'LEON 2.5LT"), "Coca-Cola D'leon 2.5Lt");
    expect(enTitulo('habichuelas ñame'), 'Habichuelas Ñame');
  });

  group('pantalla', () {
    for (final tamano in const [Size(1156, 768), Size(1710, 1080)]) {
      testWidgets('el ritmo del teclado: escanear, cantidad, costo y Esc vacía (${tamano.width.toInt()} px)',
          (t) async {
        final b = await montar(t, tamano: tamano);
        expect(casillaConFoco(t), casillaEscanear);
        expect(find.text('Escanee o escriba lo que llegó'), findsOneWidget);

        await escribirYEnter(t, Banco.refresco);
        expect(casillaConFoco(t), casillaCantidad);
        expect(textoDe(t, casillaEscanear), 'Refresco Country Club 2 L');
        expect(textoDe(t, casillaCosto), '70', reason: 'el costo anterior ya está puesto');
        expect(find.textContaining('Hay 24   ·   Costo anterior RD\$ 70.00'), findsOneWidget);

        await escribirYEnter(t, '12');
        expect(casillaConFoco(t), casillaCosto);
        await t.testTextInput.receiveAction(TextInputAction.done);
        await esperar(t);
        expect(casillaConFoco(t), casillaEscanear);
        expect(textoDe(t, casillaEscanear), '');
        expect(find.text('RD\$ 840.00'), findsOneWidget);
        expect(find.text('1 producto'), findsOneWidget);
        expect(find.text('+26%'), findsOneWidget);

        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await esperar(t);
        expect(find.text('¿Vaciar esta compra sin guardarla?'), findsOneWidget);
        await t.tap(find.text('Sí'));
        await esperar(t);
        expect(b.c.read(comprasViewModelProvider).lineas, isEmpty);
        expect(casillaConFoco(t), casillaEscanear);
      });
    }

    testWidgets('búsqueda con flechas, precio sin ganancia, Supr, factura leída y F10', (t) async {
      final b = await montar(t);
      await t.runAsync(() => crearProducto(b, 'Refresco Rojo', precio: 3000));

      // Varios resultados: flecha abajo entra a la lista y Enter escoge.
      await escribirYEnter(t, 'refresco');
      expect(find.text('Hay 24'), findsOneWidget);
      expect(find.text('Costo RD\$ 70.00'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await esperar(t);
      expect(find.text('Costo RD\$ 70.00'), findsNothing);
      expect(casillaConFoco(t), casillaCantidad);
      expect(b.c.read(comprasViewModelProvider).pendiente?.nombre, 'Refresco Rojo');

      // Cuesta lo mismo que se vende: pregunta el precio nuevo.
      await escribirYEnter(t, '2');
      await escribirYEnter(t, '30');
      expect(find.text('Precio de venta: Refresco Rojo'), findsOneWidget);
      expect(find.text('Ahora le cuesta RD\$ 30.00 y se vende a RD\$ 30.00: no deja ganancia.'), findsOneWidget);
      t.testTextInput.enterText('40');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await esperar(t);
      expect(find.text('40.00 (nuevo)'), findsOneWidget);
      expect(find.text('+25%'), findsOneWidget);
      expect(casillaConFoco(t), casillaEscanear);

      // Tocar la línea y Supr la quita; el foco vuelve a escanear.
      await t.tap(find.text('Refresco Rojo'));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await esperar(t);
      expect(b.c.read(comprasViewModelProvider).lineas, isEmpty);
      expect(find.textContaining('O pulse "Leer factura" y escoja la foto'), findsOneWidget);
      expect(casillaConFoco(t), casillaEscanear);

      // Factura leída: el panel amarillo y la línea por revisar.
      await t.runAsync(() => b.c.read(comprasViewModelProvider.notifier).llenarDeFactura(const FacturaLeida(lineas: [
            LineaFacturaLeida(descripcion: 'Arroz Selecto Grano Largo', cantidad: 25000, costo: 3600),
            LineaFacturaLeida(descripcion: 'HABICHUELAS ROJAS GOYA', cantidad: 6000, costo: 9000),
            LineaFacturaLeida(descripcion: 'REFRESCO VERDE 20OZ', cantidad: 6000, costo: 9000),
          ])));
      await esperar(t);
      expect(find.text('DE LA FACTURA · 1 DE 2 POR ESCOGER'), findsOneWidget);
      expect(find.text('HABICHUELAS ROJAS GOYA   ·   6.00 × RD\$ 90.00'), findsOneWidget);
      expect(find.textContaining('revise que sea este producto'), findsOneWidget);
      expect(casillaConFoco(t), casillaEscanear);
      expect(textoDe(t, casillaEscanear), 'HABICHUELAS');
      await t.tap(find.text('Saltar'));
      await esperar(t);
      expect(find.text('DE LA FACTURA · 2 DE 2 POR ESCOGER'), findsOneWidget);
      expect(find.text('Costo RD\$ 70.00'), findsOneWidget, reason: 'de ayuda busca REFRESCO');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await esperar(t);
      expect(find.text('Costo RD\$ 70.00'), findsNothing);

      // F10 con un renglón por escoger pregunta; a crédito se guarda.
      await t.tap(find.text('A crédito'));
      await t.pump();
      expect(casillaConFoco(t), casillaEscanear, reason: 'los botones no se roban el foco');
      await t.sendKeyEvent(LogicalKeyboardKey.f10);
      await esperar(t);
      expect(find.text('Todavía faltan 1 renglones de la factura por escoger. ¿Guardar la compra sin ellos?'),
          findsOneWidget);
      await t.tap(find.text('Sí'));
      await esperar(t);
      expect(find.text('Compra #1 guardada: RD\$ 900.00.'), findsOneWidget);
      expect(find.text('DE LA FACTURA · 2 DE 2 POR ESCOGER'), findsNothing);

      // Doble clic en la compra reciente muestra sus productos.
      await t.tap(find.text('#1 · Sin suplidor'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text('#1 · Sin suplidor'));
      await esperar(t);
      expect(find.text('#1 · Sin suplidor · RD\$ 900.00'), findsOneWidget);
      expect(find.text('Arroz Selecto'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await esperar(t);
      expect(find.text('#1 · Sin suplidor · RD\$ 900.00'), findsNothing);
    });
  });
}
