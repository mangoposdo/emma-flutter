import 'dart:async';

import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../clientes/cliente_picker.dart';
import '../productos/producto_formulario.dart';
import 'delivery_view.dart';
import 'en_la_calle_view.dart';
import 'ventas_state.dart';
import 'ventas_view_model.dart';

/// La pantalla de venta de la 0.7: pedidos arriba, escanear y la lista a la
/// izquierda, el total y el cobro a la derecha, las teclas abajo.
class VentasView extends ConsumerStatefulWidget {
  const VentasView({super.key});

  @override
  ConsumerState<VentasView> createState() => _VentasViewState();
}

class _VentasViewState extends ConsumerState<VentasView> {
  final _codigo = TextEditingController();
  final _cantidad = TextEditingController();
  final _cliente = TextEditingController();
  final _recibido = TextEditingController();
  final _focoCodigo = FocusNode();
  final _focoCantidad = FocusNode();
  final _focoCliente = FocusNode();
  final _focoRecibido = FocusNode();
  Timer? _reloj;
  var _hora = DateTime.now();
  final _listaCodigo = ScrollController();
  var _avisosMostrados = false;

  VentasViewModel get _vm => ref.read(ventasViewModelProvider.notifier);
  VentasState? get _s => ref.read(ventasViewModelProvider).value;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _hora = DateTime.now()));
    _focoCliente.addListener(() {
      if (!_focoCliente.hasFocus && _s != null) _vm.clienteSalio();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _listaCodigo.dispose();
    for (final c in [_codigo, _cantidad, _cliente, _recibido]) {
      c.dispose();
    }
    for (final f in [_focoCodigo, _focoCantidad, _focoCliente, _focoRecibido]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _avisosAlEntrar() async {
    if (_avisosMostrados) return;
    _avisosMostrados = true;
    final aviso = _vm.avisoAlCargar;
    if (aviso != null) await avisar(context, aviso);
    if (await _vm.cajaCerrada() && mounted) {
      await avisar(context, 'La caja está cerrada. Vaya a "Caja y cuadre" para abrirla antes de vender.');
    }
    _alCodigo();
  }

  void _alCodigo({bool marcar = false}) {
    if (!mounted) return;
    _focoCodigo.requestFocus();
    if (marcar) _codigo.selection = TextSelection(baseOffset: 0, extentOffset: _codigo.text.length);
  }

  Future<void> _mostrar(String? aviso) async {
    if (aviso != null && mounted) await avisar(context, aviso);
  }

  // ---------- Escanear ----------

  Future<void> _entrarCodigo() async {
    final s = _s;
    if (s == null) return;
    // Con uno marcado en la lista (flechas), Enter escoge ese.
    if (s.busqueda.isNotEmpty && s.marcado >= 0) {
      await _escoger(s.busqueda[s.marcado]);
      return;
    }
    final texto = _codigo.text;
    final r = await _vm.entrarCodigo(texto);
    if (!mounted) return;
    switch (r) {
      case Listo():
        _codigo.clear();
        _alCodigo();
      case IrACobrar():
        if (_s!.forma == FormaPago.efectivo) {
          _focoRecibido.requestFocus();
          _recibido.selection = TextSelection(baseOffset: 0, extentOffset: _recibido.text.length);
        } else {
          await _cobrar();
        }
      case PedirLibras():
        _pasarALibras();
      case EscogerDeLista():
        _alCodigo();
      case NoEncontrado(:final mensaje, :final codigo, :final ofrecerCrear, :final cantidad):
        SystemSound.play(SystemSoundType.alert);
        if (ofrecerCrear && await confirmar(context, mensaje) && mounted) {
          final p = await editarProducto(context, ref, codigo: codigo);
          if (p != null && mounted) {
            final r2 = await _vm.elegir(p, cantidad: cantidad);
            if (r2 is PedirLibras) {
              _pasarALibras();
              return;
            }
            _codigo.clear();
            _alCodigo();
            return;
          }
        } else if (!ofrecerCrear) {
          await avisar(context, mensaje);
        }
        _alCodigo(marcar: true);
      case Aviso(:final mensaje):
        await avisar(context, mensaje);
        _alCodigo(marcar: true);
    }
  }

  Future<void> _escoger(Producto p) async {
    final r = await _vm.elegir(p);
    if (!mounted) return;
    if (r is PedirLibras) {
      _pasarALibras();
    } else {
      if (r is Aviso) await avisar(context, r.mensaje);
      _codigo.clear();
      _alCodigo();
    }
  }

  /// Muestra el producto por libra y pasa a la casilla de cantidad.
  void _pasarALibras() {
    final p = _s?.pendiente;
    if (p == null) return;
    _codigo.text = p.nombre;
    _cantidad.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focoCantidad.requestFocus();
    });
  }

  void _limpiarLibras() {
    _vm.limpiarPendiente();
    _cantidad.clear();
    _codigo.clear();
    _alCodigo();
  }

  Future<void> _entrarCantidad() async {
    final error = await _vm.entrarCantidad(_cantidad.text);
    if (!mounted) return;
    if (error != null) {
      await avisar(context, error);
      _focoCantidad.requestFocus();
      _cantidad.selection = TextSelection(baseOffset: 0, extentOffset: _cantidad.text.length);
      return;
    }
    _cantidad.clear();
    _codigo.clear();
    _alCodigo();
  }

  /// Mueve la lista para que se vea el marcado con las flechas.
  void _verMarcado() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _s?.marcado ?? -1;
      if (i < 0 || !_listaCodigo.hasClients) return;
      final pos = _listaCodigo.position;
      final arriba = i * _altoFila;
      if (arriba < pos.pixels) {
        _listaCodigo.jumpTo(arriba);
      } else if (arriba + _altoFila > pos.pixels + pos.viewportDimension) {
        _listaCodigo.jumpTo(arriba + _altoFila - pos.viewportDimension);
      }
    });
  }

  void _cerrarBusqueda() {
    _vm.cerrarBusqueda();
    _alCodigo(marcar: true);
  }

  // ---------- Teclas ----------

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final s = _s;
    if (s == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    void hacer(Future<void> Function() accion) => unawaited(accion());

    if (k == LogicalKeyboardKey.f4) {
      hacer(_cambiarCantidad);
    } else if (k == LogicalKeyboardKey.f6) {
      hacer(_nuevoPedido);
    } else if (k == LogicalKeyboardKey.f7) {
      _irACliente();
    } else if (k == LogicalKeyboardKey.f8) {
      hacer(_ventaSuelta);
    } else if (k == LogicalKeyboardKey.f9) {
      hacer(_delivery);
    } else if (k == LogicalKeyboardKey.f10) {
      hacer(_cobrar);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_focoCliente.hasFocus || _focoRecibido.hasFocus) {
        _alCodigo();
      } else if (s.busqueda.isNotEmpty) {
        _cerrarBusqueda();
      } else if (s.pendiente != null) {
        _limpiarLibras();
      } else {
        hacer(_cancelar);
      }
    } else if (k == LogicalKeyboardKey.delete) {
      final enOtra = _focoCantidad.hasFocus || _focoCliente.hasFocus || _focoRecibido.hasFocus;
      if (enOtra || (_focoCodigo.hasFocus && _codigo.text.isNotEmpty)) return KeyEventResult.ignored;
      hacer(() => _vm.quitar());
    } else if ((k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) && s.busqueda.isNotEmpty) {
      _vm.moverMarca(k == LogicalKeyboardKey.arrowDown ? 1 : -1);
      _verMarcado();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _irACliente() {
    _focoCliente.requestFocus();
    _cliente.selection = TextSelection(baseOffset: 0, extentOffset: _cliente.text.length);
  }

  // ---------- Acciones ----------

  Future<void> _cambiarCantidad() async {
    final i = _vm.lineaParaCantidad();
    if (i == null) return;
    final l = _s!.lineas[i];
    if (l.porPasos) {
      final n =
          await pedirCantidad(context, 'Cantidad', l.producto.nombre, valor: l.cantidad, minimo: milesimasPorUnidad);
      if (n != null) await _mostrar(await _vm.cambiarCantidad(i, formatoCantidad(n)));
    } else if (l.precioLibre != null) {
      final m = await pedirMonto(context, l.producto.nombre, 'Monto RD\$', valor: l.precioLibre, minimo: 1);
      if (m != null) await _mostrar(await _vm.cambiarCantidad(i, formatoMonto(m)));
    } else {
      await _pedirLibras(i, l);
    }
    _alCodigo();
  }

  /// Pregunta libras o un monto en pesos ("$50" = 50 pesos de queso).
  Future<void> _pedirLibras(int i, LineaCarrito l) async {
    await Formulario('${l.producto.nombre} (${formatoRD(l.producto.precio)} la libra)', ancho: 460)
        .texto('v', 'Libras', valor: formatoCantidad(l.cantidad), requerido: true)
        .nota('Escriba las libras (ej. 0.5) o el monto en pesos con \$ delante (ej. \$50).')
        .mostrar(context, alAceptar: (v) async {
      final error = await _vm.cambiarCantidad(i, v.txt('v'));
      if (error != null) throw EmmaError(error);
    });
  }

  Future<void> _ventaSuelta() async {
    final m = await pedirMonto(
      context,
      'Venta suelta',
      'Monto RD\$',
      nota:
          'Para cobrar algo sin escoger el producto. Sale como "Varios" en el ticket. También puede escribir \$50 en la casilla del código.',
      minimo: 1,
    );
    if (m != null) await _mostrar(await _vm.agregarSuelto(m));
    _alCodigo();
  }

  Future<void> _nuevoPedido() async {
    _cantidad.clear();
    _codigo.clear();
    await _vm.nuevoPedido();
    _alCodigo();
  }

  Future<void> _cambiarAPedido(int id) async {
    _cantidad.clear();
    _codigo.clear();
    await _mostrar(await _vm.cambiarAPedido(id));
    _alCodigo();
  }

  Future<void> _cancelar() async {
    final s = _s!;
    if (s.lineas.isNotEmpty && !await confirmar(context, '¿Cancelar este pedido y vaciar la lista?')) return;
    await _vm.cancelarPedido();
    _codigo.clear();
    _alCodigo();
  }

  Future<void> _entrarCliente() async {
    final parecidos = await _vm.entrarCliente();
    if (parecidos.length > 1 && mounted) {
      final c = await escogerCliente(context, ref, texto: _s!.clienteTexto.trim());
      if (c != null) await _vm.ligarCliente(c);
    }
    _alCodigo();
  }

  Future<void> _buscarCliente() async {
    final s = _s!;
    final texto = s.clienteTexto.trim() == s.clienteNombre ? '' : s.clienteTexto.trim();
    final c = await escogerCliente(context, ref, texto: texto);
    if (c != null) await _vm.ligarCliente(c);
    _alCodigo();
  }

  Future<void> _descuento() async {
    final s = _s!;
    if (s.lineas.isEmpty) return _alCodigo();
    final d = await pedirMonto(
      context,
      'Descuento',
      'Monto RD\$',
      valor: s.descuento > 0 ? s.descuento : null,
      nota: 'Se le resta al total de ${formatoRD(s.subtotal)}. Escriba 0 para quitarlo.',
    );
    if (d != null) await _mostrar(_vm.fijarDescuento(d));
    _alCodigo();
  }

  Future<void> _cobrar() async {
    final s = _s;
    if (s == null) return;
    if (s.pendiente != null) {
      _vm.limpiarPendiente();
      _cantidad.clear();
      _codigo.clear();
    }
    if (s.lineas.isEmpty) return _alCodigo();
    if (_vm.faltaClienteFiado) {
      final c = await escogerCliente(context, ref, texto: s.clienteTexto.trim());
      if (c != null) await _vm.ligarCliente(c);
      if (_vm.faltaClienteFiado) {
        if (mounted) await avisar(context, 'Escoja el cliente al que se le fía.');
        return;
      }
    }
    final r = await _vm.cobrar();
    if (!mounted) return;
    if (r.aviso != null) {
      await avisar(context, r.aviso!);
      if (r.aviso == 'Con lo que paga no alcanza.') {
        _focoRecibido.requestFocus();
        _recibido.selection = TextSelection(baseOffset: 0, extentOffset: _recibido.text.length);
      } else {
        _alCodigo();
      }
      return;
    }
    if (r.ventaId != null) {
      _codigo.clear();
      _alCodigo();
      await _mostrar(await _vm.despuesDeVenta(r.ventaId!));
    }
    _alCodigo();
  }

  Future<void> _delivery() async {
    if (_s?.pendiente != null) _limpiarLibras();
    final id = await _vm.pedidoParaDelivery();
    if (!mounted) return;
    final despachado = await mostrarDelivery(context, id);
    await _vm.recargar(pedidoNuevo: despachado);
    _alCodigo();
  }

  Future<void> _enLaCalle() async {
    if (_s?.pendiente != null) _limpiarLibras();
    await _vm.guardarActual();
    if (!mounted) return;
    await mostrarEnLaCalle(context, alCobrar: (ventaId) => _vm.despuesDeVenta(ventaId));
    // Un pedido devuelto vuelve al mostrador.
    await _vm.recargar();
    _alCodigo();
  }

  void _sincronizar(TextEditingController c, String valor) {
    if (c.text != valor) c.text = valor;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ventasViewModelProvider.select((v) => v.value?.clienteTexto), (_, t) {
      if (t != null && !_focoCliente.hasFocus) _sincronizar(_cliente, t);
    });
    ref.listen(ventasViewModelProvider.select((v) => v.value?.recibidoTexto), (_, t) {
      if (t != null && !_focoRecibido.hasFocus) _sincronizar(_recibido, t);
    });
    final estado = ref.watch(ventasViewModelProvider);
    final s = estado.value;
    if (s == null) {
      return estado.hasError
          ? Center(child: Text('No se pudo cargar la venta: ${estado.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    if (!_avisosMostrados) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sincronizar(_cliente, s.clienteTexto);
        _sincronizar(_recibido, s.recibidoTexto);
        _avisosAlEntrar();
      });
    }

    return Focus(
      onKeyEvent: _tecla,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _barraPedidos(s),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _izquierda(s)),
                const SizedBox(width: 20),
                SizedBox(width: 400, child: _derecha(s)),
              ],
            ),
          ),
          _barraTeclas(),
        ],
      ),
    );
  }

  // ---------- Barra de arriba: pedidos abiertos ----------

  Widget _barraPedidos(VentasState s) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Estilo.azul, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in s.pedidos) _pestana(p),
                  BotonRedondo(
                    onPressed: _nuevoPedido,
                    fondo: Colors.transparent,
                    borde: Estilo.nuevoPedidoBorde,
                    letra: Colors.white,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('+ Nuevo pedido'),
                      SizedBox(width: 10),
                      Text('F6', style: TextStyle(fontWeight: FontWeight.w400, color: Estilo.textoSobreAzul)),
                    ]),
                  ),
                ],
              ),
            ),
            BotonRedondo(
              onPressed: _enLaCalle,
              texto: 'En la calle (${s.enLaCalle})',
              fondo: Estilo.botonCalle,
              letra: Colors.white,
              grosorBorde: 0,
              tamano: 14,
              peso: s.enLaCalle > 0 ? FontWeight.w700 : FontWeight.w400,
              mensaje: 'Delivery que van en camino: cobrar cuando vuelvan',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
              child: Text(formatoHoraCorta(_hora), style: const TextStyle(fontSize: 15, color: Estilo.textoSobreAzul)),
            ),
          ],
        ),
      );

  Widget _pestana(PestanaPedido p) => BotonRedondo(
        onPressed: p.id == null ? _alCodigo : () => _cambiarAPedido(p.id!),
        fondo: p.actual ? Colors.white : Colors.transparent,
        letra: p.actual ? Estilo.azul : Colors.white,
        borde: Estilo.pestanaBorde,
        grosorBorde: p.actual ? 0 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.titulo, style: TextStyle(fontWeight: p.actual ? FontWeight.w700 : FontWeight.w600)),
            if (p.detalle.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(p.detalle,
                  style: TextStyle(fontWeight: FontWeight.w400, color: p.actual ? Estilo.gris : Estilo.textoSobreAzul)),
            ],
          ],
        ),
      );

  // ---------- Izquierda: escanear y carrito ----------

  Widget _izquierda(VentasState s) {
    final p = s.pendiente;
    final porLibra = p?.unidad == UnidadVenta.libra;
    final columna = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TapRegion(
                groupId: _grupoCodigo,
                child: Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Estilo.azul, width: 3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const _CodigoDeBarras(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _codigo,
                          focusNode: _focoCodigo,
                          autofocus: true,
                          onTapOutside: (_) {},
                          onEditingComplete: () {},
                          onChanged: (t) => _vm.sugerir(t),
                          onSubmitted: (_) => _entrarCodigo(),
                          style: const TextStyle(fontSize: 24, color: Estilo.azul),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            hintText: 'Escanee o escriba el producto',
                            hintStyle: TextStyle(fontSize: 24, color: Estilo.marcador),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            border: Border.all(color: Estilo.bordeSuave), borderRadius: BorderRadius.circular(6)),
                        child: const Text('Enter ↵',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Estilo.gris)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 150,
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Estilo.bordeSuave, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(porLibra ? 'LIBRAS O \$MONTO' : 'CANTIDAD (F4)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Estilo.gris)),
                  SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _cantidad,
                      focusNode: _focoCantidad,
                      enabled: p != null,
                      textAlign: TextAlign.right,
                      textAlignVertical: TextAlignVertical.center,
                      onEditingComplete: () {},
                      onSubmitted: (_) => _entrarCantidad(),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Estilo.azul),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Text(
            p == null
                ? ' '
                : '${p.nombre}   ${formatoRD(p.precio)}${porLibra ? ' la libra' : ''}   ·   Hay ${formatoCantidadUnidad(p.existencia, p.unidad)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Estilo.azul),
          ),
        ),
        Expanded(child: _carrito(s)),
      ],
    );
    return Stack(children: [columna, if (s.busqueda.isNotEmpty) _busqueda(s)]);
  }

  static const _columnas = [40.0, 0.0, 160.0, 100.0, 110.0, 52.0];

  Widget _fila(List<Widget> celdas) => Row(
        children: [
          for (var i = 0; i < celdas.length; i++)
            _columnas[i] == 0 ? Expanded(child: celdas[i]) : SizedBox(width: _columnas[i], child: celdas[i]),
        ],
      );

  Widget _carrito(VentasState s) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Estilo.linea))),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Estilo.gris),
                child: _fila(const [
                  Text('#'),
                  Text('PRODUCTO'),
                  Center(child: Text('CANTIDAD')),
                  Align(alignment: Alignment.centerRight, child: Text('PRECIO')),
                  Align(alignment: Alignment.centerRight, child: Text('TOTAL')),
                  SizedBox(),
                ]),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: s.lineas.length,
                itemExtent: 58,
                itemBuilder: (_, i) => _lineaCarrito(s, i),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Estilo.linea))),
              child: Row(
                children: [
                  const Text('Cliente:', style: TextStyle(fontSize: 15, color: Estilo.gris)),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Nombre o teléfono. Con Enter se busca en la lista de clientes. Vacío = mostrador.',
                    child: Container(
                      width: 226,
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Estilo.suave,
                        border: Border.all(color: Estilo.bordeSuave),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: _cliente,
                        focusNode: _focoCliente,
                        maxLength: 60,
                        onEditingComplete: () {},
                        onChanged: _vm.escribirCliente,
                        onSubmitted: (_) => _entrarCliente(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Estilo.azul),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  BotonRedondo(
                      onPressed: _buscarCliente,
                      texto: 'Buscar (F7)',
                      alto: 40,
                      tamano: 14,
                      mensaje: 'Escoger de la lista de clientes'),
                  const SizedBox(width: 12),
                  // Si no cabe, la última venta y sus botones bajan a otra línea.
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 4,
                      children: [
                        if (s.ultimaVentaTexto.isNotEmpty)
                          Text(s.ultimaVentaTexto, style: const TextStyle(fontSize: 15, color: Estilo.gris)),
                        BotonRedondo(
                          onPressed: s.ultimaVentaId == null ? null : () async => _mostrar(await _vm.reimprimir()),
                          texto: 'Reimprimir',
                          fondo: Colors.transparent,
                          grosorBorde: 0,
                          relleno: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        if (s.ticketsPendientes > 0)
                          BotonRedondo(
                            onPressed: () async {
                              await _mostrar(await _vm.imprimirPendientes());
                              _alCodigo();
                            },
                            texto: s.ticketsPendientes == 1
                                ? 'Imprimir 1 ticket pendiente'
                                : 'Imprimir ${s.ticketsPendientes} tickets pendientes',
                            fondo: Estilo.amarillo,
                            borde: Estilo.amarilloBorde,
                            tamano: 14,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _lineaCarrito(VentasState s, int i) {
    final l = s.lineas[i];
    final escogida = i == s.seleccionada;
    Widget paso(String signo, int n) => BotonRedondo(
          onPressed: () async {
            _vm.seleccionar(i);
            if (l.porPasos) {
              await _vm.paso(i, n);
            } else {
              await _cambiarCantidad();
            }
            _alCodigo();
          },
          texto: signo,
          ancho: 44,
          alto: 40,
          tamano: 22,
          relleno: EdgeInsets.zero,
          mensaje: n > 0 ? 'Uno más' : 'Uno menos',
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _vm.seleccionar(i);
        _alCodigo();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: escogida ? Estilo.seleccion : Colors.white,
          border: const Border(bottom: BorderSide(color: Estilo.lineaFila)),
        ),
        child: _fila([
          Text('${i + 1}', style: const TextStyle(fontSize: 15, color: Estilo.gris)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.producto.nombre,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul),
                  overflow: TextOverflow.ellipsis),
              if (l.producto.codigo != null && !esServicio(l.producto))
                Text(l.producto.codigo!, style: const TextStyle(fontSize: 12, color: Estilo.gris)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              paso('−', -1),
              SizedBox(
                width: 62,
                child: Text(l.cantidadTexto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Estilo.azul)),
              ),
              paso('+', 1),
            ],
          ),
          Text(formatoMonto(l.precio),
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, color: Estilo.gris)),
          Text(formatoMonto(l.total),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Estilo.azul)),
          Align(
            alignment: Alignment.centerRight,
            child: BotonRedondo(
              onPressed: () async {
                await _vm.quitar(i);
                _alCodigo();
              },
              fondo: Colors.transparent,
              grosorBorde: 0,
              ancho: 44,
              alto: 40,
              relleno: EdgeInsets.zero,
              mensaje: 'Quitar',
              child: const Icon(Icons.delete_outline, color: Estilo.rojoOscuro, size: 22),
            ),
          ),
        ]),
      ),
    );
  }

  /// La casilla del código y su lista: tocar fuera de las dos cierra la lista.
  static const _grupoCodigo = #casillaDelCodigo;
  static const _altoFila = 44.0;

  /// La lista de productos que sale debajo de la casilla del código, del
  /// ancho de la casilla. Un toque escoge; las flechas marcan para Enter.
  Widget _busqueda(VentasState s) => Positioned(
        top: 72,
        left: 0,
        right: 162,
        child: TapRegion(
          groupId: _grupoCodigo,
          onTapOutside: (_) => _vm.cerrarBusqueda(),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Estilo.azul, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                // Cada búsqueda nueva empieza arriba.
                key: ObjectKey(s.busqueda),
                controller: _listaCodigo,
                shrinkWrap: true,
                itemExtent: _altoFila,
                itemCount: s.busqueda.length,
                itemBuilder: (_, i) {
                  final p = s.busqueda[i];
                  return InkWell(
                    onTap: () => _escoger(p),
                    child: Container(
                      color: i == s.marcado ? Estilo.seleccionTabla : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(p.nombre,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 18, color: Estilo.azul),
                                  overflow: TextOverflow.ellipsis)),
                          Text('Hay ${formatoCantidad(p.existencia)}',
                              style: const TextStyle(fontSize: 18, color: Estilo.atenuado)),
                          const SizedBox(width: 24),
                          Text(formatoRD(p.precio),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

  // ---------- Derecha: total y cobro ----------

  Widget _derecha(VentasState s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(color: Estilo.azul, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL A COBRAR',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Estilo.textoSobreAzul)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatoRD(s.total),
                      style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                Text(s.articulosTexto, style: const TextStyle(fontSize: 15, color: Estilo.textoSobreAzul)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: SingleChildScrollView(child: _panelCobro(s))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(3, 10, 3, 0),
                    child: BotonRedondo(
                      onPressed: _cobrar,
                      alto: 76,
                      fondo: Estilo.rojo,
                      grosorBorde: 0,
                      letra: Colors.white,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('COBRAR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                          Container(
                            margin: const EdgeInsets.only(left: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Estilo.rojoOscuro, borderRadius: BorderRadius.circular(6)),
                            child: const Text('F10', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _panelCobro(VentasState s) {
    final d = s.devuelta;
    final verde = d.falta ? Estilo.rojo : Estilo.verde;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Rotulo('CÓMO PAGA'),
        Row(
          children: [
            for (final (f, texto) in const [
              (FormaPago.efectivo, 'Efectivo'),
              (FormaPago.tarjeta, 'Tarjeta'),
              (FormaPago.transferencia, 'Transfer.'),
              (FormaPago.fiado, 'Fiado'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: BotonRedondo(
                    onPressed: () async {
                      await _vm.elegirForma(f);
                      _alCodigo();
                    },
                    texto: texto,
                    alto: 48,
                    relleno: EdgeInsets.zero,
                    grosorBorde: 2,
                    fondo: s.forma == f ? Estilo.azul : Colors.white,
                    borde: s.forma == f ? Estilo.azul : Estilo.bordeSuave,
                    letra: s.forma == f ? Colors.white : Estilo.azul,
                    peso: s.forma == f ? FontWeight.w700 : FontWeight.w600,
                    mensaje: f == FormaPago.transferencia ? 'Transferencia' : null,
                  ),
                ),
              ),
          ],
        ),
        if (s.forma == FormaPago.efectivo) ...[
          const SizedBox(height: 14),
          const Rotulo('CON CUÁNTO PAGA'),
          Row(
            children: [
              for (final (pesos, texto) in const [(0, 'Exacto'), (500, '500'), (1000, '1,000'), (2000, '2,000')])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: BotonRedondo(
                      onPressed: () {
                        _recibido.text = _vm.billete(pesos);
                        _focoRecibido.requestFocus();
                        _recibido.selection = TextSelection.collapsed(offset: _recibido.text.length);
                      },
                      texto: texto,
                      alto: 48,
                      relleno: const EdgeInsets.symmetric(horizontal: 4),
                      tamano: pesos == 0 ? 15 : 16,
                      peso: FontWeight.w700,
                      fondo: Estilo.suave,
                      borde: s.billeteMarcado(pesos) ? Estilo.azul : Estilo.bordeSuave,
                      grosorBorde: s.billeteMarcado(pesos) ? 2 : 1,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 12, 3, 0),
            child: Row(
              children: [
                const Text('Recibido', style: TextStyle(fontSize: 16, color: Estilo.gris)),
                const Spacer(),
                Tooltip(
                  message: 'Con cuánto paga. Vacío = monto exacto. Enter cobra.',
                  child: Container(
                    width: 190,
                    decoration:
                        const BoxDecoration(border: Border(bottom: BorderSide(color: Estilo.bordeSuave, width: 2))),
                    child: TextField(
                      controller: _recibido,
                      focusNode: _focoRecibido,
                      textAlign: TextAlign.right,
                      onEditingComplete: () {},
                      onChanged: _vm.escribirRecibido,
                      onSubmitted: (_) => _cobrar(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Estilo.azul),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(3, 12, 3, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: d.falta ? Estilo.rojoFondo : Estilo.verdeFondo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(d.etiqueta, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: verde)),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(d.monto, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: verde)),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (s.forma == FormaPago.fiado) ...[
          const SizedBox(height: 14),
          const Rotulo('SE LE FÍA A'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.fiadoNombre ?? 'Escoja el cliente',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Estilo.azul),
                      overflow: TextOverflow.ellipsis),
                ),
                BotonRedondo(onPressed: _buscarCliente, texto: 'Escoger'),
              ],
            ),
          ),
          if (s.fiadoCredito.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 8, 3, 0),
              child: Text(s.fiadoCredito, style: const TextStyle(fontSize: 14, color: Estilo.gris)),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 12, 3, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.descuento > 0 ? 'Descuento: ${formatoRD(s.descuento)}' : '',
                    style: const TextStyle(fontSize: 14, color: Estilo.gris)),
              ),
              BotonRedondo(
                onPressed: _descuento,
                texto: 'Descuento',
                fondo: Colors.transparent,
                grosorBorde: 0,
                alto: 32,
                tamano: 14,
                relleno: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Teclas ----------

  Widget _barraTeclas() => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                children: [
                  Tecla(tecla: 'F4', texto: 'Cantidad', onPressed: _cambiarCantidad),
                  Tecla(tecla: 'F7', texto: 'Cliente', onPressed: _irACliente),
                  Tecla(
                    tecla: 'F8',
                    texto: 'Venta suelta',
                    onPressed: _ventaSuelta,
                    mensaje: 'Cobrar un monto sin escoger producto. También: escriba \$50 en el código.',
                  ),
                  Tecla(
                      tecla: 'F9',
                      texto: 'Delivery',
                      onPressed: _delivery,
                      mensaje: 'Datos de entrega y despachar con el repartidor'),
                  Tecla(
                      tecla: 'Supr',
                      texto: 'Quitar',
                      onPressed: () async {
                        await _vm.quitar();
                        _alCodigo();
                      }),
                  Tecla(tecla: 'Esc', texto: 'Cancelar venta', onPressed: _cancelar),
                ],
              ),
            ),
            BotonRedondo(
              onPressed: () async {
                await _mostrar(await _vm.abrirGaveta());
                _alCodigo();
              },
              texto: 'Abrir gaveta',
              alto: 38,
              tamano: 14,
            ),
          ],
        ),
      );
}

/// Las rayitas del código de barras de la casilla de escanear.
class _CodigoDeBarras extends StatelessWidget {
  const _CodigoDeBarras();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(24, 24), painter: _Rayas());
}

class _Rayas extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Estilo.azul
      ..strokeWidth = 2;
    for (final x in const [3.0, 6.0, 10.0, 13.0, 17.0, 21.0]) {
      canvas.drawLine(Offset(x, 5), Offset(x, 19), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
