import 'dart:typed_data';

/// Una foto más ancha que esto se reduce al abrirla, para no gastar memoria (igual que la 0.7).
const anchoMaximoAlAbrir = 1440;

/// Pasa pixeles RGBA (sin premultiplicar) a grises sobre fondo blanco: lo
/// transparente queda blanco. Misma fórmula que la 0.7.
Uint8List grisesSobreBlanco(Uint8List rgba) {
  final grises = Uint8List(rgba.length ~/ 4);
  for (var i = 0; i < grises.length; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2], a = rgba[i * 4 + 3];
    final luz = (r * 299 + g * 587 + b * 114) ~/ 1000;
    grises[i] = 255 - (255 - luz) * a ~/ 255;
  }
  return grises;
}

/// Filas del logo guardado (8 puntos por byte).
int altoDelLogo(Uint8List puntos, int ancho) => puntos.length ~/ (ancho ~/ 8);

/// El logo tal como lo imprime la impresora, en pixeles RGBA para verlo en
/// pantalla: bit 1 = negro, 8 puntos por byte, fila por fila.
Uint8List rgbaDelLogo(Uint8List puntos, int ancho) {
  final anchoBytes = ancho ~/ 8;
  final alto = altoDelLogo(puntos, ancho);
  final rgba = Uint8List(ancho * alto * 4);
  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      final negro = puntos[y * anchoBytes + x ~/ 8] & (0x80 >> (x % 8)) != 0;
      final i = (y * ancho + x) * 4;
      final v = negro ? 0 : 255;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}
