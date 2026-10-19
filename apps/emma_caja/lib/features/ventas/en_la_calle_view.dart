import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import '../clientes/cliente_picker.dart';
import 'en_la_calle_view_model.dart';

/// Abre la lista de delivery en camino. [alCobrar] recibe cada venta cobrada
/// (para el ticket y la "última venta" de la pantalla de ventas) y devuelve el
/// aviso de la impresora.
Future<void> mostrarEnLaCalle(BuildContext context, {required Future<String?> Function(int ventaId) alCobrar}) =>
    showDialog<void>(context: context, builder: (_) => _EnLaCalleView(alCobrar: alCobrar));

class _EnLaCalleView extends ConsumerWidget {
  const _EnLaCalleView({required this.alCobrar});

  final Future<String?> Function(int ventaId) alCobrar;

  static String _tiempo(int minutos) => minutos < 60 ? '$minutos min' : '${minutos ~/ 60} h ${minutos % 60} min';

  Future<void> _cobrar(BuildContext context, WidgetRef ref) async {
    final vm = ref.read(enLaCalleViewModelProvider.notifier);
    final d = ref.read(enLaCalleViewModelProvider).value?.seleccionado;
    if (d == null) return informar(context, 'Escoja el pedido que llegó.');
    final pago = await showDialog<PagoDelivery>(
      context: context,
      builder: (_) => _CobroView(total: d.total, pagaCon: d.pedido.pagaCon, vm: vm),
    );
    if (pago == null || !context.mounted) return;
    VentaDetalle? venta;
    if (!await intentar(context, () async => venta = await vm.cobrar(d, pago)) || venta == null) return;
    final aviso = await alCobrar(venta!.venta.id);
    if (aviso != null && context.mounted) await avisar(context, aviso);
    if (venta!.venta.formaPago == FormaPago.efectivo && venta!.venta.devuelta > 0 && context.mounted) {
      await mostrarDevuelta(context, venta!.venta.devuelta);
    }
  }

  Future<void> _devolver(BuildContext context, WidgetRef ref) async {
    final d = ref.read(enLaCalleViewModelProvider).value?.seleccionado;
    if (d == null) return informar(context, 'Escoja el pedido que volvió.');
    final motivo = await pedirTexto(context, 'Volvió sin entregar', '¿Qué pasó?', valor: 'No estaba en la casa');
    if (motivo == null || !context.mounted) return;
    if (await intentar(context, () => ref.read(enLaCalleViewModelProvider.notifier).devolver(d, motivo)) && context.mounted) {
      await informar(context, '${TicketService.titulo(d.pedido)} volvió al mostrador. Desde ahí puede cambiarlo, mandarlo otra vez o cancelarlo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(enLaCalleViewModelProvider).value ?? const EnLaCalleState();
    final vm = ref.read(enLaCalleViewModelProvider.notifier);
    return Dialog(
      backgroundColor: Estilo.fondo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      child: SizedBox(
        width: 980,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text('Delivery en la calle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
              ),
              const TextoGris('Cuando el repartidor vuelva con el dinero, escoja el pedido y pulse "Entregado: cobrar".',
                  margen: EdgeInsets.fromLTRB(4, 0, 4, 8)),
              SizedBox(
                height: 380,
                child: Tabla<DeliveryEnCamino>(
                  altoFila: 44,
                  filas: s.lista,
                  escogida: s.escogida,
                  alEscoger: vm.escoger,
                  alAbrir: (_) => _cobrar(context, ref),
                  columnas: [
                    Columna('Cliente', (d) => d.pedido.nombreCliente ?? 'Pedido ${d.pedido.numero}', ancho: 170),
                    Columna('Dirección', (d) => d.pedido.direccion ?? ''),
                    Columna('Repartidor', (d) => d.pedido.repartidor ?? '-', ancho: 130),
                    Columna('Salió hace', (d) => _tiempo(d.minutos), ancho: 100),
                    Columna('Cobrar', (d) => formatoMonto(d.total), ancho: 110, derecha: true),
                    Columna('Cambio', (d) => d.cambio == null ? '' : formatoMonto(d.cambio!), ancho: 100, derecha: true),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(s.resumen, style: const TextStyle(fontSize: 16, color: Estilo.azul)),
              ),
              const SizedBox(height: 10),
              Wrap(
                children: [
                  Boton('Entregado: cobrar', tipo: TipoBoton.accion, anchoMinimo: 180, onPressed: () => _cobrar(context, ref)),
                  Boton('Volvió sin entregar', anchoMinimo: 160, onPressed: () => _devolver(context, ref)),
                  Boton('Reimprimir comanda', anchoMinimo: 160, onPressed: () async {
                    final d = s.seleccionado;
                    if (d == null) return;
                    final aviso = await vm.reimprimirComanda(d);
                    if (aviso != null && context.mounted) await avisar(context, aviso);
                  }),
                  Boton('Cerrar', anchoMinimo: 100, onPressed: () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Forma de pago, lo recibido y el cliente si es fiado para un delivery que
/// volvió. No guarda nada: eso lo hace "En la calle".
class _CobroView extends ConsumerStatefulWidget {
  const _CobroView({required this.total, this.pagaCon, required this.vm});

  final int total;
  final int? pagaCon;
  final EnLaCalleViewModel vm;

  @override
  ConsumerState<_CobroView> createState() => _CobroViewState();
}

class _CobroViewState extends ConsumerState<_CobroView> {
  final _recibido = TextEditingController();
  final _descuento = TextEditingController();
  var _forma = FormaPago.efectivo;
  Cliente? _cliente;
  var _credito = '';

  @override
  void initState() {
    super.initState();
    if (widget.pagaCon != null && widget.pagaCon! > 0) _recibido.text = formatoMonto(widget.pagaCon!).replaceAll(',', '');
    _recibido.selection = TextSelection(baseOffset: 0, extentOffset: _recibido.text.length);
    _recibido.addListener(() => setState(() {}));
    _descuento.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _recibido.dispose();
    _descuento.dispose();
    super.dispose();
  }

  int get _desc {
    final d = parsearMonto(_descuento.text) ?? 0;
    return d > 0 && d <= widget.total ? d : 0;
  }

  int get _total => widget.total - _desc;

  ({String texto, bool falta}) get _devuelta {
    final t = _recibido.text.trim();
    if (t.isEmpty) return (texto: formatoRD(0), falta: false);
    final r = parsearMonto(t);
    if (r != null && r >= _total) return (texto: formatoRD(r - _total), falta: false);
    return (texto: r == null ? '-' : 'Faltan ${formatoRD(_total - r)}', falta: true);
  }

  Future<void> _escogerCliente() async {
    final c = await escogerCliente(context, ref);
    if (c == null) return;
    final credito = await widget.vm.creditoDe(c.id, _total);
    setState(() {
      _cliente = c;
      _credito = credito;
    });
  }

  Future<void> _aceptar() async {
    int? recibido;
    if (_forma == FormaPago.efectivo && _recibido.text.trim().isNotEmpty) {
      recibido = parsearMonto(_recibido.text);
      if (recibido == null || recibido < _total) {
        await avisar(context, 'El monto recibido no alcanza.');
        return;
      }
    }
    if (_forma == FormaPago.fiado && _cliente == null) {
      await avisar(context, 'Escoja el cliente al que se le fía.');
      return;
    }
    if (mounted) {
      Navigator.pop(context, PagoDelivery(forma: _forma, recibido: recibido, descuento: _desc, clienteFiadoId: _cliente?.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _devuelta;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Total a pagar', style: TextStyle(fontSize: 18, color: Estilo.azul)),
                    const Spacer(),
                    Text(formatoRD(_total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Estilo.azul)),
                  ],
                ),
                const TextoGris('Forma de pago', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
                Row(
                  children: [
                    for (final f in FormaPago.values)
                      Expanded(
                        child: Boton(f.etiqueta,
                            tipo: _forma == f ? TipoBoton.principal : TipoBoton.normal,
                            alto: 46,
                            onPressed: () => setState(() => _forma = f)),
                      ),
                  ],
                ),
                if (_forma == FormaPago.efectivo) ...[
                  const TextoGris('Recibido (Enter = monto exacto)', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
                  Casilla(controller: _recibido, autofocus: true, derecha: true, tamano: 26, onSubmitted: (_) => _aceptar()),
                  Wrap(
                    children: [
                      for (final b in const [50, 100, 200, 500, 1000, 2000])
                        Boton(formatoMontoEntero(b * 100), anchoMinimo: 76, onPressed: () => _recibido.text = '$b'),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        const Text('Devuelta', style: TextStyle(fontSize: 20, color: Estilo.azul)),
                        const Spacer(),
                        Text(d.texto,
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: d.falta ? Estilo.rojo : Colors.black)),
                      ],
                    ),
                  ),
                ],
                if (_forma == FormaPago.fiado) ...[
                  const TextoGris('Cliente', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(_cliente?.nombre ?? 'Escoja el cliente',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                        ),
                      ),
                      Boton('Escoger', onPressed: _escogerCliente),
                    ],
                  ),
                  if (_credito.isNotEmpty) TextoGris(_credito),
                ],
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('Descuento', style: TextStyle(fontSize: 16, color: Estilo.azul)),
                    children: [Casilla(controller: _descuento, derecha: true)],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Boton('Cancelar', anchoMinimo: 120, onPressed: () => Navigator.pop(context)),
                    Boton('Cobrar', tipo: TipoBoton.principal, anchoMinimo: 160, tamano: 18, onPressed: _aceptar),
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

/// La devuelta en grande; se cierra con cualquier tecla o clic.
Future<void> mostrarDevuelta(BuildContext context, int devuelta) => showDialog<void>(
      context: context,
      builder: (c) => Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent) Navigator.pop(c);
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          onTap: () => Navigator.pop(c),
          child: Dialog(
            backgroundColor: Colors.white,
            child: SizedBox(
              width: 460,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('DEVUELTA', style: TextStyle(fontSize: 20, color: Estilo.azul)),
                    Text(formatoRD(devuelta), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w700, color: Estilo.azul)),
                    const SizedBox(height: 8),
                    const Text('Pulse cualquier tecla para seguir', style: TextStyle(fontSize: 16, color: Estilo.atenuado)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
