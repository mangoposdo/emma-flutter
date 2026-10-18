import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../errores.dart';
import '../seguridad/pin_hasher.dart';
import '../sesion.dart';
import 'database.dart';

const nombreArchivoBase = 'emma.db';

/// Carpeta de datos por defecto en Windows. En Android la app pasa su
/// almacenamiento interno (path_provider) a [abrirBaseDeDatos].
const carpetaDatosWindows = r'C:\ProgramData\ColmadoEmma';

/// Ajustes de SQLite para que un apagón no pierda ni dañe nada:
/// WAL, escritura completa al disco en cada transacción y llaves foráneas.
void configurarSqlite(Database db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA synchronous = FULL');
  db.execute('PRAGMA busy_timeout = 5000');
  db.execute('PRAGMA foreign_keys = ON');
}

/// Abre (o crea) la base en [carpetaDatos]. Si hay migraciones pendientes,
/// primero copia la base a `Respaldos/AntesDeActualizar`; si la migración
/// falla, vuelve sola a esa copia y lanza [ErrorMigracion].
Future<EmmaDatabase> abrirBaseDeDatos(
  Directory carpetaDatos, {
  PinHasher? pinHasher,
  Reloj reloj = relojDelSistema,
}) async {
  await carpetaDatos.create(recursive: true);
  final archivo = File(p.join(carpetaDatos.path, nombreArchivoBase));
  return abrirConRespaldo<EmmaDatabase>(
    archivo: archivo,
    versionEsperada: EmmaDatabase.versionEsquema,
    carpetaRespaldos: Directory(p.join(carpetaDatos.path, 'Respaldos')),
    reloj: reloj,
    abrir: () async {
      final db = EmmaDatabase(
        NativeDatabase.createInBackground(archivo, setup: configurarSqlite),
        pinHasher: pinHasher,
        reloj: reloj,
      );
      try {
        // drift abre y migra en la primera consulta: se fuerza aquí para
        // que cualquier fallo de migración se atrape ahora.
        await db.customSelect('SELECT 1').get();
        return db;
      } catch (_) {
        await db.close();
        rethrow;
      }
    },
  );
}

/// Versión del esquema guardada en el archivo (PRAGMA user_version), o null
/// si el archivo no existe.
int? versionDelArchivo(File archivo) {
  if (!archivo.existsSync()) return null;
  final db = sqlite3.open(archivo.path);
  try {
    // Pasa lo que esté en el WAL al archivo principal antes de copiarlo.
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    return db.userVersion;
  } finally {
    db.dispose();
  }
}

/// Paso genérico de respaldo y vuelta atrás. [abrir] debe abrir la base,
/// aplicar las migraciones y, si falla, cerrar su conexión antes de lanzar.
Future<T> abrirConRespaldo<T>({
  required File archivo,
  required int versionEsperada,
  required Directory carpetaRespaldos,
  required Future<T> Function() abrir,
  Reloj reloj = relojDelSistema,
}) async {
  final version = versionDelArchivo(archivo);
  // Base nueva o ya al día: no hay nada que respaldar.
  if (version == null || version == 0 || version >= versionEsperada) {
    return abrir();
  }

  final destino = Directory(p.join(carpetaRespaldos.path, 'AntesDeActualizar'));
  await destino.create(recursive: true);
  final copia = File(p.join(destino.path, 'emma_v${version}_${_sello(reloj())}.db'));
  await archivo.copy(copia.path);

  try {
    return await abrir();
  } catch (e) {
    // En Windows el archivo puede seguir tomado un momento después de cerrar.
    await _conReintentos(() async {
      for (final sufijo in const ['-wal', '-shm', '-journal']) {
        final aux = File('${archivo.path}$sufijo');
        if (aux.existsSync()) await aux.delete();
      }
      await copia.copy(archivo.path);
    });
    throw ErrorMigracion(
      'No se pudo actualizar la base de datos. Se volvió a la copia de antes de '
      'actualizar y no se perdió nada. Llama a soporte.',
      causa: e,
      copia: copia.path,
    );
  }
}

Future<void> _conReintentos(Future<void> Function() accion) async {
  for (var intento = 1;; intento++) {
    try {
      await accion();
      return;
    } on FileSystemException {
      if (intento >= 10) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

String _sello(DateTime f) {
  String d(int n) => n.toString().padLeft(2, '0');
  return '${f.year}${d(f.month)}${d(f.day)}_${d(f.hour)}${d(f.minute)}${d(f.second)}';
}
