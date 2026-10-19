import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import 'delivery_view_model.dart';

/// Abre los datos de entrega del pedido. Devuelve true si salió con el repartidor.
Future<bool> mostrarDelivery(BuildContext context, int ticketId) async =>
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => DeliveryView(ticketId: ticketId)) ??
    false;

/// "Despachar" lo manda con el repartidor e imprime la comanda; "Guardar" lo
/// deja en el mostrador para seguir armándolo.
class DeliveryView extends ConsumerStatefulWidget {
  const DeliveryView({super.key, required this.ticketId});

  final int ticketId;

  @override
  ConsumerState<DeliveryView> createState() => _DeliveryViewState();
}

class _DeliveryViewState extends ConsumerState<DeliveryView> {
  final _telefono = TextEditingController();
  final _nombre = TextEditingController();
  final _direccion = TextEditingController();
  final _pagaCon = TextEditingController();
  final _envio = TextEditingController();
  final _repartidor = TextEditingController();
  final _focoTelefono = FocusNode();
  final _focoNombre = FocusNode();
  final _focoDireccion = FocusNode();
  var _cargado = false;
  var _ocupado = false;

  DeliveryViewModel get _vm => ref.read(deliveryViewModelProvider(widget.ticketId).notifier);

  @override
  void initState() {
    super.initState();
    _focoTelefono.addListener(() {
      if (!_focoTelefono.hasFocus) _buscar();
    });
    for (final c in [_envio, _pagaCon]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_telefono, _nombre, _direccion, _pagaCon, _envio, _repartidor]) {
      c.dispose();
    }
    for (final f in [_focoTelefono, _focoNombre, _focoDireccion]) {
      f.dispose();
    }
    super.dispose();
  }

  void _llenar(DeliveryState s) {
    _telefono.text = s.telefono;
    _nombre.text = s.nombre;
    _direccion.text = s.direccion;
    if (!_cargado) {
      _pagaCon.text = s.pedido.pagaCon == null ? '' : _texto(s.pedido.pagaCon!);
      _envio.text = _texto(s.envio);
      _repartidor.text = s.pedido.repartidor ?? (s.repartidores.isEmpty ? '' : s.repartidores.first);
      _cargado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (_telefono.text.isEmpty ? _focoTelefono : _focoDireccion).requestFocus();
      });
    }
  }

  static String _texto(int c) => c % 100 == 0 ? '${c ~/ 100}' : formatoMonto(c).replaceAll(',', '');

  Future<void> _buscar() =>
      _vm.buscarTelefono(telefono: _telefono.text, nombre: _nombre.text, direccion: _direccion.text);

  Future<void> _guardar({required bool despachar}) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final r = await _vm.guardar(
      nombre: _nombre.text,
      telefono: _telefono.text,
      direccion: _direccion.text,
      pagaCon: _pagaCon.text,
      envio: _envio.text,
      repartidor: _repartidor.text,
      despachar: despachar,
    );
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r.aviso != null) await avisar(context, r.aviso!);
    if (r.listo && mounted) Navigator.pop(context, despachar);
  }

  String _cobrarTexto(DeliveryState s) {
    final envio = parsearMonto(_envio.text) ?? 0;
    final total = s.subtotal + (envio < 0 ? 0 : envio);
    var t = 'Cobrar: ${formatoRD(total)}';
    final paga = parsearMonto(_pagaCon.text);
    if (paga != null && paga > total) t += '   ·   Cambio: ${formatoRD(paga - total)}';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deliveryViewModelProvider(widget.ticketId), (_, v) {
      if (v.value != null) _llenar(v.value!);
    });
    final estado = ref.watch(deliveryViewModelProvider(widget.ticketId));
    final s = estado.value;
    if (s != null && !_cargado) _llenar(s);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context, false)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 560,
          child: s == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: estado.hasError ? Text('${estado.error}') : const Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text('Delivery', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                      ),
                      TextoGris(s.aviso, margen: const EdgeInsets.fromLTRB(4, 0, 4, 6)),
                      FilaCampo(
                        etiqueta: 'Teléfono',
                        child: Casilla(controller: _telefono, foco: _focoTelefono, tamano: 18, onSubmitted: (_) async {
                          await _buscar();
                          _focoNombre.requestFocus();
                        }),
                      ),
                      FilaCampo(etiqueta: 'Nombre', child: Casilla(controller: _nombre, foco: _focoNombre, tamano: 18)),
                      FilaCampo(
                        etiqueta: 'Dirección y referencia',
                        child: Casilla(controller: _direccion, foco: _focoDireccion, lineas: 3),
                      ),
                      FilaCampo(etiqueta: 'Paga con RD\$', child: Casilla(controller: _pagaCon, derecha: true, tamano: 18)),
                      FilaCampo(etiqueta: 'Envío RD\$', child: Casilla(controller: _envio, derecha: true, tamano: 18)),
                      FilaCampo(
                        etiqueta: 'Repartidor',
                        child: Row(
                          children: [
                            Expanded(child: Casilla(controller: _repartidor, tamano: 18)),
                            if (s.repartidores.isNotEmpty)
                              PopupMenuButton<String>(
                                tooltip: 'Escoger repartidor',
                                icon: const Icon(Icons.arrow_drop_down, color: Estilo.azul),
                                onSelected: (r) => _repartidor.text = r,
                                itemBuilder: (_) => [for (final r in s.repartidores) PopupMenuItem(value: r, child: Text(r))],
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(_cobrarTexto(s), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Estilo.azul)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          Boton('Cancelar', anchoMinimo: 100, onPressed: () => Navigator.pop(context, false)),
                          if (s.pedido.esDelivery)
                            Boton('Ya no es delivery', anchoMinimo: 140, onPressed: () async {
                              if (await intentar(context, _vm.quitarDelivery) && context.mounted) Navigator.pop(context, false);
                            }),
                          Boton('Guardar sin despachar', anchoMinimo: 160, onPressed: _ocupado ? null : () => _guardar(despachar: false)),
                          Boton('Despachar e imprimir comanda',
                              tipo: TipoBoton.accion, anchoMinimo: 240, onPressed: _ocupado ? null : () => _guardar(despachar: true)),
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
