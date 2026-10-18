import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  group('migración inicial (versión 1)', () {
    late EmmaDatabase db;
    setUp(() => db = baseDePrueba());
    tearDown(() => db.close());

    test('crea todas las tablas del modelo de datos', () async {
      final filas = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
          .get();
      final tablas = filas.map((f) => f.read<String>('name')).toSet();
      expect(
        tablas,
        containsAll(<String>[
          'negocio',
          'usuarios',
          'categorias',
          'productos',
          'clientes',
          'repartidores',
          'turnos_caja',
          'ventas',
          'venta_lineas',
          'tickets_abiertos',
          'movimientos_inventario',
          'movimientos_fiado',
          'movimientos_caja',
          'bitacora',
          'eventos_salida',
        ]),
      );
    });

    test('siembra el negocio con su instalacionId', () async {
      final n = await db.negocio();
      expect(n.instalacionId, isNotEmpty);
      expect(n.anchoTicket, 80);
      expect(n.intensidadTicket, IntensidadTicket.normal);
      expect(await contar(db, 'negocio'), 1);
    });

    test('crea el usuario admin, dueño, con PIN 1234 guardado como hash', () async {
      final u = await (db.select(db.usuarios)..where((x) => x.login.equals('admin'))).getSingle();
      expect(u.rol, Rol.dueno);
      expect(u.activo, isTrue);
      expect(u.pinHash, isNot('1234'));
      expect(u.pinHash, startsWith('pbkdf2-sha256\$'));
      expect(await db.pinHasher.verificar('1234', u.pinHash), isTrue);
      expect(await db.pinHasher.verificar('0000', u.pinHash), isFalse);
    });

    test('crea el producto interno Varios', () async {
      final v = await db.productoVarios();
      expect(v.codigo, codigoVarios);
      expect(v.nombre, 'Varios');
    });

    test('las llaves foráneas están activas', () async {
      final f = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(f.read<int>('foreign_keys'), 1);
    });

    test('el código de producto es único', () async {
      await crearProducto(db, codigo: 'X1', nombre: 'Uno', precio: 100);
      await expectLater(crearProducto(db, codigo: 'X1', nombre: 'Dos', precio: 100), throwsA(anything));
    });
  });

  group('abrir en disco', () {
    late Directory carpeta;
    setUp(() async => carpeta = await Directory.systemTemp.createTemp('emma_prueba_'));
    tearDown(() async {
      if (carpeta.existsSync()) await carpeta.delete(recursive: true);
    });

    test('abre en modo WAL y guarda la versión del esquema', () async {
      final db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      final modo = await db.customSelect('PRAGMA journal_mode').getSingle();
      expect(modo.read<String>('journal_mode'), 'wal');
      await db.close();
      expect(versionDelArchivo(File(p.join(carpeta.path, nombreArchivoBase))), EmmaDatabase.versionEsquema);
    });

    test('volver a abrir no pierde datos ni repite la siembra', () async {
      var db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      await crearCliente(db, nombre: 'Rosa');
      await db.close();

      db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      expect(await contar(db, 'clientes'), 1);
      expect(await contar(db, 'usuarios'), 1);
      expect(await contar(db, 'negocio'), 1);
      await db.close();
    });

    test('si una migración falla, respalda antes y vuelve sola a la copia', () async {
      final db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      await crearCliente(db, nombre: 'Rosa');
      await db.close();

      final archivo = File(p.join(carpeta.path, nombreArchivoBase));
      final respaldos = Directory(p.join(carpeta.path, 'Respaldos'));

      // Simula una versión 2 cuya migración daña la base a medias y falla.
      await expectLater(
        abrirConRespaldo<void>(
          archivo: archivo,
          versionEsperada: EmmaDatabase.versionEsquema + 1,
          carpetaRespaldos: respaldos,
          reloj: () => horaPrueba,
          abrir: () async {
            final s = sqlite3.open(archivo.path);
            try {
              s.execute('DROP TABLE clientes');
            } finally {
              s.dispose();
            }
            throw StateError('falló la migración');
          },
        ),
        throwsA(isA<ErrorMigracion>().having((e) => e.copia, 'copia', isNotNull)),
      );

      final copias = Directory(p.join(respaldos.path, 'AntesDeActualizar')).listSync();
      expect(copias, hasLength(1));
      expect(p.basename(copias.single.path), 'emma_v1_20261018_103005.db');

      // La base quedó como antes: la tabla y el cliente siguen ahí.
      final otra = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      expect(await contar(otra, 'clientes'), 1);
      await otra.close();
    });

    test('base nueva o ya al día: no hace copia', () async {
      final db = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      await db.close();
      final db2 = await abrirBaseDeDatos(carpeta, pinHasher: PinHasher(vueltas: 1000));
      await db2.close();
      expect(Directory(p.join(carpeta.path, 'Respaldos')).existsSync(), isFalse);
    });
  });
}
