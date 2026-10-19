import 'package:emma_core/emma_core.dart';
import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/cuidados.dart';
import '../app/providers.dart';
import '../app/router.dart';
import '../comun/avisos.dart';
import '../comun/estilo.dart';

/// La ventana principal de la 0.7: el menú azul a la izquierda y la pantalla a
/// la derecha. F1 vuelve a Ventas desde cualquier pantalla.
class ShellView extends ConsumerStatefulWidget {
  const ShellView({super.key, required this.pantalla, required this.child});

  final Pantalla pantalla;
  final Widget child;

  @override
  ConsumerState<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends ConsumerState<ShellView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _avisosAlEntrar());
  }

  Future<void> _avisosAlEntrar() async {
    for (final a in ref.read(avisosDeArranqueProvider.notifier).tomar()) {
      if (!mounted) return;
      await avisar(context, a);
    }
    final sesion = ref.read(sesionProvider);
    if (sesion == null || !sesion.esDueno) return;
    if (await ref.read(usuarioServiceProvider).usaPinDeFabrica() && mounted) {
      await avisar(context,
          'El usuario admin todavía usa el PIN 1234. Cámbielo en Configuración para que nadie más pueda entrar como dueño.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    if (sesion == null) return const SizedBox.shrink();
    final negocio = ref.watch(negocioProvider).value;
    final turno = ref.watch(turnoAbiertoProvider).value;
    final nube = ref.watch(estadoNubeProvider).value ?? '';

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f1): () => context.go(Pantalla.ventas.ruta)},
      child: Scaffold(
        backgroundColor: Estilo.fondo,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 210,
              color: Estilo.azul,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 4, 0, 14),
                    child: Center(child: EmmaLogo(version: EmmaLogoVersion.negativo, ancho: 150)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
                    child: Text(negocio?.nombre ?? '',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
                    child: Text('${sesion.nombre} (${sesion.esDueno ? 'dueño' : 'cajero'})',
                        style: const TextStyle(fontSize: 16, color: Estilo.textoSobreAzul)),
                  ),
                  // Con la ventana baja, el menú se desliza en vez de desbordarse.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in Pantalla.values)
                            if (sesion.esDueno || !p.soloDueno)
                              _ItemMenu(texto: p.titulo, activo: p == widget.pantalla, onTap: () => context.go(p.ruta)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      turno == null ? 'Caja cerrada' : 'Caja abierta desde ${formatoHoraPantalla(turno.apertura)}',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                  if (nube.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(nube, style: const TextStyle(fontSize: 13, color: Estilo.textoSobreAzul)),
                    ),
                  _ItemMenu(texto: 'Cerrar sesión', activo: false, onTap: () => ref.read(sesionProvider.notifier).salir()),
                ],
              ),
            ),
            Expanded(child: Padding(padding: const EdgeInsets.all(16), child: widget.child)),
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.texto, required this.activo, required this.onTap});

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: activo ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          border: activo ? const Border(left: BorderSide(color: Estilo.rojo, width: 4)) : null,
        ),
        child: ExcludeFocus(
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    texto,
                    style: TextStyle(fontSize: 17, color: Colors.white, fontWeight: activo ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
