import 'package:flutter/painting.dart';

/// Colores del manual de identidad (sección 05).
///
/// El rojo toldo es para UNA sola cosa por pantalla: la acción principal
/// (Cobrar, Empezar, Conectar) o el dato que más importa.
abstract final class EmmaColores {
  /// Fondo de barras y texto principal.
  static const azul = Color(0xFF14213D);

  /// Solo la acción principal.
  static const rojo = Color(0xFFD7263D);

  static const blanco = Color(0xFFFFFFFF);

  /// Textos de apoyo.
  static const grisPizarra = Color(0xFF56607A);

  /// Tintes del azul que aparecen en el manual (60 %, 25 %, 10 %, 5 %),
  /// mezclados sobre blanco para que sean colores sólidos.
  static final azul60 = _sobreBlanco(azul, 0.60);
  static final azul25 = _sobreBlanco(azul, 0.25);
  static final azul10 = _sobreBlanco(azul, 0.10);
  static final azul5 = _sobreBlanco(azul, 0.05);

  static Color _sobreBlanco(Color c, double opacidad) =>
      Color.alphaBlend(c.withValues(alpha: opacidad), blanco);
}
