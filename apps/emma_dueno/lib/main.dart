import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/material.dart';

// Se construye en la Fase 6. Por ahora la app arranca con la marca.
void main() => runApp(const EmmaDuenoApp());

class EmmaDuenoApp extends StatelessWidget {
  const EmmaDuenoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emma Dueño',
      debugShowCheckedModeBanner: false,
      theme: EmmaTema.claro(),
      home: Scaffold(
        appBar: AppBar(
          title: const EmmaLogo(version: EmmaLogoVersion.horizontalNegativo, ancho: 140),
        ),
        body: const Center(child: EmmaLogo(ancho: 260)),
      ),
    );
  }
}
