import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import 'cliente_formulario.dart';
import 'cliente_picker_view_model.dart';

/// Escoger un cliente de la lista buscando por nombre o teléfono (los fijos
/// primero), con "Nuevo cliente". Devuelve el escogido, o null si cancelan.
Future<Cliente?> escogerCliente(BuildContext context, WidgetRef ref, {String texto = ''}) => showDialog<Cliente>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Picker(texto: texto),
    );

/// El ClientePicker de la 0.7.
class _Picker extends ConsumerStatefulWidget {
  const _Picker({required this.texto});

  final String texto;

  @override
  ConsumerState<_Picker> createState() => _PickerEstado();
}

class _PickerEstado extends ConsumerState<_Picker> {
  // Nombre y detalle, con el alto de línea de la letra (se calcula al dibujar).
  var _altoFila = 54.0;

  late final _buscar = TextEditingController(text: widget.texto)
    ..selection = TextSelection.collapsed(offset: widget.texto.length);
  late final _focoBuscar = FocusNode(onKeyEvent: _teclaBuscar);
  final _focoLista = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _buscar.dispose();
    _focoBuscar.dispose();
    _focoLista.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ClientePickerViewModel get _vm => ref.read(clientePickerViewModelProvider(widget.texto).notifier);
  ClientePickerState? get _estado => ref.read(clientePickerViewModelProvider(widget.texto)).value;

  void _aceptar() {
    final c = _estado?.seleccionado;
    if (c != null) Navigator.pop(context, c);
  }

  Future<void> _nuevo() async {
    final c = await editarCliente(context, ref, _vm.datosNuevo(_buscar.text));
    if (c != null && mounted) Navigator.pop(context, c);
  }

  // Flecha abajo pasa a la lista.
  KeyEventResult _teclaBuscar(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    if (_estado?.clientes.isNotEmpty != true) return KeyEventResult.ignored;
    _vm.escoger(0);
    _mostrar(0);
    _focoLista.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _teclaLista(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final s = _estado;
    if (s == null || s.clientes.isEmpty) return KeyEventResult.ignored;
    final i = s.escogido ?? 0;
    final n = s.clientes.length;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final otro = (i + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, n - 1);
      _vm.escoger(otro);
      _mostrar(otro);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _aceptar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _mostrar(int i) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final arriba = i * _altoFila;
    final abajo = arriba + _altoFila;
    if (arriba < p.pixels) {
      _scroll.jumpTo(arriba);
    } else if (abajo > p.pixels + p.viewportDimension) {
      _scroll.jumpTo((abajo - p.viewportDimension).clamp(0, p.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = clientePickerViewModelProvider(widget.texto);
    // Lista nueva al escribir: vuelve arriba, como la 0.7.
    ref.listen(proveedor, (antes, ahora) {
      if (!identical(antes?.value?.clientes, ahora.value?.clientes) && _scroll.hasClients) _scroll.jumpTo(0);
    });
    final s = ref.watch(proveedor).value;
    final clientes = s?.clientes ?? const <Cliente>[];
    final escala = MediaQuery.textScalerOf(context);
    _altoFila = 8 + (escala.scale(16) + escala.scale(13)) * 1.6;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 620,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Escoger cliente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                ),
                const Text('Nombre o teléfono', style: TextStyle(fontSize: 16, color: Estilo.atenuado)),
                Casilla(
                  controller: _buscar,
                  foco: _focoBuscar,
                  autofocus: true,
                  tamano: 18,
                  margen: const EdgeInsets.only(top: 4, bottom: 6),
                  onChanged: (t) => _vm.buscar(t),
                  onSubmitted: (_) => _aceptar(),
                ),
                // 360 de alto como la 0.7; en una pantalla baja se encoge para que quepan los botones.
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 360),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Estilo.borde)),
                    child: Focus(
                      focusNode: _focoLista,
                      onKeyEvent: _teclaLista,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: clientes.length,
                        itemExtent: _altoFila,
                        itemBuilder: (context, i) => _Fila(
                          cliente: clientes[i],
                          escogida: i == s?.escogido,
                          alTocar: () {
                            _focoLista.requestFocus();
                            _vm.escoger(i);
                          },
                          alAbrir: () {
                            _vm.escoger(i);
                            _aceptar();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      Boton('Nuevo cliente', anchoMinimo: 130, onPressed: _nuevo),
                      Boton('Cancelar', anchoMinimo: 100, onPressed: () => Navigator.pop(context)),
                      Boton('Escoger', tipo: TipoBoton.principal, anchoMinimo: 110, onPressed: _aceptar),
                    ],
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

/// Un cliente de la lista: el nombre y debajo teléfono · dirección · sector.
class _Fila extends StatelessWidget {
  const _Fila({required this.cliente, required this.escogida, required this.alTocar, required this.alAbrir});

  final Cliente cliente;
  final bool escogida;
  final VoidCallback alTocar;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: alTocar,
        onDoubleTap: alAbrir,
        child: Container(
          color: escogida ? Estilo.seleccionTabla : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(ClientePickerState.titulo(cliente),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              Text(ClientePickerState.detalle(cliente),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Estilo.atenuado)),
            ],
          ),
        ),
      );
}
