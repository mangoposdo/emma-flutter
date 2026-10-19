import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late CajaService caja;
  late Sesion dueno;

  setUp(() async {
    db = baseDePrueba();
    caja = CajaService(db);
    dueno = await sesionDueno(db);
  });

  tearDown(() => db.close());

  group('abrir caja', () {
    test('la base nueva empieza con la caja cerrada', () async {
      expect(await caja.turnoAbierto(), isNull);
    });

    test('abre el turno con el fondo, la hora y el usuario; anota en la bitácora', () async {
      final t = await caja.abrir(dueno, 150000);

      expect(t.fondoInicial, 150000);
      expect(t.apertura, horaPrueba);
      expect(t.usuarioId, dueno.usuarioId);
      expect(t.cierre, isNull);
      expect((await caja.turnoAbierto())?.id, t.id);

      final b = await db.select(db.bitacora).getSingle();
      expect(b.accion, 'Abrir caja');
      expect(b.detalle, 'Turno #${t.id} con fondo de RD\$ 1,500.00.');
    });

    test('se puede abrir con fondo cero', () async {
      final t = await caja.abrir(dueno, 0);
      expect(t.fondoInicial, 0);
    });

    test('el cajero también puede abrir', () async {
      final maria = await crearCajero(db);
      final t = await caja.abrir(maria, 100000);
      expect(t.usuarioId, maria.usuarioId);
    });

    test('no deja abrir dos veces', () async {
      await caja.abrir(dueno, 100000);
      await expectLater(
        caja.abrir(dueno, 50000),
        throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'La caja ya está abierta.')),
      );
      expect(await contar(db, 'turnos_caja'), 1);
    });

    test('no deja un fondo negativo y no guarda nada', () async {
      await expectLater(caja.abrir(dueno, -1), throwsA(isA<DatoInvalido>()));
      expect(await contar(db, 'turnos_caja'), 0);
      expect(await contar(db, 'bitacora'), 0);
    });

    test('con la caja abierta ya se puede cobrar', () async {
      await caja.abrir(dueno, 100000);
      final r = await VentaService(db).cobrar(
        dueno,
        SolicitudCobro(lineas: [LineaCobro.varios(2500)], formaPago: FormaPago.efectivo),
      );
      expect(r.total, 2500);
    });
  });
}
