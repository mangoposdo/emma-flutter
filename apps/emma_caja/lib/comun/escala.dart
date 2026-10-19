import 'dart:io';

import 'package:flutter/widgets.dart';

/// Cuánto se achica la pantalla. En Windows, 1: la caja usa las mismas
/// unidades que la 0.7 y sale del mismo tamaño. En macOS (solo para
/// desarrollar) todo se mide en puntos de dos píxeles, como un Windows con
/// zoom; con 0.7 cabe lo mismo que en un monitor de mostrador.
/// Las pruebas miden a tamaño real, como una PC con Windows.
double escalaDeLaPlataforma() =>
    Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST') ? 0.7 : 1.0;

/// Dibuja [child] como si la ventana fuera 1/[escala] más grande y lo achica
/// para que quepa: letras, botones y ventanitas en la misma proporción.
class EscalaInterfaz extends StatelessWidget {
  const EscalaInterfaz({super.key, required this.escala, required this.child});

  final double escala;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (escala == 1) return child;
    final mq = MediaQuery.of(context);
    final tamano = mq.size / escala;
    return MediaQuery(
      data: mq.copyWith(
        size: tamano,
        devicePixelRatio: mq.devicePixelRatio * escala,
        padding: mq.padding / escala,
        viewPadding: mq.viewPadding / escala,
        viewInsets: mq.viewInsets / escala,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(width: tamano.width, height: tamano.height, child: child),
      ),
    );
  }
}
