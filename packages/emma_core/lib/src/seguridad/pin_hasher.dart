import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// PIN con PBKDF2-SHA256 y sal al azar. Nunca se guarda el PIN.
///
/// Formato guardado: `pbkdf2-sha256$<vueltas>$<sal base64>$<hash base64>`.
/// Las vueltas van dentro del texto, así se pueden subir más adelante sin
/// romper los PIN ya guardados.
class PinHasher {
  PinHasher({this.vueltas = vueltasPorDefecto});

  /// Igual que la 0.6.
  static const vueltasPorDefecto = 100000;
  static const _prefijo = 'pbkdf2-sha256';

  final int vueltas;

  Future<String> hash(String pin) async {
    final rnd = Random.secure();
    final sal = List<int>.generate(16, (_) => rnd.nextInt(256));
    final h = await _derivar(pin, sal, vueltas);
    return '$_prefijo\$$vueltas\$${base64Encode(sal)}\$${base64Encode(h)}';
  }

  Future<bool> verificar(String pin, String guardado) async {
    final partes = guardado.split(r'$');
    if (partes.length != 4 || partes[0] != _prefijo) return false;
    final it = int.tryParse(partes[1]);
    if (it == null || it <= 0) return false;
    final sal = base64Decode(partes[2]);
    final esperado = base64Decode(partes[3]);
    final calculado = await _derivar(pin, sal, it);
    return _igualesTiempoConstante(calculado, esperado);
  }

  static Future<List<int>> _derivar(String pin, List<int> sal, int vueltas) async {
    final algoritmo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: vueltas, bits: 256);
    final llave = await algoritmo.deriveKeyFromPassword(password: pin, nonce: sal);
    return llave.extractBytes();
  }

  static bool _igualesTiempoConstante(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var dif = 0;
    for (var i = 0; i < a.length; i++) {
      dif |= a[i] ^ b[i];
    }
    return dif == 0;
  }
}
