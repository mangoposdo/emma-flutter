import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'impresora_windows.dart';

/// Manda bytes ESC/POS directo a una impresora del sistema (modo RAW), sin el
/// diálogo de impresión. La impresora térmica se instala con el driver del
/// fabricante (o como "Generic / Text Only" en Windows).
abstract class Impresora {
  /// Las impresoras instaladas en el sistema, por nombre.
  Future<List<String>> instaladas();

  /// Lanza [ErrorImpresora] si no se pudo.
  Future<void> enviarRaw(String impresora, Uint8List datos);

  factory Impresora.delSistema() => Platform.isWindows ? ImpresoraWindows() : ImpresoraCups();
}

class ErrorImpresora implements Exception {
  const ErrorImpresora(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// macOS y Linux: por CUPS (lpstat y lp -o raw).
class ImpresoraCups implements Impresora {
  @override
  Future<List<String>> instaladas() async {
    try {
      final r = await Process.run('lpstat', ['-e']);
      if (r.exitCode != 0) return [];
      return (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()..sort();
    } on ProcessException {
      return [];
    }
  }

  @override
  Future<void> enviarRaw(String impresora, Uint8List datos) async {
    final carpeta = await Directory.systemTemp.createTemp('emma_ticket_');
    try {
      final archivo = File(p.join(carpeta.path, 'ticket.bin'));
      await archivo.writeAsBytes(datos, flush: true);
      final ProcessResult r;
      try {
        r = await Process.run('lp', ['-d', impresora, '-o', 'raw', archivo.path]);
      } on ProcessException catch (e) {
        throw ErrorImpresora('No se pudo usar la impresión del sistema: ${e.message}');
      }
      if (r.exitCode != 0) {
        final detalle = '${r.stderr}'.trim();
        throw ErrorImpresora(detalle.isEmpty ? 'La impresora no aceptó el trabajo.' : detalle);
      }
    } finally {
      await carpeta.delete(recursive: true);
    }
  }
}
