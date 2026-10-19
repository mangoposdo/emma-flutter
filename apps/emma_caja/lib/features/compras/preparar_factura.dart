import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:emma_core/emma_core.dart';
import 'package:image/image.dart' as img;

const _noSeAbre = 'No se pudo abrir ese archivo. Escoja una foto (JPG o PNG) o un PDF.';

/// El lado mayor de la foto que se manda a leer.
const ladoMaximoFactura = 2400;

const _pesoMaximoPdf = 8 * 1024 * 1024;
const _pesoFotoSinTocar = 3500000;

/// La foto o el PDF de la factura listo para mandar a leer: los bytes y su tipo.
/// Las fotos del celular vienen grandes y a veces de lado: se enderezan y se
/// achican antes de enviarlas. Lanza [EmmaError] con el mensaje para mostrar.
Future<(Uint8List, String)> prepararFactura(String ruta) async {
  final tipo = NubeService.tipoFactura(ruta);
  final Uint8List bytes;
  try {
    bytes = await File(ruta).readAsBytes();
  } on FileSystemException {
    throw const DatoInvalido(_noSeAbre);
  }
  if (tipo == 'application/pdf') {
    if (bytes.length > _pesoMaximoPdf) throw const DatoInvalido('El PDF pesa más de 8 MB.');
    return (bytes, tipo);
  }
  final listo = await Isolate.run(() => arreglarFoto(bytes, tipo));
  if (listo == null) throw const DatoInvalido(_noSeAbre);
  return listo;
}

/// Si la foto ya está derecha, no pasa de 2400 px ni de 3.5 MB, va tal cual;
/// si no, se endereza, se achica y se manda en JPEG calidad 85. null si no es
/// una imagen que se pueda abrir.
(Uint8List, String)? arreglarFoto(Uint8List bytes, String tipo) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) return null;
    final orientacion = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
    final mayor = max(info.width, info.height);
    if (orientacion == 1 && mayor <= ladoMaximoFactura && bytes.length <= _pesoFotoSinTocar) return (bytes, tipo);

    final foto = img.decodeImage(bytes);
    if (foto == null) return null;
    var listo = img.bakeOrientation(foto);
    final lado = max(listo.width, listo.height);
    if (lado > ladoMaximoFactura) {
      listo = listo.width >= listo.height
          ? img.copyResize(listo, width: ladoMaximoFactura, interpolation: img.Interpolation.average)
          : img.copyResize(listo, height: ladoMaximoFactura, interpolation: img.Interpolation.average);
    }
    // Sin los datos de la cámara (ubicación, orientación): ya va derecha.
    listo.exif = img.ExifData();
    return (img.encodeJpg(listo, quality: 85), 'image/jpeg');
  } catch (_) {
    // Un archivo dañado puede romper el decodificador con cualquier error.
    return null;
  }
}
