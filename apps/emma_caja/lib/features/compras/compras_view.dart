import 'dart:math';

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
import '../../plataforma/archivos.dart';
import '../productos/producto_formulario.dart';
import 'compras_view_model.dart';

const _negro = Colors.black87;
const _ambar = Color(0xFFA35F00);
const _rojoGanancia = Color(0xFFB22222);
const _rojoOscuro = Color(0xFFA3192B);
const _amarilloPanel = Color(0xFFFFF6DB);
const _amarilloBordePanel = Color(0xFFE8C35A);
const _cafe = Color(0xFF7A5A00);
const _cafeOscuro = Color(0xFF3D2E00);
const _atenuado = Color(0xFF696969);

const _altoLinea = 58.0;
const _altoBusqueda = 36.0;
const _altoMinimo = 480.0;

/// Registrar compra, como la 0.7.1: arriba el suplidor, la factura y cómo se
/// pagó; a la izquierda escanear y lo que llegó; a la derecha el total, guardar
/// y las últimas compras. La casilla de escanear nunca pierde el foco.
class ComprasView extends ConsumerStatefulWidget {
  const ComprasView({super.key});

  @override
  ConsumerState<ComprasView> createState() => _ComprasViewState();
}

class _ComprasViewState extends ConsumerState<ComprasView> {
  final _codigo = TextEditingController();
  final _cantidad = TextEditingController();
  final _costo = TextEditingController();
  final _suplidor = TextEditingController();
  final _factura = TextEditingController();
  late final _focoCodigo = FocusNode(onKeyEvent: _teclaCodigo);
  final _focoCantidad = FocusNode();
  final _focoCosto = FocusNode();
  final _focoSuplidor = FocusNode();
  final _focoFactura = FocusNode();
  final _focoBusqueda = FocusNode();
  final _focoLineas = FocusNode();
  final _scrollLineas = ScrollController();
  final _scrollBusqueda = ScrollController();
  int? _indiceBusqueda;
  int? _reciente;

  ComprasViewModel get _vm => ref.read(comprasViewModelProvider.notifier);
  ComprasEstado get _s => ref.read(comprasViewModelProvider);

  @override
  void initState() {
    super.initState();
    _suplidor.addListener(() => _vm.escribirSuplidor(_suplidor.text));
    _factura.addListener(() => _vm.escribirFactura(_factura.text));
  }

  @override
  void dispose() {
    for (final c in [_codigo, _cantidad, _costo, _suplidor, _factura]) {
      c.dispose();
    }
    for (final f in [_focoCodigo, _focoCantidad, _focoCosto, _focoSuplidor, _focoFactura, _focoBusqueda, _focoLineas]) {
      f.dispose();
    }
    _scrollLineas.dispose();
    _scrollBusqueda.dispose();
    super.dispose();
  }

  /// El foco se pide después de dibujar: la cantidad y el costo se habilitan
  /// en el mismo cambio.
  void _enfocar(FocusNode n, TextEditingController t, {bool marcar = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      n.requestFocus();
      if (marcar) t.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _alCodigo() => _enfocar(_focoCodigo, _codigo, marcar: false);

  void _alCambiar(ComprasEstado? antes, ComprasEstado ahora) {
    if (antes == null) return;
    if (antes.pendiente != null && ahora.pendiente == null) {
      _cantidad.clear();
      _costo.clear();
    }
    if (antes.pedidoCodigo != ahora.pedidoCodigo) {
      if (ahora.textoCodigo != null) _codigo.text = ahora.textoCodigo!;
      _enfocar(_focoCodigo, _codigo);
    }
    if (antes.seleccion != ahora.seleccion && ahora.pendiente != null) {
      _codigo.text = ahora.pendiente!.nombre;
      _cantidad.text = ahora.cantidadInicial;
      _costo.text = ahora.costoInicial;
      _enfocar(_focoCantidad, _cantidad);
    }
    if (_suplidor.text != ahora.suplidor) _suplidor.text = ahora.suplidor;
    if (_factura.text != ahora.factura) _factura.text = ahora.factura;
    if (!identical(antes.busqueda, ahora.busqueda)) _indiceBusqueda = null;
    if (antes.escogida != ahora.escogida || antes.lineas.length != ahora.lineas.length) {
      _mostrar(_scrollLineas, ahora.escogida, _altoLinea);
    }
    if (!identical(antes.recientes, ahora.recientes)) _reciente = null;
  }

  void _mostrar(ScrollController scroll, int? i, double alto) {
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final p = scroll.position;
      final arriba = i * alto;
      if (arriba < p.pixels) {
        scroll.jumpTo(arriba);
      } else if (arriba + alto > p.pixels + p.viewportDimension) {
        scroll.jumpTo((arriba + alto - p.viewportDimension).clamp(0, p.maxScrollExtent));
      }
    });
  }

  // ---------- Teclas ----------

  bool _esEnter(KeyEvent e) =>
      e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final s = _s;
    if (e.logicalKey == LogicalKeyboardKey.f10) {
      _guardar();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (s.busqueda != null) {
        _vm.cerrarBusqueda();
      } else if (s.pendiente != null) {
        _vm.limpiarPendiente();
      } else if (_focoCodigo.hasFocus) {
        _vaciar();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _teclaCodigo(FocusNode _, KeyEvent e) {
    final b = _s.busqueda;
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown && b != null && b.isNotEmpty) {
      setState(() => _indiceBusqueda = 0);
      _focoBusqueda.requestFocus();
      _mostrar(_scrollBusqueda, 0, _altoBusqueda);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _teclaBusqueda(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final b = _s.busqueda;
    if (b == null || b.isEmpty) return KeyEventResult.ignored;
    final i = _indiceBusqueda;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final nuevo =
          e.logicalKey == LogicalKeyboardKey.arrowDown ? min((i ?? -1) + 1, b.length - 1) : max((i ?? 1) - 1, 0);
      setState(() => _indiceBusqueda = nuevo);
      _mostrar(_scrollBusqueda, nuevo, _altoBusqueda);
      return KeyEventResult.handled;
    }
    if (_esEnter(e) && e is KeyDownEvent) {
      if (i != null && i < b.length) _vm.elegir(b[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _teclaLineas(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final s = _s;
    final i = s.escogida;
    if (s.lineas.isEmpty) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _vm.escogerLinea(i == null ? 0 : min(i + 1, s.lineas.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _vm.escogerLinea(i == null ? 0 : max(i - 1, 0));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.delete && e is KeyDownEvent && i != null) {
      _quitar(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- Acciones ----------

  Future<bool> _preguntar(String pregunta) async => mounted && await confirmar(context, pregunta);

  Future<int?> _pedirPrecio(LineaCompraVista l, String nota) async {
    if (!mounted) return null;
    return pedirMonto(context, 'Precio de venta: ${l.nombre}', 'Se vende a RD\$',
        valor: l.precio, nota: nota, minimo: 1);
  }

  Future<Producto?> _crearPorCodigo(String codigo) async {
    final crear = await _preguntar('El código $codigo no está registrado.\n\n¿Crear el producto ahora?');
    if (!crear || !mounted) return null;
    return editarProducto(context, ref, codigo: codigo);
  }

  Future<void> _escanear() async {
    final msg = await _vm.escanear(_codigo.text, crear: _crearPorCodigo);
    if (msg == null || !mounted) return;
    await SystemSound.play(SystemSoundType.alert);
    if (!mounted) return;
    await avisar(context, msg);
    _enfocar(_focoCodigo, _codigo);
  }

  Future<void> _alCantidad() async {
    if (_s.pendiente == null) return;
    final msg = _vm.cantidad(_cantidad.text);
    if (msg != null) {
      await avisar(context, msg);
      _enfocar(_focoCantidad, _cantidad);
      return;
    }
    _enfocar(_focoCosto, _costo);
  }

  Future<void> _alCosto() async {
    final s = _s;
    if (s.pendiente == null) return;
    if (s.cantidadPendiente <= 0) {
      _enfocar(_focoCantidad, _cantidad, marcar: false);
      return;
    }
    final msg = await _vm.costo(_costo.text, pedirPrecio: _pedirPrecio);
    if (!mounted) return;
    if (msg != null) {
      await avisar(context, msg);
      _enfocar(_focoCosto, _costo);
      return;
    }
    _alCodigo();
  }

  Future<void> _precio(int i) async {
    await _vm.precio(i, pedirPrecio: _pedirPrecio);
    _alCodigo();
  }

  void _quitar(int i) {
    _vm.quitar(i);
    _alCodigo();
  }

  Future<void> _guardar() async {
    final msg = await _vm.guardar(preguntar: _preguntar);
    if (!mounted) return;
    if (msg != null) return avisar(context, msg);
    _alCodigo();
  }

  Future<void> _vaciar() async {
    await _vm.vaciar(preguntar: _preguntar);
    _alCodigo();
  }

  Future<void> _leerFactura() async {
    final msg = await _vm.leerFactura(
      preguntar: _preguntar,
      escoger: () => escogerArchivo(
        descripcion: 'Foto o PDF de la factura',
        extensiones: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      ),
    );
    if (msg != null && mounted) await avisar(context, msg);
  }

  Future<void> _crearDeFactura() => _vm.crearDeFactura(
        crear: (codigo, nombre, costo) async =>
            mounted ? editarProducto(context, ref, codigo: codigo, nombre: nombre, costo: costo) : null,
      );

  Future<void> _verCompra(CompraDetalle c) =>
      showDialog<void>(context: context, builder: (_) => _DetalleCompra(compra: c));

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(comprasViewModelProvider);
    ref.listen(comprasViewModelProvider, _alCambiar);
    return Stack(
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _tecla,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _barraDeArriba(s),
              const SizedBox(height: 16),
              Expanded(
                // En una ventana muy baja se recorta, como la 0.7, en vez de apretarse.
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cuerpo = Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _izquierda(s)),
                        const SizedBox(width: 20),
                        SizedBox(width: 380, child: _derecha(s)),
                      ],
                    );
                    if (c.maxHeight >= _altoMinimo) return cuerpo;
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: _altoMinimo,
                        maxHeight: _altoMinimo,
                        child: cuerpo,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (s.leyendo) const Positioned.fill(child: MouseRegion(cursor: SystemMouseCursors.wait, opaque: false)),
      ],
    );
  }

  Widget _barraDeArriba(ComprasEstado s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 28),
              child: Text('Registrar compra',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Estilo.azul)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Rotulo('SUPLIDOR'),
                  _CasillaSuplidor(
                    controller: _suplidor,
                    foco: _focoSuplidor,
                    suplidores: s.suplidores,
                    alTerminar: _alCodigo,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Rotulo('FACTURA #'),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Estilo.suave,
                      border: Border.all(color: Estilo.bordeSuave),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _factura,
                        focusNode: _focoFactura,
                        maxLength: 40,
                        buildCounter: _sinContador,
                        style: const TextStyle(fontSize: 16, color: Estilo.azul),
                        decoration: const InputDecoration.collapsed(hintText: ''),
                        onSubmitted: (_) => _alCodigo(),
                        onEditingComplete: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Rotulo('SE PAGÓ'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pago(s, PagoCompra.deLaCaja, 'De la caja', 'Sale del efectivo de la caja (se resta en el cuadre)'),
                    _pago(s, PagoCompra.porFuera, 'Por fuera',
                        'Banco, transferencia o dinero del dueño: no toca la caja'),
                    _pago(s, PagoCompra.credito, 'A crédito', 'Se le queda debiendo al suplidor'),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mismo alto que los rótulos: el botón queda abajo, al nivel de las casillas.
                  const Rotulo(' '),
                  BotonRedondo(
                    onPressed: s.leyendo ? null : _leerFactura,
                    fondo: Estilo.azul,
                    letra: Colors.white,
                    grosorBorde: 0,
                    alto: 42,
                    relleno: const EdgeInsets.symmetric(horizontal: 16),
                    mensaje:
                        'Escoja la foto o el PDF de la factura: Emma la lee y llena la compra para que usted la revise',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CustomPaint(size: Size(20, 20), painter: _Dibujo.camara(Colors.white)),
                        const SizedBox(width: 10),
                        Text(s.leyendo ? 'Leyendo la factura…' : 'Leer factura (foto)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static Widget? _sinContador(BuildContext _,
          {required int currentLength, required bool isFocused, required int? maxLength}) =>
      null;

  Widget _pago(ComprasEstado s, PagoCompra p, String texto, String mensaje) {
    final escogido = s.pago == p;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: BotonRedondo(
        texto: texto,
        mensaje: mensaje,
        ancho: 120,
        alto: 42,
        relleno: EdgeInsets.zero,
        grosorBorde: 2,
        fondo: escogido ? Estilo.azul : Colors.white,
        letra: escogido ? Colors.white : Estilo.azul,
        borde: escogido ? Estilo.azul : Estilo.bordeSuave,
        peso: escogido ? FontWeight.w700 : FontWeight.w600,
        onPressed: () => _vm.pago(p),
      ),
    );
  }

  // ---------- Izquierda: escanear y lo que llegó ----------

  Widget _izquierda(ComprasEstado s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
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
                      const CustomPaint(size: Size(24, 24), painter: _Dibujo.codigoDeBarras(Estilo.azul)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _codigo,
                          focusNode: _focoCodigo,
                          autofocus: true,
                          style: const TextStyle(fontSize: 22, color: Estilo.azul),
                          decoration: const InputDecoration.collapsed(
                            hintText: 'Escanee o escriba lo que llegó',
                            hintStyle: TextStyle(fontSize: 22, color: Estilo.marcador),
                          ),
                          onSubmitted: (_) => _escanear(),
                          onEditingComplete: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: _CasillaNumero(
                  rotulo: s.rotuloCantidad,
                  controller: _cantidad,
                  foco: _focoCantidad,
                  habilitada: s.pendiente != null,
                  alEnter: _alCantidad,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: _CasillaNumero(
                  rotulo: s.rotuloCosto,
                  controller: _costo,
                  foco: _focoCosto,
                  habilitada: s.pendiente != null,
                  alEnter: _alCosto,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Text(s.seleccionado,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Estilo.azul)),
          ),
          if (s.leida == null) const SizedBox.shrink() else _panelEmparejar(s),
          Expanded(child: _lineas(s)),
        ],
      );

  Widget _panelEmparejar(ComprasEstado s) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _amarilloPanel,
          border: Border.all(color: _amarilloBordePanel, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.cuentaEmparejar,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _cafe)),
                  Text(
                    s.lineaEmparejar,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _cafeOscuro),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text('¿Cuál producto es? Escanéelo o búsquelo arriba y pulse Enter.',
                      style: TextStyle(fontSize: 13, color: _cafe)),
                ],
              ),
            ),
            BotonRedondo(
              texto: 'Crear producto',
              tamano: 14,
              alto: 38,
              relleno: const EdgeInsets.symmetric(horizontal: 12),
              mensaje: 'Es mercancía nueva: crearla con lo que dice la factura',
              onPressed: _crearDeFactura,
            ),
            const SizedBox(width: 8),
            BotonRedondo(
              texto: 'Saltar',
              tamano: 14,
              alto: 38,
              relleno: const EdgeInsets.symmetric(horizontal: 12),
              mensaje: 'No meter este renglón en la compra',
              onPressed: _vm.saltarDeFactura,
            ),
          ],
        ),
      );

  Widget _columnas(List<Widget> c) => Row(
        children: [
          Expanded(child: c[0]),
          SizedBox(width: 90, child: c[1]),
          SizedBox(width: 100, child: c[2]),
          SizedBox(width: 110, child: c[3]),
          SizedBox(width: 150, child: c[4]),
          SizedBox(width: 52, child: c[5]),
        ],
      );

  Widget _lineas(ComprasEstado s) {
    const titulo = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Estilo.gris);
    final busqueda = s.busqueda;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Estilo.linea))),
            child: _columnas(const [
              Text('PRODUCTO', style: titulo),
              Text('CANTIDAD', style: titulo, textAlign: TextAlign.right),
              Text('COSTO', style: titulo, textAlign: TextAlign.right),
              Text('TOTAL', style: titulo, textAlign: TextAlign.right),
              Text('SE VENDE A', style: titulo, textAlign: TextAlign.right),
              SizedBox.shrink(),
            ]),
          ),
          Expanded(
            child: Stack(
              children: [
                if (s.lineas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Escanee cada producto de la factura, escriba cuántos llegaron y a cuánto le salió cada uno. '
                      'O pulse "Leer factura" y escoja la foto: Emma la llena sola. '
                      'Al guardar, sube el inventario y queda el costo nuevo.',
                      style: TextStyle(fontSize: 15, color: Estilo.gris),
                    ),
                  )
                else
                  Focus(
                    focusNode: _focoLineas,
                    onKeyEvent: _teclaLineas,
                    child: ListView.builder(
                      controller: _scrollLineas,
                      itemCount: s.lineas.length,
                      itemExtent: _altoLinea,
                      itemBuilder: (_, i) => _linea(s, i),
                    ),
                  ),
                if (busqueda != null) Positioned(left: 8, right: 8, top: 0, child: _panelBusqueda(busqueda)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(ComprasEstado s, int i) {
    final l = s.lineas[i];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focoLineas.requestFocus();
        _vm.escogerLinea(i);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: i == s.escogida ? Estilo.seleccion : Colors.white,
          border: const Border(bottom: BorderSide(color: Estilo.lineaFila)),
        ),
        child: _columnas([
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.nombre,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _negro),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(l.detalle,
                  style: TextStyle(fontSize: 12, color: l.revisar ? _ambar : Estilo.gris),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          Text(l.cantidadTexto,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _negro),
              textAlign: TextAlign.right),
          Text(formatoMonto(l.costo), style: const TextStyle(fontSize: 16, color: _negro), textAlign: TextAlign.right),
          Text(formatoMonto(l.total),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _negro),
              textAlign: TextAlign.right),
          Align(
            alignment: Alignment.centerRight,
            child: BotonRedondo(
              alto: 40,
              relleno: const EdgeInsets.symmetric(horizontal: 10),
              mensaje: 'Cambiar el precio de venta',
              onPressed: () => _precio(i),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(l.precioTexto, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(l.ganancia,
                      style: TextStyle(fontSize: 12, color: l.dejaGanancia ? Estilo.verde : _rojoGanancia)),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: BotonRedondo(
              fondo: Colors.transparent,
              grosorBorde: 0,
              ancho: 44,
              alto: 40,
              relleno: EdgeInsets.zero,
              mensaje: 'Quitar',
              onPressed: () => _quitar(i),
              child: const CustomPaint(size: Size(20, 20), painter: _Dibujo.zafacon(_rojoOscuro)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _panelBusqueda(List<Producto> productos) => Container(
        constraints: const BoxConstraints(maxHeight: 420),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Estilo.azul, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Focus(
          focusNode: _focoBusqueda,
          onKeyEvent: _teclaBusqueda,
          child: ListView.builder(
            controller: _scrollBusqueda,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: productos.length,
            itemExtent: _altoBusqueda,
            itemBuilder: (_, i) {
              final p = productos[i];
              // Se marca al bajar el botón: con doble clic, el clic sencillo tardaría.
              return Listener(
                onPointerDown: (_) {
                  _focoBusqueda.requestFocus();
                  setState(() => _indiceBusqueda = i);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => _vm.elegir(p),
                  child: Container(
                    color: i == _indiceBusqueda ? Estilo.seleccionTabla : null,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(p.nombre,
                              style: const TextStyle(fontSize: 18, color: _negro),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('Hay ${cantidadCorta(p.existencia)}',
                            style: const TextStyle(fontSize: 18, color: _atenuado)),
                        const SizedBox(width: 24),
                        Text('Costo RD\$ ${formatoMonto(p.costo)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _negro)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

  // ---------- Derecha: total, guardar y últimas compras ----------

  Widget _derecha(ComprasEstado s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(color: Estilo.azul, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL DE LA COMPRA',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Estilo.textoSobreAzul)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatoRD(s.total),
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                Text(s.resumen, style: const TextStyle(fontSize: 15, color: Estilo.textoSobreAzul)),
              ],
            ),
          ),
          BotonRedondo(
            alto: 68,
            fondo: Estilo.rojo,
            letra: Colors.white,
            grosorBorde: 0,
            onPressed: _guardar,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('GUARDAR COMPRA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Container(
                    margin: const EdgeInsets.only(left: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _rojoOscuro, borderRadius: BorderRadius.circular(6)),
                    child: const Text('F10'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.aviso,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Estilo.verde)),
                ),
                BotonRedondo(texto: 'Vaciar (Esc)', tamano: 14, alto: 38, onPressed: _vaciar),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Rotulo('ÚLTIMAS COMPRAS'),
                  Expanded(
                    child: Tooltip(
                      message: 'Doble clic para ver los productos',
                      child: ListView.builder(
                        itemCount: s.recientes.length,
                        itemBuilder: (_, i) => _filaReciente(s.recientes[i], i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _filaReciente(CompraDetalle c, int i) => Listener(
        onPointerDown: (_) => setState(() => _reciente = i),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => _verCompra(c),
          child: Container(
            color: i == _reciente ? Estilo.seleccion : null,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tituloCompra(c),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _negro),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(detalleCompra(c), style: const TextStyle(fontSize: 12, color: Estilo.gris)),
                    ],
                  ),
                ),
                Text(formatoMonto(c.compra.total),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _negro)),
              ],
            ),
          ),
        ),
      );
}

/// El suplidor: se escoge de los guardados o se escribe uno nuevo.
class _CasillaSuplidor extends StatelessWidget {
  const _CasillaSuplidor(
      {required this.controller, required this.foco, required this.suplidores, required this.alTerminar});

  final TextEditingController controller;
  final FocusNode foco;
  final List<String> suplidores;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Escoja o escriba uno nuevo; queda guardado para la próxima.',
        child: SizedBox(
          width: 260,
          height: 42,
          child: RawAutocomplete<String>(
            textEditingController: controller,
            focusNode: foco,
            optionsBuilder: (v) {
              final t = v.text.trim().toLowerCase();
              if (t.isEmpty) return const [];
              return suplidores.where((s) => s.toLowerCase().startsWith(t) && s.toLowerCase() != t);
            },
            onSelected: (_) => alTerminar(),
            fieldViewBuilder: (context, c, f, alEnviar) => Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Estilo.borde),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      focusNode: f,
                      style: const TextStyle(fontSize: 16, color: Estilo.azul),
                      decoration: const InputDecoration.collapsed(hintText: ''),
                      onSubmitted: (_) {
                        alEnviar();
                        alTerminar();
                      },
                      onEditingComplete: () {},
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: suplidores.isNotEmpty,
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down, color: Estilo.gris),
                    itemBuilder: (_) => [
                      for (final s in suplidores)
                        PopupMenuItem(
                            value: s, child: Text(s, style: const TextStyle(fontSize: 16, color: Estilo.azul))),
                    ],
                    onSelected: (s) {
                      c.text = s;
                      alTerminar();
                    },
                  ),
                ],
              ),
            ),
            optionsViewBuilder: (context, alEscoger, opciones) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 260),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final (i, o) in opciones.indexed)
                        InkWell(
                          onTap: () => alEscoger(o),
                          child: Container(
                            color: AutocompleteHighlightedOption.of(context) == i ? Estilo.seleccionTabla : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(o, style: const TextStyle(fontSize: 16, color: Estilo.azul)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Cantidad o costo: rótulo chiquito arriba y el número grande a la derecha.
class _CasillaNumero extends StatelessWidget {
  const _CasillaNumero({
    required this.rotulo,
    required this.controller,
    required this.foco,
    required this.habilitada,
    required this.alEnter,
  });

  final String rotulo;
  final TextEditingController controller;
  final FocusNode foco;
  final bool habilitada;
  final VoidCallback alEnter;

  @override
  Widget build(BuildContext context) => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Estilo.bordeSuave, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(rotulo,
                style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: Estilo.gris)),
            TextField(
              controller: controller,
              focusNode: foco,
              enabled: habilitada,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700, color: Estilo.azul),
              decoration: const InputDecoration.collapsed(hintText: ''),
              onSubmitted: (_) => alEnter(),
              onEditingComplete: () {},
            ),
          ],
        ),
      );
}

/// La ventanita con los productos de una compra guardada.
class _DetalleCompra extends StatelessWidget {
  const _DetalleCompra({required this.compra});

  final CompraDetalle compra;

  @override
  Widget build(BuildContext context) {
    final alto = min(480.0, 32 + 34.0 * max(compra.lineas.length, 1) + 10);
    return Dialog(
      backgroundColor: Estilo.fondo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      child: SizedBox(
        width: 640,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('${tituloCompra(compra)} · ${formatoRD(compra.compra.total)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Estilo.gris),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              SizedBox(
                height: alto,
                child: Tabla<CompraLinea>(
                  filas: compra.lineas,
                  columnas: [
                    Columna('Producto', (l) => l.descripcion),
                    Columna('Cantidad', (l) => formatoCantidad(l.cantidad), ancho: 90),
                    Columna('Costo', (l) => formatoMonto(l.costo), ancho: 100),
                    Columna('Total', (l) => formatoMonto(l.total), ancho: 110),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los dibujitos de la 0.7 (Path de WPF con Stretch=Uniform): rayas en un
/// cuadro de diseño que se agranda parejo hasta llenar el tamaño.
class _Dibujo extends CustomPainter {
  const _Dibujo.codigoDeBarras(this.color)
      : trazos = const [
          [Offset(3, 5), Offset(3, 19)],
          [Offset(6, 5), Offset(6, 19)],
          [Offset(10, 5), Offset(10, 19)],
          [Offset(13, 5), Offset(13, 19)],
          [Offset(17, 5), Offset(17, 19)],
          [Offset(21, 5), Offset(21, 19)],
        ],
        circulo = null,
        redondo = false;

  const _Dibujo.zafacon(this.color)
      : trazos = const [
          [Offset(4, 7), Offset(20, 7)],
          [Offset(9, 7), Offset(9, 4), Offset(15, 4), Offset(15, 7)],
          [Offset(6, 7), Offset(7, 20), Offset(17, 20), Offset(18, 7)],
        ],
        circulo = null,
        redondo = true;

  const _Dibujo.camara(this.color)
      : trazos = const [
          [
            Offset(4, 8),
            Offset(8, 8),
            Offset(10, 5),
            Offset(14, 5),
            Offset(16, 8),
            Offset(20, 8),
            Offset(20, 19),
            Offset(4, 19),
            Offset(4, 8)
          ],
        ],
        circulo = const (Offset(12, 13), 3.0),
        redondo = true;

  final Color color;
  final List<List<Offset>> trazos;
  final (Offset, double)? circulo;
  final bool redondo;

  @override
  void paint(Canvas canvas, Size size) {
    final puntos = trazos.expand((t) => t);
    var izq = puntos.map((p) => p.dx).reduce(min);
    var der = puntos.map((p) => p.dx).reduce(max);
    var arriba = puntos.map((p) => p.dy).reduce(min);
    var abajo = puntos.map((p) => p.dy).reduce(max);
    final c = circulo;
    if (c != null) {
      izq = min(izq, c.$1.dx - c.$2);
      der = max(der, c.$1.dx + c.$2);
      arriba = min(arriba, c.$1.dy - c.$2);
      abajo = max(abajo, c.$1.dy + c.$2);
    }
    const grueso = 2.0;
    final ancho = size.width - grueso;
    final alto = size.height - grueso;
    final escala = min(ancho / (der - izq), alto / (abajo - arriba));
    final dx = (size.width - (der - izq) * escala) / 2 - izq * escala;
    final dy = (size.height - (abajo - arriba) * escala) / 2 - arriba * escala;
    Offset en(Offset p) => Offset(p.dx * escala + dx, p.dy * escala + dy);

    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grueso
      ..strokeCap = redondo ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    for (final t in trazos) {
      final camino = Path()..moveTo(en(t.first).dx, en(t.first).dy);
      for (final p in t.skip(1)) {
        camino.lineTo(en(p).dx, en(p).dy);
      }
      canvas.drawPath(camino, pincel);
    }
    if (c != null) canvas.drawCircle(en(c.$1), c.$2 * escala, pincel);
  }

  @override
  bool shouldRepaint(_Dibujo anterior) => anterior.color != color || anterior.trazos != trazos;
}
