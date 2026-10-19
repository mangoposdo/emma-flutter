import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:path_provider/path_provider.dart';

/// Dónde vive la base. En Windows, la carpeta compartida de siempre
/// (`C:\ProgramData\ColmadoEmma`); en Android, y en macOS mientras se
/// desarrolla, el almacenamiento interno de la app.
Future<Directory> carpetaDeDatos() async {
  if (Platform.isWindows) return Directory(carpetaDatosWindows);
  return getApplicationSupportDirectory();
}
