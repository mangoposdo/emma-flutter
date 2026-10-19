/// Página de códigos 850 (la que se le pide a la impresora con ESC t 2), para
/// que salgan las tildes, la ñ, ¿ y ¡. Lo que no está en la página sale como "?".
library;

import 'dart:typed_data';

// Caracteres de 0x80 a 0xFF, en orden.
const _altos = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐'
    '└┴┬├─┼ãÃ╚╔╩╦╠═╬¤ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀ÓßÔÒõÕµþÞÚÛÙýÝ¯´­±‗¾¶§÷¸°¨·¹³²■ ';

final Map<int, int> _tabla = {
  for (var i = 0; i < _altos.length; i++) _altos.codeUnitAt(i): 0x80 + i,
};

Uint8List codificarCp850(String texto) {
  final salida = Uint8List(texto.length);
  var n = 0;
  for (final r in texto.runes) {
    if (r < 0x80) {
      salida[n++] = r;
    } else {
      salida[n++] = _tabla[r] ?? 0x3F; // ?
    }
  }
  return Uint8List.sublistView(salida, 0, n);
}
