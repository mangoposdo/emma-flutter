import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../comun/botones.dart';
import '../comun/escala.dart';
import '../comun/estilo.dart';
import 'router.dart';

ThemeData temaCaja() => EmmaTema.claro().copyWith(scaffoldBackgroundColor: Estilo.fondo);

const _localizaciones = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class EmmaCajaApp extends ConsumerWidget {
  const EmmaCajaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Emma',
      debugShowCheckedModeBanner: false,
      theme: temaCaja(),
      locale: const Locale('es', 'DO'),
      supportedLocales: const [Locale('es', 'DO'), Locale('es')],
      localizationsDelegates: _localizaciones,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => EscalaInterfaz(escala: escalaDeLaPlataforma(), child: child!),
    );
  }
}

/// Pantalla sola para cuando la caja no puede abrir: un mensaje y, si se puede,
/// un botón para arreglarlo.
class PantallaDeArranque extends StatelessWidget {
  const PantallaDeArranque({super.key, required this.titulo, required this.mensaje, this.accion, this.alAccion, this.alSalir});

  final String titulo;
  final String mensaje;
  final String? accion;
  final VoidCallback? alAccion;
  final VoidCallback? alSalir;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emma',
      debugShowCheckedModeBanner: false,
      theme: temaCaja(),
      locale: const Locale('es', 'DO'),
      supportedLocales: const [Locale('es', 'DO'), Locale('es')],
      localizationsDelegates: _localizaciones,
      builder: (context, child) => EscalaInterfaz(escala: escalaDeLaPlataforma(), child: child!),
      home: Scaffold(
        body: Row(
          children: [
            Container(
              width: 340,
              color: Estilo.azul,
              alignment: Alignment.center,
              child: const EmmaLogo(version: EmmaLogoVersion.negativo, ancho: 260),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Estilo.azul)),
                        const SizedBox(height: 12),
                        SelectableText(mensaje, style: const TextStyle(fontSize: 16, color: Estilo.azul, height: 1.4)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (accion != null) Boton(accion!, tipo: TipoBoton.accion, onPressed: alAccion),
                            if (alSalir != null) Boton('Salir', onPressed: alSalir),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
