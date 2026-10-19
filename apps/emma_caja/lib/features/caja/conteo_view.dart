import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import 'conteo_view_model.dart';

/// El conteo para el cuadre: {denominación en pesos: cuántos} y las notas.
typedef ResultadoConteo = ({Map<int, int> conteo, String? notas});

/// Abre la ventana del conteo. null si cancelan.
Future<ResultadoConteo?> contarEfectivo(BuildContext context) => showDialog<ResultadoConteo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConteoView(),
    );

/// La ConteoWindow de la 0.7: cuántos billetes y monedas hay de cada uno; el
/// total se calcula solo.
class ConteoView extends ConsumerStatefulWidget {
  const ConteoView({super.key});

  @override
  ConsumerState<ConteoView> createState() => _ConteoViewState();
}

class _ConteoViewState extends ConsumerState<ConteoView> {
  final _textos = {for (final d in ConteoState.denominaciones) d: TextEditingController()};
  final _focos = <int, FocusNode>{};
  final _notas = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Al entrar a una casilla se marca todo, como en la 0.7.
    for (final d in ConteoState.denominaciones) {
      final t = _textos[d]!;
      final f = FocusNode();
      f.addListener(() {
        if (f.hasFocus) t.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
      });
      _focos[d] = f;
    }
  }

  @override
  void dispose() {
    for (final t in _textos.values) {
      t.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    _notas.dispose();
    super.dispose();
  }

  Future<void> _aceptar() async {
    final vm = ref.read(conteoViewModelProvider.notifier);
    final error = vm.revisar();
    if (error != null) {
      await avisar(context, error);
      _focos[ref.read(conteoViewModelProvider).malEscrita]?.requestFocus();
      return;
    }
    if (!await confirmar(context, vm.pregunta) || !mounted) return;
    Navigator.pop(context, vm.resultado);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(conteoViewModelProvider);
    final vm = ref.read(conteoViewModelProvider.notifier);
    const texto = TextStyle(fontSize: 16, color: Estilo.azul);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Cerrar caja: contar el efectivo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Escriba cuántos billetes y monedas hay de cada uno.', style: texto),
                ),
                for (final d in ConteoState.denominaciones)
                  Row(
                    children: [
                      Expanded(child: Text(ConteoState.etiqueta(d), style: texto)),
                      SizedBox(
                        width: 110,
                        child: Casilla(
                          controller: _textos[d],
                          foco: _focos[d],
                          autofocus: d == ConteoState.denominaciones.first,
                          derecha: true,
                          onChanged: (t) => vm.cambiar(d, t),
                          onSubmitted: (_) => _aceptar(),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(s.subtotalTexto(d), textAlign: TextAlign.right, style: texto),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Total contado', style: TextStyle(fontSize: 18, color: Estilo.azul))),
                      Text(s.totalTexto, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Estilo.azul)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text('Notas (opcional)', style: texto),
                ),
                Casilla(controller: _notas, lineas: 3, onChanged: vm.cambiarNotas),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Boton('Cancelar', anchoMinimo: 110, onPressed: () => Navigator.pop(context)),
                    Boton('Cerrar caja', tipo: TipoBoton.principal, anchoMinimo: 140, onPressed: _aceptar),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
