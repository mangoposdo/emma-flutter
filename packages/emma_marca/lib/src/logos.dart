import 'package:flutter/widgets.dart';

/// Versiones del logo (manual, sección 02). Se usan siempre desde los
/// archivos originales: sin estirar, girar, cambiar colores ni poner sombras.
enum EmmaLogoVersion {
  /// Fondos blancos o claros. La que se usa siempre que se pueda.
  principal('emma-logo.png', 2000 / 770),

  /// Sobre azul o fotos oscuras.
  negativo('emma-logo-negativo.png', 2000 / 770),

  /// Espacios bajos y anchos: encabezados.
  horizontal('emma-horizontal.png', 2000 / 534),

  /// Barras azules del programa y del portal.
  horizontalNegativo('emma-horizontal-negativo.png', 2000 / 534),

  /// App, acceso directo, lugares pequeños.
  icono('emma-icono.png', 1),

  /// Promociones y avisos.
  iconoRojo('emma-icono-rojo.png', 1),

  /// Sobre azul o rojo.
  iconoBlanco('emma-icono-blanco.png', 1);

  const EmmaLogoVersion(this.archivo, this.proporcion);

  final String archivo;

  /// Ancho entre alto.
  final double proporcion;

  String get ruta => 'packages/emma_marca/assets/logos/$archivo';
}

/// Logo a un ancho dado, siempre con su proporción.
///
/// Debajo de 120 px de ancho el lema no se lee: con [EmmaLogoVersion.principal]
/// o [EmmaLogoVersion.negativo] a menos de 120 px se cambia solo al ícono.
class EmmaLogo extends StatelessWidget {
  const EmmaLogo({super.key, this.version = EmmaLogoVersion.principal, required this.ancho});

  final EmmaLogoVersion version;
  final double ancho;

  static const anchoMinimoConLema = 120.0;

  @override
  Widget build(BuildContext context) {
    var v = version;
    if (ancho < anchoMinimoConLema) {
      if (v == EmmaLogoVersion.principal) v = EmmaLogoVersion.icono;
      if (v == EmmaLogoVersion.negativo) v = EmmaLogoVersion.iconoBlanco;
    }
    return Image.asset(
      v.ruta,
      width: ancho,
      height: ancho / v.proporcion,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Emma, tu colmado en orden',
    );
  }
}

/// Logo a una tinta para el ticket de 80 mm: 384 puntos de ancho.
const rutaLogoTicket = 'packages/emma_marca/assets/ticket/emma-ticket-384.png';
