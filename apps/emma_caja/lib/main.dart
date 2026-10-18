import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/material.dart';

// Las pantallas llegan en la Fase 2. Por ahora la app arranca con la marca.
void main() => runApp(const EmmaCajaApp());

class EmmaCajaApp extends StatelessWidget {
  const EmmaCajaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emma Caja',
      debugShowCheckedModeBanner: false,
      theme: EmmaTema.claro(),
      home: Scaffold(
        appBar: AppBar(
          // Barra azul con el logo horizontal negativo (manual, sección 02).
          title: const EmmaLogo(version: EmmaLogoVersion.horizontalNegativo, ancho: 140),
        ),
        body: const Center(child: EmmaLogo(ancho: 320)),
      ),
    );
  }
}
