import 'dart:convert';
import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'ayudantes.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

class _EnviadorFalso implements EnviadorNube {
  var falla = false;
  final recibidos = <EventoSalida>[];

  @override
  Future<void> enviar(String instalacionId, List<EventoSalida> eventos) async {
    if (falla) throw const EmmaError('Sin internet');
    recibidos.addAll(eventos);
  }
}

void main() {
  group('respaldos', () {
    late Directory carpeta;
    late EmmaDatabase db;
    var ahora = horaPrueba;

    setUp(() async {
      carpeta = await Directory.systemTemp.createTemp('emma_respaldo_');
      ahora = horaPrueba;
      db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000), reloj: () => ahora);
    });

    tearDown(() async {
      await db.close();
      if (carpeta.existsSync()) await carpeta.delete(recursive: true);
    });

    test('crea una copia sana y se puede restaurar', () async {
      final r = RespaldoService(db, carpeta);
      await crearCliente(db, nombre: 'Rosa');
      final copia = await r.respaldar();
      expect(p.basename(copia), 'emma_2026-10-18_103005.db');
      expect(RespaldoService.problemaDeLaBase(File(copia)), isNull);

      await crearCliente(db, nombre: 'Luis');
      final dueno = await sesionDueno(db);
      final seguridad = await r.prepararRestauracion(dueno, copia);
      expect(File(seguridad).existsSync(), isTrue);
      await db.close();
      await RespaldoService.ponerRespaldo(carpeta, copia);
      db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      expect(await contar(db, 'clientes'), 1);
    });

    test('guarda los 20 más nuevos y uno por día del último mes', () {
      final nombres = <String>[];
      for (var d = 0; d < 40; d++) {
        final f = horaPrueba.subtract(Duration(days: d));
        String dos(int n) => n.toString().padLeft(2, '0');
        for (final h in const ['180000', '090000']) {
          nombres.add('emma_${f.year}-${dos(f.month)}-${dos(f.day)}_$h.db');
        }
      }
      final sobran = RespaldoService.sobrantes(nombres, horaPrueba);
      final quedan = nombres.where((n) => !sobran.contains(n)).toList();
      // 20 recientes (10 días con 2) + el último de cada uno de los otros 21 días del mes.
      expect(quedan, hasLength(20 + 21));
      expect(quedan, contains(nombres.first));
      expect(sobran, contains(nombres.last));
    });

    test('detecta una base dañada y encuentra el último respaldo sano', () async {
      final r = RespaldoService(db, carpeta);
      final sano = await r.respaldar();
      await db.close();
      final base = File(p.join(carpeta.path, nombreArchivoBase));
      final bytes = await base.readAsBytes();
      // Se daña la página 2 en adelante.
      for (var i = 4096; i < bytes.length && i < 4096 * 3; i++) {
        bytes[i] = 0x5A;
      }
      for (final extra in const ['-wal', '-shm']) {
        final f = File('${base.path}$extra');
        if (f.existsSync()) await f.delete();
      }
      await base.writeAsBytes(bytes);
      expect(RespaldoService.problemaDeLaBase(base), isNotNull);
      expect(RespaldoService.ultimoSano(carpeta), sano);
      final guardada = await RespaldoService.reemplazarDanada(carpeta, sano);
      expect(File(guardada).existsSync(), isTrue);
      expect(RespaldoService.problemaDeLaBase(base), isNull);
      db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
    });

    test('un archivo que no es de Emma no se restaura', () async {
      final otro = File(p.join(carpeta.path, 'otro.db'))..writeAsStringSync('hola');
      expect(() => RespaldoService.validarRespaldo(otro), throwsA(isA<DatoInvalido>()));
    });

    test('el mantenimiento se hace una vez por semana', () async {
      final m = MantenimientoService(db);
      expect(await m.hacerSiToca(), isTrue);
      ahora = horaPrueba.add(const Duration(days: 3));
      expect(await m.hacerSiToca(), isFalse);
      ahora = horaPrueba.add(const Duration(days: 8));
      expect(await m.hacerSiToca(), isTrue);
    });

    test('avisa si el reloj de la computadora está atrasado', () async {
      final dueno = await sesionDueno(db);
      await CajaService(db).abrir(dueno, 0);
      final varios = await db.productoVarios();
      await VentaService(db).cobrar(dueno, SolicitudCobro(lineas: [LineaCobro.servicio(productoId: varios.id, descripcion: 'Varios', monto: 100)], formaPago: FormaPago.efectivo));
      final m = MantenimientoService(db);
      expect(await m.revisarReloj(), isNull);
      ahora = horaPrueba.subtract(const Duration(days: 2));
      expect(await m.revisarReloj(), contains('16/10/2026'));
    });
  });

  group('nube', () {
    late EmmaDatabase db;
    setUp(() => db = baseDePrueba());
    tearDown(() => db.close());

    test('el envío marca los enviados y reintenta si falla', () async {
      final dueno = await sesionDueno(db);
      await abrirTurno(db, dueno);
      final varios = await db.productoVarios();
      for (var i = 0; i < 3; i++) {
        await VentaService(db).cobrar(dueno, SolicitudCobro(lineas: [LineaCobro.servicio(productoId: varios.id, descripcion: 'Varios', monto: 100)], formaPago: FormaPago.efectivo));
      }
      final falso = _EnviadorFalso()..falla = true;
      final s = SincronizacionService(db, falso);
      expect(await s.pendientes(), 3);
      final malo = await s.sincronizar();
      expect(malo.error, 'Sin internet');
      expect(malo.pendientes, 3);
      expect((await db.select(db.eventosSalida).get()).every((e) => e.intentos == 1), isTrue);

      falso.falla = false;
      final bueno = await s.sincronizar();
      expect(bueno.enviados, 3);
      expect(bueno.pendientes, 0);
      expect(falso.recibidos.map((e) => e.tipo).toSet(), {TipoEvento.ventaRegistrada});
    });

    test('conecta con el código, guarda la llave y manda los eventos con su autorización', () async {
      final dueno = await sesionDueno(db);
      late http.Request ultimo;
      final cliente = MockClient((req) async {
        ultimo = req;
        if (req.url.path == '/api/caja/activar') {
          final b = jsonDecode(req.body) as Map<String, Object?>;
          if (b['codigo'] != 'EMMA-7K4P-9QX2') {
            return http.Response(jsonEncode({'detail': 'Ese código no existe.'}), 404, headers: _json);
          }
          return http.Response(
              jsonEncode({'cajaId': 'caja-1', 'llave': 'secreta', 'negocio': 'Colmado La Esquina', 'caja': 'Caja 1'}), 200,
              headers: _json);
        }
        if (req.headers['Authorization'] != 'Emma caja-1.secreta') return http.Response('', 401);
        return http.Response(jsonEncode({'nuevos': 1, 'repetidos': 0}), 200, headers: _json);
      });
      final nube = NubeService(db, version: '1.0.0', cliente: cliente, direccion: 'https://emma.test/');

      await expectLater(
        nube.conectar(dueno, 'MALO'),
        throwsA(isA<EmmaError>().having((e) => e.mensaje, 'mensaje', 'Ese código no existe.')),
      );
      expect(await nube.conectar(dueno, ' EMMA-7K4P-9QX2 ', nombrePc: 'CAJA'), 'Colmado La Esquina');
      expect(await nube.conectada(), isTrue);

      await abrirTurno(db, dueno);
      final varios = await db.productoVarios();
      await VentaService(db).cobrar(dueno, SolicitudCobro(lineas: [LineaCobro.servicio(productoId: varios.id, descripcion: 'Varios', monto: 2500)], formaPago: FormaPago.efectivo));
      final r = await SincronizacionService(db, nube).sincronizar();
      expect(r.error, isNull);
      expect(ultimo.url.toString(), 'https://emma.test/api/caja/eventos');
      expect(ultimo.headers['X-Emma-Version'], '1.0.0');
      final env = jsonDecode(ultimo.body) as Map<String, Object?>;
      final ev = (env['eventos']! as List).single as Map<String, Object?>;
      expect(ev['tipo'], TipoEvento.ventaRegistrada);
      expect(jsonDecode(ev['datos']! as String), containsPair('Total', 25));
      expect((await db.negocio()).nubeUltimoEnvio, isNotNull);

      await nube.desconectar(dueno);
      expect(await nube.conectada(), isFalse);
    });
  });
}
