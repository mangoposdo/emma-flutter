import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:emma_core/emma_core.dart';

import 'logo_en_grises.dart';

class ImagenEnGrises {
  const ImagenEnGrises(this.grises, this.ancho, this.alto);

  /// 0 = negro, 255 = blanco.
  final Uint8List grises;
  final int ancho;
  final int alto;
}

/// Abre la imagen (PNG, JPG, BMP, GIF) y la pasa a grises sobre fondo blanco.
/// Una foto más ancha de [anchoMaximoAlAbrir] se reduce al abrirla.
Future<ImagenEnGrises> leerEnGrises(String ruta) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? imagen;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(await File(ruta).readAsBytes());
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec(
      targetWidth: descriptor.width > anchoMaximoAlAbrir ? anchoMaximoAlAbrir : null,
    );
    imagen = (await codec.getNextFrame()).image;
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (datos == null) throw const EmmaError('No se pudo abrir esa imagen. Escoja un PNG o JPG.');
    final rgba = datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
    return ImagenEnGrises(grisesSobreBlanco(rgba), imagen.width, imagen.height);
  } on EmmaError {
    rethrow;
  } catch (_) {
    throw const EmmaError('No se pudo abrir esa imagen. Escoja un PNG o JPG.');
  } finally {
    imagen?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
