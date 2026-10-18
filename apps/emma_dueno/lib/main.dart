import 'package:flutter/material.dart';

// Se construye en la Fase 6. Por ahora la app solo arranca.
void main() => runApp(const EmmaDuenoApp());

class EmmaDuenoApp extends StatelessWidget {
  const EmmaDuenoApp({super.key});

  static const azul = Color(0xFF14213D);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emma Dueño',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: azul)),
      home: const Scaffold(body: Center(child: Text('Emma Dueño'))),
    );
  }
}
