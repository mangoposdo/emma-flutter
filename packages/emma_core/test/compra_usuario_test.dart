import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late Sesion dueno;

  setUp(() async {
    db = baseDePrueba();
    dueno = await sesionDueno(db);
  });

  tearDown(() => db.close());

  group('compras', () {
    late CompraService compras;
    setUp(() => compras = CompraService(db));

    test('de la caja: sube existencia, deja el costo nuevo y sale del cuadre', () async {
      final arroz = await crearProducto(db, codigo: '1', nombre: 'Arroz', precio: 5000, costo: 4000, existencia: 10000);
      final aceite = await crearProducto(db, codigo: '2', nombre: 'Aceite', precio: 12000, costo: 9500, existencia: 2000);
      final caja = CajaService(db);
      await caja.abrir(dueno, 500000);

      final c = await compras.registrar(dueno, SolicitudCompra(
        suplidor: 'Distribuidora Ramos',
        factura: 'A-1203',
        lineas: [
          LineaCompra(productoId: arroz, cantidad: 25000, costo: 4200),
          LineaCompra(productoId: aceite, cantidad: 12000, costo: 10000, precio: 13000),
        ],
      ));
      expect(c.total, 25 * 4200 + 12 * 10000);
      final a = await producto(db, arroz);
      expect((a.existencia, a.costo, a.precio), (35000, 4200, 5000));
      final b = await producto(db, aceite);
      expect((b.existencia, b.precio), (14000, 13000));
      final movs = await ProductoService(db).movimientos(arroz);
      expect(movs.first.referencia, 'Compra #${c.id}');

      final r = await caja.resumen((await caja.turnoAbierto())!.id);
      expect(r.salidas, c.total);
      expect(r.efectivoEsperado, 500000 - c.total);
      final mov = (await caja.movimientos(r.turno.id)).single;
      expect(mov.concepto, 'Compra #${c.id} a Distribuidora Ramos, factura A-1203');

      expect((await compras.suplidores()).single.nombre, 'Distribuidora Ramos');
      final reciente = (await compras.recientes()).single;
      expect(reciente.lineas, hasLength(2));
      expect(reciente.suplidor, 'Distribuidora Ramos');
    });

    test('a crédito no toca la caja; reglas', () async {
      final pan = await crearProducto(db, codigo: '3', nombre: 'Pan', precio: 500, costo: 300);
      await expectLater(
        compras.registrar(dueno, SolicitudCompra(lineas: [LineaCompra(productoId: pan, cantidad: 10000, costo: 300)])),
        throwsA(isA<CajaCerrada>()),
      );
      await expectLater(
        compras.registrar(dueno, const SolicitudCompra(pago: PagoCompra.credito, lineas: [])),
        throwsA(isA<DatoInvalido>()),
      );
      await expectLater(
        compras.registrar(dueno, SolicitudCompra(pago: PagoCompra.credito, lineas: [LineaCompra(productoId: pan, cantidad: 1500, costo: 300)])),
        throwsA(isA<DatoInvalido>()),
      );
      await compras.registrar(dueno, SolicitudCompra(pago: PagoCompra.credito, lineas: [LineaCompra(productoId: pan, cantidad: 100000, costo: 350)]));
      expect((await producto(db, pan)).existencia, 100000);
      expect(await compras.suplidores(), isEmpty);
      expect(await contar(db, 'movimientos_caja'), 0);

      final maria = await crearCajero(db);
      await expectLater(
        compras.registrar(maria, SolicitudCompra(pago: PagoCompra.porFuera, lineas: [LineaCompra(productoId: pan, cantidad: 1000, costo: 1)])),
        throwsA(isA<PermisoDenegado>()),
      );
    });
  });

  group('usuarios', () {
    late UsuarioService usuarios;
    setUp(() => usuarios = UsuarioService(db));

    test('PIN incorrecto no entra y queda en la bitácora; el correcto abre la sesión', () async {
      expect(await usuarios.iniciarSesion('admin', '0000'), isNull);
      final s = await usuarios.iniciarSesion(' ADMIN ', '1234');
      expect(s?.esDueno, isTrue);
      expect(s?.nombre, 'Dueño');
      final b = await usuarios.bitacora(s!);
      expect(b.map((x) => x.entrada.accion), ['Inicio de sesión', 'Intento de entrada fallido']);
      expect(b.first.usuario, 'Dueño');
      expect(await usuarios.usaPinDeFabrica(), isTrue);
    });

    test('siempre queda un dueño activo', () async {
      final yo = (await db.select(db.usuarios).getSingle());
      await expectLater(
        usuarios.guardar(dueno, DatosUsuario(id: yo.id, nombre: 'Dueño', login: 'admin', rol: Rol.cajero)),
        throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Debe quedar al menos un dueño activo.')),
      );
      await usuarios.guardar(dueno, const DatosUsuario(nombre: 'Otra dueña', login: 'ana', rol: Rol.dueno), pinNuevo: '9999');
      await usuarios.guardar(dueno, DatosUsuario(id: yo.id, nombre: 'Dueño', login: 'admin', rol: Rol.cajero));
    });

    test('reglas: login único, PIN de 4 o más, nuevo con PIN; solo el dueño', () async {
      await usuarios.guardar(dueno, const DatosUsuario(nombre: 'María', login: 'Maria'), pinNuevo: '4321');
      await expectLater(
        usuarios.guardar(dueno, const DatosUsuario(nombre: 'Otra', login: 'maria'), pinNuevo: '1111'),
        throwsA(isA<DatoInvalido>()),
      );
      await expectLater(usuarios.guardar(dueno, const DatosUsuario(nombre: 'X', login: 'x'), pinNuevo: '12'), throwsA(isA<DatoInvalido>()));
      await expectLater(usuarios.guardar(dueno, const DatosUsuario(nombre: 'X', login: 'x')), throwsA(isA<DatoInvalido>()));
      final maria = (await usuarios.iniciarSesion('maria', '4321'))!;
      expect(maria.esDueno, isFalse);
      await expectLater(usuarios.guardar(maria, const DatosUsuario(nombre: 'Y', login: 'y'), pinNuevo: '1234'), throwsA(isA<PermisoDenegado>()));
      await expectLater(usuarios.bitacora(maria), throwsA(isA<PermisoDenegado>()));
    });

    test('cambiar mi PIN pide el actual', () async {
      await expectLater(usuarios.cambiarMiPin(dueno, '0000', '5678'), throwsA(isA<DatoInvalido>()));
      await usuarios.cambiarMiPin(dueno, '1234', '5678');
      expect(await usuarios.usaPinDeFabrica(), isFalse);
      expect(await usuarios.iniciarSesion('admin', '5678'), isNotNull);
    });

    test('el PIN guardado por la 0.6/0.7 sigue sirviendo', () async {
      // Pin.Hash("1234") de la 0.7 con 1000 vueltas.
      final hasher = PinHasher(vueltas: 1000);
      final propio = await hasher.hash('1234');
      final partes = propio.split(r'$');
      final formatoViejo = '${partes[1]}.${partes[2]}.${partes[3]}';
      expect(await hasher.verificar('1234', formatoViejo), isTrue);
      expect(await hasher.verificar('1235', formatoViejo), isFalse);
      expect(await hasher.verificar('1234', 'basura.x.y'), isFalse);
    });
  });
}
