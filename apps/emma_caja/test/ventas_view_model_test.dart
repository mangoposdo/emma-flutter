import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/features/ventas/delivery_view_model.dart';
import 'package:emma_caja/features/ventas/ventas_state.dart';
import 'package:emma_caja/features/ventas/ventas_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

void main() {
  late Banco b;

  Future<VentasViewModel> abrir() async {
    b.c.listen(ventasViewModelProvider, (_, __) {});
    await b.c.read(ventasViewModelProvider.future);
    return b.c.read(ventasViewModelProvider.notifier);
  }

  VentasState s() => b.c.read(ventasViewModelProvider).requireValue;

  setUp(() async => b = await Banco.crear());
  tearDown(() => b.db.close());

  group('escanear', () {
    test('escanear agrega 1 al instante; otra vez suma a la misma línea', () async {
      final vm = await abrir();
      expect(await vm.entrarCodigo(Banco.refresco), isA<Listo>());
      expect(await vm.entrarCodigo(Banco.refresco), isA<Listo>());
      expect(s().lineas.single.cantidad, 2000);
      expect(s().total, 19000);
      expect(s().articulosTexto, '1 producto · 2 artículos');
    });

    test('3* y el código agrega 3', () async {
      final vm = await abrir();
      await vm.entrarCodigo('3*${Banco.refresco}');
      expect(s().lineas.single.cantidad, 3000);
    });

    test('por libra pasa a la cantidad: libras o \$50 exactos', () async {
      final vm = await abrir();
      expect(await vm.entrarCodigo(Banco.arroz), isA<PedirLibras>());
      expect(s().pendiente?.codigo, Banco.arroz);
      expect(await vm.entrarCantidad('1.5'), isNull);
      expect(s().lineas.single.total, 6750);
      expect(s().pendiente, isNull);

      await vm.entrarCodigo(Banco.arroz);
      expect(await vm.entrarCantidad(r'$50'), isNull);
      expect(s().lineas.last.total, 5000);
      expect(s().lineas.last.cantidad, 1111);
      expect(await vm.entrarCodigo(Banco.arroz), isA<PedirLibras>());
      expect(await vm.entrarCantidad('cero'), 'Escriba una cantidad mayor que cero.');
    });

    test(r'$50 en el código es una venta suelta', () async {
      final vm = await abrir();
      await vm.entrarCodigo(r'$50');
      expect(s().lineas.single.producto.codigo, codigoVarios);
      expect(s().lineas.single.total, 5000);
    });

    test('por nombre: un resultado se agrega; varios muestran la lista', () async {
      final vm = await abrir();
      expect(await vm.entrarCodigo('country'), isA<Listo>());
      expect(s().lineas, hasLength(1));
      expect(await vm.entrarCodigo('r'), isA<EscogerDeLista>());
      expect(s().busqueda.length, 2);
      vm.moverMarca(1);
      expect(s().marcado, 1);
    });

    test('desde la primera letra sale la lista, sin ninguno marcado', () async {
      final vm = await abrir();
      await vm.sugerir('a');
      expect(s().busqueda.map((p) => p.nombre), ['Arroz Selecto']);
      expect(s().marcado, -1);
      await vm.sugerir('r');
      expect(s().busqueda.map((p) => p.nombre), ['Refresco Country Club 2 L', 'Arroz Selecto']);
      vm.moverMarca(1);
      expect(s().marcado, 0, reason: 'la primera flecha marca el primero');
      await vm.sugerir('re');
      expect(s().marcado, -1, reason: 'al seguir escribiendo se desmarca');
    });

    test('3*arr busca arr; borrar o \$50 cierran la lista', () async {
      final vm = await abrir();
      await vm.sugerir('3*arr');
      expect(s().busqueda.single.codigo, Banco.arroz);
      await vm.sugerir('');
      expect(s().busqueda, isEmpty);
      await vm.sugerir('r');
      await vm.sugerir(r'$5');
      expect(s().busqueda, isEmpty);
    });

    test('el lector escanea y da Enter antes de que salga la lista: no sale', () async {
      final vm = await abrir();
      final escribiendo = vm.sugerir('7460');
      expect(await vm.entrarCodigo(Banco.refresco), isA<Listo>());
      await escribiendo;
      expect(s().busqueda, isEmpty);
      expect(s().lineas.single.producto.codigo, Banco.refresco);
    });

    test('un código que no existe: el dueño puede crearlo, el cajero no', () async {
      final vm = await abrir();
      final r = await vm.entrarCodigo('7460999');
      expect(r, isA<NoEncontrado>().having((x) => x.ofrecerCrear, 'ofrecerCrear', isTrue));
      expect((await vm.entrarCodigo('xyz') as NoEncontrado).mensaje, 'No se encontró "xyz".');

      final cajero = await Banco.crear(comoCajero: true);
      cajero.c.listen(ventasViewModelProvider, (_, __) {});
      await cajero.c.read(ventasViewModelProvider.future);
      final r2 = await cajero.c.read(ventasViewModelProvider.notifier).entrarCodigo('7460999');
      expect(r2, isA<NoEncontrado>().having((x) => x.ofrecerCrear, 'ofrecerCrear', isFalse));
      await cajero.db.close();
    });

    test('− y + van de uno en uno; en cero se quita', () async {
      final vm = await abrir();
      await vm.entrarCodigo('2*${Banco.refresco}');
      await vm.paso(0, 1);
      expect(s().lineas.single.cantidad, 3000);
      await vm.paso(0, -1);
      await vm.paso(0, -1);
      await vm.paso(0, -1);
      expect(s().lineas, isEmpty);
    });
  });

  group('pedidos abiertos', () {
    test('cada cambio se guarda; F6 deja el pedido y abre otro; se vuelve con su pestaña', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      final primero = s().ticketId!;
      expect((await b.c.read(ticketServiceProvider).abiertos()).single.id, primero);

      await vm.nuevoPedido();
      expect(s().ticketId, isNull);
      expect(s().lineas, isEmpty);
      expect(s().pedidos.map((p) => (p.titulo, p.actual)), [('Pedido 1', false), ('Mostrador', true)]);

      vm.escribirCliente('Doña Rosa');
      await vm.clienteSalio();
      expect(s().pedidos.map((p) => p.titulo), ['Pedido 1', 'Doña Rosa']);

      await vm.cambiarAPedido(primero);
      expect(s().lineas.single.producto.codigo, Banco.refresco);
      expect(s().pedidos.first.detalle, r'RD$95');
    });

    test('al entrar sigue con el último pedido que se tocó', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      await b.c.read(ticketServiceProvider).guardar(b.dueno, lineas: const [], nombreCliente: 'Otro');
      b.c.invalidate(ventasViewModelProvider);
      await b.c.read(ventasViewModelProvider.future);
      expect(s().clienteTexto, 'Otro');
    });

    test('cancelar borra el pedido', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      await vm.cancelarPedido();
      expect(await b.c.read(ticketServiceProvider).abiertos(), isEmpty);
      expect(s().lineas, isEmpty);
    });
  });

  group('cobrar', () {
    test('en efectivo: guarda la venta, borra el pedido y deja la devuelta', () async {
      await b.abrirCaja();
      final vm = await abrir();
      await vm.entrarCodigo('2*${Banco.refresco}');
      expect(vm.billete(0), '190');
      vm.escribirRecibido('500');
      expect(s().devuelta, (etiqueta: 'Devuelta', monto: r'RD$ 310.00', falta: false));
      expect(s().billeteMarcado(500), isTrue);

      final r = await vm.cobrar();
      expect(r.aviso, isNull);
      expect(await b.contar('ventas'), 1);
      expect(await b.c.read(ticketServiceProvider).abiertos(), isEmpty);
      expect(s().lineas, isEmpty);
      expect(s().devuelta.etiqueta, 'Devuelta (venta anterior)');
      expect(s().devuelta.monto, r'RD$ 310.00');

      // Sin impresora no queda ticket pendiente.
      expect(await vm.despuesDeVenta(r.ventaId!), isNull);
      expect(s().ticketsPendientes, 0);
      expect(s().ultimaVentaTexto, r'Última venta: #1 · RD$ 190.00 · Efectivo ·');

      // El siguiente producto quita la devuelta de la venta anterior.
      await vm.entrarCodigo(Banco.refresco);
      expect(s().devueltaAnterior, isNull);
    });

    test('si lo que paga no alcanza no cobra', () async {
      await b.abrirCaja();
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      vm.escribirRecibido('50');
      expect(s().devuelta, (etiqueta: 'Faltan', monto: r'RD$ 45.00', falta: true));
      expect((await vm.cobrar()).aviso, 'Con lo que paga no alcanza.');
      expect(await b.contar('ventas'), 0);
    });

    test('con la caja cerrada avisa y el pedido sigue abierto', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      final r = await vm.cobrar();
      expect(r.aviso, const CajaCerrada().mensaje);
      expect(s().lineas, hasLength(1));
      expect(await b.c.read(ticketServiceProvider).abiertos(), hasLength(1));
    });

    test('fiado: pide el cliente y suma a su cuenta', () async {
      await b.abrirCaja();
      final rosa = await b.c.read(fiadoServiceProvider).guardarCliente(b.dueno, const DatosCliente(nombre: 'Rosa'));
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      await vm.elegirForma(FormaPago.fiado);
      expect(vm.faltaClienteFiado, isTrue);
      vm.escribirCliente('rosa');
      expect(await vm.entrarCliente(), isEmpty); // uno solo: se liga
      expect(s().fiadoNombre, 'Rosa');
      expect(s().fiadoCredito, contains('Sin límite de crédito'));
      expect((await vm.cobrar()).aviso, isNull);
      expect(await b.c.read(fiadoServiceProvider).balance(rosa.id), 9500);
    });

    test('el descuento no pasa el total y se quita si la venta baja', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      expect(vm.fijarDescuento(10000), 'El descuento no puede ser mayor que el total.');
      expect(vm.fijarDescuento(1500), isNull);
      expect(s().total, 8000);
      await vm.quitar();
      expect(s().descuento, 0);
    });
  });

  group('delivery', () {
    test('se despacha, sale de los pedidos y se cobra al volver con el envío', () async {
      await b.abrirCaja();
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      final id = await vm.pedidoParaDelivery();

      b.c.listen(deliveryViewModelProvider(id), (_, __) {});
      await b.c.read(deliveryViewModelProvider(id).future);
      final d = b.c.read(deliveryViewModelProvider(id).notifier);
      final r = await d.guardar(
        nombre: 'Carmen',
        telefono: '809-555-1234',
        direccion: 'Calle 5',
        pagaCon: '200',
        envio: '50',
        repartidor: 'Pedro',
        despachar: true,
      );
      expect(r.listo, isTrue);
      await vm.recargar(pedidoNuevo: true);
      expect(s().enLaCalle, 1);
      expect(s().pedidos.map((p) => p.titulo), ['Mostrador']);

      final calle = await b.c.read(deliveryServiceProvider).enLaCalle();
      expect(calle.single.total, 14500);
      expect(calle.single.cambio, 5500);
    });

    test('con poco dinero no se despacha', () async {
      final vm = await abrir();
      await vm.entrarCodigo(Banco.refresco);
      final id = await vm.pedidoParaDelivery();
      b.c.listen(deliveryViewModelProvider(id), (_, __) {});
      await b.c.read(deliveryViewModelProvider(id).future);
      final r = await b.c.read(deliveryViewModelProvider(id).notifier).guardar(
            nombre: '', telefono: '', direccion: 'Aquí', pagaCon: '100', envio: '50', repartidor: '', despachar: true);
      expect(r, (listo: false, aviso: r'Con RD$ 100.00 no alcanza: el pedido es RD$ 145.00.'));
    });
  });
}
