import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'botones.dart';
import 'estilo.dart';

enum TipoAviso { info, aviso, error }

/// El cuadro de mensaje de la 0.7: "Emma", el texto y Aceptar.
Future<void> avisar(BuildContext context, String mensaje, {TipoAviso tipo = TipoAviso.aviso}) => showDialog<void>(
      context: context,
      builder: (c) => _Cuadro(
        mensaje: mensaje,
        icono: switch (tipo) {
          TipoAviso.info => Icons.info_outline,
          TipoAviso.aviso => Icons.warning_amber_rounded,
          TipoAviso.error => Icons.error_outline,
        },
        colorIcono: switch (tipo) {
          TipoAviso.info => Estilo.azul,
          TipoAviso.aviso => const Color(0xFFC88A04),
          TipoAviso.error => Estilo.rojo,
        },
        botones: [Boton('Aceptar', tipo: TipoBoton.principal, anchoMinimo: 100, onPressed: () => Navigator.pop(c))],
      ),
    );

Future<void> informar(BuildContext context, String mensaje) => avisar(context, mensaje, tipo: TipoAviso.info);

/// Pregunta de sí o no. Enter = Sí, Esc = No.
Future<bool> confirmar(BuildContext context, String mensaje) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => _Cuadro(
        mensaje: mensaje,
        icono: Icons.help_outline,
        colorIcono: Estilo.azul,
        alEnter: () => Navigator.pop(c, true),
        botones: [
          Boton('No', anchoMinimo: 100, onPressed: () => Navigator.pop(c, false)),
          Boton('Sí', tipo: TipoBoton.principal, anchoMinimo: 100, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ) ??
    false;

/// Corre [accion]; si una regla del negocio la detiene, muestra el mensaje.
/// Devuelve si salió bien.
Future<bool> intentar(BuildContext context, Future<void> Function() accion) async {
  try {
    await accion();
    return true;
  } on EmmaError catch (e) {
    if (context.mounted) await avisar(context, e.mensaje);
    return false;
  }
}

class _Cuadro extends StatelessWidget {
  const _Cuadro({required this.mensaje, required this.icono, required this.colorIcono, required this.botones, this.alEnter});

  final String mensaje;
  final IconData icono;
  final Color colorIcono;
  final List<Widget> botones;
  final VoidCallback? alEnter;

  @override
  Widget build(BuildContext context) {
    Widget cuadro = Dialog(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Emma', style: TextStyle(fontSize: 14, color: Estilo.gris)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icono, color: colorIcono, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: SingleChildScrollView(
                        child: SelectableText(mensaje, style: const TextStyle(fontSize: 16, color: Estilo.azul, height: 1.4)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: botones),
            ],
          ),
        ),
      ),
    );
    if (alEnter != null) {
      cuadro = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): alEnter!,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): alEnter!,
        },
        child: Focus(autofocus: true, child: cuadro),
      );
    }
    return cuadro;
  }
}
