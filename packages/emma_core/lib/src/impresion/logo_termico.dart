import 'dart:typed_data';

/// Logo listo para la impresora: puntos blanco y negro, 8 por byte, fila por fila.
class LogoConvertido {
  const LogoConvertido(this.puntos, this.ancho, this.alto);

  final Uint8List puntos;

  /// En puntos, múltiplo de 8.
  final int ancho;
  final int alto;
}

/// Convierte una imagen a puntos blanco y negro para la impresora térmica.
/// Recibe la imagen ya en grises (0 = negro, 255 = blanco).
abstract final class LogoTermico {
  /// Cabe en papel de 58 mm (384 puntos) y de 80 mm; unos 4.5 cm de ancho.
  static const anchoMaximo = 360;

  /// Unos 2 cm de alto, para no gastar mucho papel.
  static const altoMaximo = 160;

  static const _negroHasta = 70.0;
  static const _blancoDesde = 200.0;

  static LogoConvertido convertir(Uint8List grises, int ancho, int alto) {
    if (ancho <= 0 || alto <= 0 || grises.length < ancho * alto) {
      throw ArgumentError('Imagen vacía o incompleta.');
    }
    final escala = [1.0, anchoMaximo / ancho, altoMaximo / alto].reduce((a, b) => a < b ? a : b);
    final nuevoAncho = (ancho * escala).round().clamp(8, 1 << 20);
    final nuevoAlto = (alto * escala).round().clamp(1, 1 << 20);
    final anchoBytes = (nuevoAncho + 7) ~/ 8;

    // Promedio de los pixeles que caen en cada punto: reduce sin perder las
    // líneas finas. Más contraste: lo oscuro sale negro sólido y lo claro, blanco.
    final valores = Float64List(nuevoAncho * nuevoAlto);
    for (var y = 0; y < nuevoAlto; y++) {
      final y0 = y * alto ~/ nuevoAlto;
      final y1 = ((y + 1) * alto ~/ nuevoAlto).clamp(y0 + 1, alto);
      for (var x = 0; x < nuevoAncho; x++) {
        final x0 = x * ancho ~/ nuevoAncho;
        final x1 = ((x + 1) * ancho ~/ nuevoAncho).clamp(x0 + 1, ancho);
        var suma = 0;
        for (var yy = y0; yy < y1; yy++) {
          for (var xx = x0; xx < x1; xx++) {
            suma += grises[yy * ancho + xx];
          }
        }
        final gris = suma / ((y1 - y0) * (x1 - x0));
        valores[y * nuevoAncho + x] = ((gris - _negroHasta) * 255 / (_blancoDesde - _negroHasta)).clamp(0, 255);
      }
    }

    // Floyd-Steinberg: los grises salen como puntitos en vez de manchas.
    final puntos = Uint8List(anchoBytes * nuevoAlto);
    for (var y = 0; y < nuevoAlto; y++) {
      for (var x = 0; x < nuevoAncho; x++) {
        final i = y * nuevoAncho + x;
        final negro = valores[i] < 128;
        if (negro) puntos[y * anchoBytes + x ~/ 8] |= 0x80 >> (x % 8);
        final error = valores[i] - (negro ? 0 : 255);
        if (x + 1 < nuevoAncho) valores[i + 1] += error * 7 / 16;
        if (y + 1 < nuevoAlto) {
          if (x > 0) valores[i + nuevoAncho - 1] += error * 3 / 16;
          valores[i + nuevoAncho] += error * 5 / 16;
          if (x + 1 < nuevoAncho) valores[i + nuevoAncho + 1] += error * 1 / 16;
        }
      }
    }
    return LogoConvertido(puntos, anchoBytes * 8, nuevoAlto);
  }

  /// Comando GS v 0 (imagen de puntos), en tiras de 128 filas porque algunas
  /// impresoras no aceptan más de una vez.
  static Uint8List comando(Uint8List puntos, int ancho) {
    final anchoBytes = ancho ~/ 8;
    final alto = puntos.length ~/ anchoBytes;
    final salida = BytesBuilder(copy: false);
    for (var inicio = 0; inicio < alto; inicio += 128) {
      final filas = (alto - inicio).clamp(0, 128);
      salida.add([0x1D, 0x76, 0x30, 0x00, anchoBytes & 0xFF, anchoBytes >> 8, filas & 0xFF, filas >> 8]);
      salida.add(Uint8List.sublistView(puntos, inicio * anchoBytes, (inicio + filas) * anchoBytes));
    }
    return salida.toBytes();
  }
}
