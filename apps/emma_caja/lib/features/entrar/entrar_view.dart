import 'dart:io';

import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/version.dart';
import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import 'entrar_view_model.dart';

/// La entrada de la 0.7: logo a la izquierda, usuario y PIN a la derecha.
class EntrarView extends ConsumerStatefulWidget {
  const EntrarView({super.key});

  @override
  ConsumerState<EntrarView> createState() => _EntrarViewState();
}

class _EntrarViewState extends ConsumerState<EntrarView> {
  final _usuario = TextEditingController();
  final _pin = TextEditingController();
  final _focoUsuario = FocusNode();
  final _focoPin = FocusNode();

  @override
  void dispose() {
    _usuario.dispose();
    _pin.dispose();
    _focoUsuario.dispose();
    _focoPin.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final error = await ref.read(entrarViewModelProvider.notifier).entrar(_usuario.text, _pin.text);
    if (error == null || !mounted) return;
    _pin.clear();
    await avisar(context, error);
    _focoPin.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(entrarViewModelProvider).value;
    return Scaffold(
      backgroundColor: Estilo.fondo,
      body: Center(
        child: Container(
          width: 760,
          decoration: BoxDecoration(
            color: Estilo.fondo,
            border: Border.all(color: Estilo.borde),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 340,
                  color: Estilo.azul,
                  padding: const EdgeInsets.all(28),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      EmmaLogo(version: EmmaLogoVersion.negativo, ancho: 260),
                      SizedBox(height: 18),
                      Text('Versión $versionEmma · Funciona sin internet',
                          style: TextStyle(fontSize: 13, color: Estilo.textoSobreAzul)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(s?.negocio.isNotEmpty == true ? s!.negocio : 'Bienvenido',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Estilo.azul)),
                        ),
                        const TextoGris('Escriba su usuario y PIN', margen: EdgeInsets.fromLTRB(4, 4, 4, 20)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('Usuario', style: TextStyle(fontSize: 16, color: Estilo.azul))),
                        Casilla(
                          controller: _usuario,
                          foco: _focoUsuario,
                          autofocus: true,
                          tamano: 18,
                          onSubmitted: (_) => _focoPin.requestFocus(),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                          child: Text('PIN', style: TextStyle(fontSize: 16, color: Estilo.azul)),
                        ),
                        Casilla(controller: _pin, foco: _focoPin, oculta: true, tamano: 18, onSubmitted: (_) => _entrar()),
                        Boton(
                          'ENTRAR',
                          tipo: TipoBoton.accion,
                          tamano: 18,
                          margen: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                          onPressed: s?.entrando ?? false ? null : _entrar,
                        ),
                        Boton('Salir', onPressed: () => exit(0)),
                        if (s?.primeraVez ?? false)
                          const TextoGris('Primera vez: usuario admin y PIN 1234. Cámbielo en Configuración.',
                              margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
