import 'package:flutter/material.dart';

// Las pantallas llegan en la Fase 2. Por ahora la app solo arranca.
void main() => runApp(const EmmaCajaApp());

class EmmaCajaApp extends StatelessWidget {
  const EmmaCajaApp({super.key});

  static const azul = Color(0xFF14213D);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emma Caja',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: azul)),
      home: const Scaffold(body: Center(child: Text('Emma Caja'))),
    );
  }
}
