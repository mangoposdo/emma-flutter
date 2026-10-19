import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Escoger un archivo para abrir. null si cancelan.
Future<String?> escogerArchivo({required String descripcion, required List<String> extensiones, String? carpeta}) async {
  final f = await openFile(
    acceptedTypeGroups: [XTypeGroup(label: descripcion, extensions: extensiones)],
    initialDirectory: carpeta,
  );
  return f?.path;
}

/// Escoger dónde guardar. null si cancelan.
Future<String?> escogerDondeGuardar({required String nombre, required String descripcion, required List<String> extensiones}) async {
  final r = await getSaveLocation(
    suggestedName: nombre,
    acceptedTypeGroups: [XTypeGroup(label: descripcion, extensions: extensiones)],
  );
  return r?.path;
}

/// Escoger una carpeta (respaldo en USB). null si cancelan.
Future<String?> escogerCarpeta() => getDirectoryPath();

/// Abre la carpeta en el explorador del sistema.
Future<void> abrirCarpeta(String ruta) async {
  await Directory(ruta).create(recursive: true);
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [ruta]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [ruta]);
  } else {
    await Process.run('xdg-open', [ruta]);
  }
}
