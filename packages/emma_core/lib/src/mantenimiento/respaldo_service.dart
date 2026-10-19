import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../db/abrir_base.dart';
import '../db/database.dart';
import '../errores.dart';
import '../formato.dart';
import '../sesion.dart';

/// Copias de la base: al abrir, cada 2 horas y al cerrar la caja (igual que la 0.7).
class RespaldoService {
  RespaldoService(this.db, this.carpetaDatos, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  /// Se guardan siempre las más recientes...
  static const copiasRecientes = 20;

  /// ...y además la última de cada día durante este tiempo.
  static const diasConUnaPorDia = 30;

  final EmmaDatabase db;
  final Directory carpetaDatos;
  final Reloj _reloj;

  static Directory carpetaLocal(Directory carpetaDatos) => Directory(p.join(carpetaDatos.path, 'Respaldos'));

  Directory get carpeta => carpetaLocal(carpetaDatos);

  /// Copia la base a [destino] (por defecto la carpeta de respaldos) con la
  /// fecha en el nombre, y borra las copias que sobran. Se puede hacer con la
  /// caja vendiendo. Devuelve la ruta del archivo creado.
  Future<String> respaldar([Directory? destino]) async {
    final dir = destino ?? carpeta;
    await dir.create(recursive: true);
    final f = _reloj();
    String d(int n) => n.toString().padLeft(2, '0');
    var archivo = p.join(dir.path, 'emma_${f.year}-${d(f.month)}-${d(f.day)}_${d(f.hour)}${d(f.minute)}${d(f.second)}.db');
    if (File(archivo).existsSync()) await File(archivo).delete();
    // VACUUM INTO hace una copia completa y consistente sin parar la caja.
    await db.customStatement('VACUUM INTO ?', [archivo]);
    for (final viejo in sobrantes(listar(dir), f)) {
      try {
        await File(viejo).delete();
      } on FileSystemException {
        // Se intenta la próxima vez.
      }
    }
    return archivo;
  }

  /// Respaldos que se pueden borrar: se quedan los [copiasRecientes] más nuevos y
  /// el último de cada día de los últimos [diasConUnaPorDia]. Recibe la lista del
  /// más nuevo al más viejo.
  static List<String> sobrantes(List<String> respaldos, DateTime ahora) {
    final quedan = respaldos.take(copiasRecientes).toSet();
    final limite = soloDia(ahora).subtract(const Duration(days: diasConUnaPorDia));
    final vistos = <DateTime>{};
    for (final r in respaldos) {
      final dia = _dia(r);
      if (dia == null || dia.isBefore(limite)) continue;
      if (vistos.add(dia)) quedan.add(r);
    }
    return respaldos.where((r) => !quedan.contains(r)).toList();
  }

  /// Fecha del nombre "emma_2026-10-17_143000.db".
  static DateTime? _dia(String archivo) {
    final m = RegExp(r'_(\d{4})-(\d{2})-(\d{2})_').firstMatch(p.basename(archivo));
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// Respaldos de la carpeta, del más nuevo al más viejo.
  static List<String> listar(Directory carpeta) {
    if (!carpeta.existsSync()) return [];
    final lista = carpeta
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((r) => RegExp(r'^emma_.*\.db$').hasMatch(p.basename(r)))
        .toList()
      ..sort((a, b) => p.basename(b).compareTo(p.basename(a)));
    return lista;
  }

  /// Revisa que el archivo no esté dañado (PRAGMA quick_check). Si no existe
  /// todavía se considera sano. Devuelve null si está sano o el problema.
  static String? problemaDeLaBase(File archivo) {
    if (!archivo.existsSync() || archivo.lengthSync() == 0) return null;
    try {
      final s = sqlite3.open(archivo.path, mode: OpenMode.readOnly);
      try {
        final filas = s.select('PRAGMA quick_check').map((r) => r.values.first.toString()).toList();
        return filas.length == 1 && filas.first == 'ok' ? null : filas.join('; ');
      } finally {
        s.dispose();
      }
    } on SqliteException catch (e) {
      return e.message;
    }
  }

  /// El respaldo sano más nuevo (de Respaldos o de AntesDeActualizar), o null.
  static String? ultimoSano(Directory carpetaDatos) {
    final local = carpetaLocal(carpetaDatos);
    final todos = [...listar(local), ...listar(Directory(p.join(local.path, 'AntesDeActualizar')))]
      ..sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
    for (final r in todos) {
      if (problemaDeLaBase(File(r)) == null) return r;
    }
    return null;
  }

  /// Pone un respaldo en lugar de la base dañada. La dañada no se borra: se
  /// guarda en Respaldos/Dañadas para que soporte pueda sacarle datos.
  /// Llamar con la base cerrada. Devuelve dónde quedó la dañada.
  static Future<String> reemplazarDanada(Directory carpetaDatos, String respaldo) async {
    final base = p.join(carpetaDatos.path, nombreArchivoBase);
    final danadas = Directory(p.join(carpetaLocal(carpetaDatos).path, 'Dañadas'));
    await danadas.create(recursive: true);
    final ahora = DateTime.now();
    String d(int n) => n.toString().padLeft(2, '0');
    final guardada =
        p.join(danadas.path, 'emma_dañada_${ahora.year}-${d(ahora.month)}-${d(ahora.day)}_${d(ahora.hour)}${d(ahora.minute)}${d(ahora.second)}.db');
    for (final extra in const ['', '-wal', '-shm']) {
      final f = File('$base$extra');
      if (f.existsSync()) await f.rename('$guardada$extra');
    }
    await File(respaldo).copy(base);
    return guardada;
  }

  /// Revisa que [archivo] sea un respaldo de Emma que esta versión puede abrir.
  static void validarRespaldo(File archivo) {
    if (!archivo.existsSync()) throw const DatoInvalido('No se encontró el archivo de respaldo.');
    try {
      final s = sqlite3.open(archivo.path, mode: OpenMode.readOnly);
      try {
        final tablas = s.select("SELECT name FROM sqlite_master WHERE type = 'table'").map((r) => r['name']).toSet();
        if (!tablas.contains('ventas') || !tablas.contains('eventos_salida')) {
          throw const DatoInvalido('Ese archivo no es un respaldo de este sistema.');
        }
        if (s.userVersion > EmmaDatabase.versionEsquema) {
          throw const DatoInvalido('Ese respaldo es de una versión más nueva del programa.');
        }
      } finally {
        s.dispose();
      }
    } on SqliteException {
      throw const DatoInvalido('Ese archivo no es un respaldo de este sistema.');
    }
  }

  /// Primer paso de restaurar: valida el respaldo y guarda una copia de los
  /// datos actuales en Respaldos/AntesDeRestaurar. Después la app cierra la base
  /// y llama a [ponerRespaldo]. Devuelve la ruta de la copia de seguridad.
  Future<String> prepararRestauracion(Sesion sesion, String archivoRespaldo) async {
    requiereDueno(sesion.esDueno, 'restaurar un respaldo');
    validarRespaldo(File(archivoRespaldo));
    return respaldar(Directory(p.join(carpeta.path, 'AntesDeRestaurar')));
  }

  /// Segundo paso de restaurar, con la base ya cerrada.
  static Future<void> ponerRespaldo(Directory carpetaDatos, String archivoRespaldo) async {
    final base = p.join(carpetaDatos.path, nombreArchivoBase);
    for (final extra in const ['-wal', '-shm']) {
      final f = File('$base$extra');
      if (f.existsSync()) await f.delete();
    }
    await File(archivoRespaldo).copy(base);
  }
}

/// Cuidados de la base y revisiones que se hacen al abrir.
class MantenimientoService {
  MantenimientoService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  static const cada = Duration(days: 7);

  final EmmaDatabase db;
  final Reloj _reloj;

  /// Una vez por semana ordena y compacta la base para que siga rápida. Se hace
  /// al abrir, antes de que nadie esté vendiendo. Devuelve si se hizo.
  Future<bool> hacerSiToca() async {
    final n = await db.negocio();
    final ahora = _reloj();
    final ultimo = n.ultimoMantenimiento;
    if (ultimo != null && ahora.difference(ultimo) < cada && !ultimo.isAfter(ahora)) return false;
    await db.customStatement('PRAGMA optimize');
    await db.customStatement('VACUUM');
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id)))
        .write(NegociosCompanion(ultimoMantenimiento: Value(ahora)));
    return true;
  }

  /// Si la fecha de la PC está antes de la última venta, el reloj está atrasado
  /// y las ventas saldrían con fecha equivocada. Devuelve el aviso o null.
  Future<String?> revisarReloj() async {
    final ultima = await (db.select(db.ventas)
          ..orderBy([(v) => OrderingTerm.desc(v.id)])
          ..limit(1))
        .getSingleOrNull();
    final ahora = _reloj();
    if (ultima == null || !ahora.isBefore(ultima.fecha.subtract(const Duration(hours: 1)))) return null;
    return 'La fecha de esta computadora (${formatoFechaHora(ahora)}) es anterior a la última venta '
        '(${formatoFechaHora(ultima.fecha)}). Corrija la fecha y la hora para que las ventas salgan bien.';
  }
}
