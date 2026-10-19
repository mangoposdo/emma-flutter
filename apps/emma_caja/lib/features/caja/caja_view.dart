import 'dart:math' as math;

import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import 'caja_view_model.dart';
import 'conteo_view.dart';

/// "Caja y cuadre" de la 0.7: abrir la caja, el resumen del turno con
/// entradas y salidas, el cierre con el conteo, las ventas del turno y los
/// cuadres anteriores.
class CajaView extends ConsumerStatefulWidget {
  const CajaView({super.key});

  @override
  ConsumerState<CajaView> createState() => _CajaViewState();
}

class _CajaViewState extends ConsumerState<CajaView> {
  final _fondo = TextEditingController(text: '0');
  final _focoFondo = FocusNode();
  var _cerrando = false;

  @override
  void dispose() {
    _fondo.dispose();
    _focoFondo.dispose();
    super.dispose();
  }

  CajaViewModel get _vm => ref.read(cajaViewModelProvider.notifier);

  /// Con la caja cerrada, el fondo con el foco y todo marcado.
  void _enfocarFondo() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focoFondo.requestFocus();
        _fondo.selection = TextSelection(baseOffset: 0, extentOffset: _fondo.text.length);
      });

  Future<void> _abrir() => intentar(context, () => _vm.abrir(_fondo.text));

  Future<void> _movimiento(TipoMovCaja tipo) =>
      Formulario(tipo == TipoMovCaja.entrada ? 'Entrada de efectivo' : 'Salida de efectivo', ancho: 480)
          .monto('monto', 'Monto RD\$', minimo: 1)
          .texto('concepto', 'Concepto', requerido: true)
          .mostrar(context, alAceptar: (v) => _vm.movimiento(tipo, v.monto('monto'), v.txt('concepto')));

  Future<void> _cerrar() async {
    if (_cerrando || ref.read(cajaViewModelProvider).value?.abierta != true) return;
    _cerrando = true;
    try {
      final pregunta = await _vm.preguntaAntesDeCerrar();
      if (!mounted) return;
      if (pregunta != null && !await confirmar(context, pregunta)) return;
      if (!mounted) return;
      final conteo = await contarEfectivo(context);
      if (conteo == null || !mounted) return;
      CierreCaja? cierre;
      final bien = await intentar(context, () async {
        cierre = await _vm.cerrar(conteo.conteo, conteo.notas);
      });
      final c = cierre;
      if (!bien || c == null || !mounted) return;
      if (c.errorImpresion != null) await avisar(context, c.errorImpresion!);
      if (mounted) await informar(context, c.mensaje);
    } finally {
      _cerrando = false;
    }
  }

  Future<void> _verVenta(int i) async {
    final v = await _vm.verVenta(i);
    if (v == null || !mounted) return;
    if (!v.preguntarAnular) {
      await informar(context, v.mensaje);
      return;
    }
    if (!await confirmar(context, v.mensaje) || !mounted) return;
    final motivo = await pedirTexto(context, 'Anular venta', 'Motivo');
    if (motivo == null || !mounted) return;
    await intentar(context, () => _vm.anular(v.id, motivo));
  }

  Future<void> _reimprimir(int i) async {
    final r = await _vm.reimprimir(i);
    if (r == null || !mounted) return;
    await (r.esError ? avisar(context, r.texto) : informar(context, r.texto));
  }

  static String _monto(int? c) => c == null ? '' : formatoMonto(c);
  static String _fechaHora(DateTime? f) => f == null ? '' : formatoFechaHora(f);

  @override
  Widget build(BuildContext context) {
    ref.listen(cajaViewModelProvider, (antes, ahora) {
      if (ahora.value?.abierta == false && antes?.value?.abierta != false) _enfocarFondo();
    });
    final s = ref.watch(cajaViewModelProvider).value;
    const titulo = TituloPantalla('Caja y cuadre');
    if (s == null) return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [titulo]);

    // Los cuadres anteriores llenan lo que quede de alto; si no queda casi
    // nada (pantalla chica), la pantalla se desplaza.
    return LayoutBuilder(
      builder: (context, caja) => SingleChildScrollView(
        child: _ArribaYResto(
          alto: caja.maxHeight,
          minimo: 100,
          arriba: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titulo,
              if (s.abierta) _abierta(s) else _cerrada(),
              const TextoGris('Cuadres anteriores (doble clic para reimprimir)', margen: EdgeInsets.fromLTRB(4, 16, 4, 4)),
            ],
          ),
          resto: _historial(s),
        ),
      ),
    );
  }

  Widget _cerrada() => Align(
        alignment: Alignment.centerLeft,
        child: Tarjeta(
          ancho: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('La caja está cerrada', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Estilo.azul)),
              const TextoGris('Fondo inicial (el cambio con que empieza la gaveta)', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
              Casilla(controller: _fondo, foco: _focoFondo, derecha: true, tamano: 22),
              Boton('Abrir caja', tipo: TipoBoton.principal, tamano: 18, onPressed: _abrir),
            ],
          ),
        ),
      );

  /// La tabla de ventas crece con las filas hasta 520, como en la 0.7 (con el
  /// rótulo de arriba y el margen de la tabla).
  static double _altoVentas(CajaState s) => 33 + math.min(520.0, 32 + 34.0 * s.ventas.length) + 8;

  Widget _abierta(CajaState s) {
    const normal = TextStyle(fontSize: 16, color: Estilo.azul);
    final negrita = normal.copyWith(fontWeight: FontWeight.w700);
    final tarjeta = Tarjeta(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.textoTurno, style: const TextStyle(fontSize: 16, color: Estilo.atenuado)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final f in s.filasResumen)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(f.texto, style: f.negrita ? negrita : normal)),
                        Text(formatoRD(f.monto), style: f.negrita ? negrita : normal),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Boton('Entrada de efectivo', onPressed: () => _movimiento(TipoMovCaja.entrada)),
          Boton('Salida de efectivo (pago a suplidor, gasto)', onPressed: () => _movimiento(TipoMovCaja.salida)),
          Boton('Cerrar caja y cuadrar', tipo: TipoBoton.principal, tamano: 18, onPressed: _cerrar),
        ],
      ),
    );
    final ventas = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextoGris('Ventas de este turno (doble clic para ver o anular)'),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520 + 8),
            child: Tabla<VentaListada>(
              filas: s.ventas,
              escogida: s.ventaEscogida,
              alEscoger: _vm.escogerVenta,
              alAbrir: _verVenta,
              columnas: [
                Columna('#', (v) => '${v.venta.id}', ancho: 70),
                Columna('Hora', (v) => formatoHora(v.venta.fecha), ancho: 100),
                Columna('Pago', (v) => v.venta.formaPago.etiqueta, ancho: 120),
                Columna('Cliente', (v) => v.nombreParaMostrar ?? ''),
                Columna('Total', (v) => formatoMonto(v.venta.total), ancho: 110, derecha: true),
                Columna('Anulada', (v) => '', ancho: 80, celda: (v) => celdaMarcada(v.venta.anulada)),
              ],
            ),
          ),
        ),
      ],
    );
    // La tarjeta (420) a la izquierda y las ventas a la derecha, de la altura
    // de la más alta de las dos.
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          SizedBox(width: 420, child: tarjeta),
          SizedBox(height: _altoVentas(s)),
          Positioned(left: 420, top: 0, right: 0, bottom: 0, child: ventas),
        ],
      ),
    );
  }

  Widget _historial(CajaState s) => Tabla<TurnoConCajero>(
        filas: s.historial,
        escogida: s.cuadreEscogido,
        alEscoger: _vm.escogerCuadre,
        alAbrir: _reimprimir,
        columnas: [
          Columna('Apertura', (t) => _fechaHora(t.turno.apertura), ancho: 190),
          Columna('Cierre', (t) => _fechaHora(t.turno.cierre), ancho: 190),
          Columna('Cajero', (t) => t.cajero),
          Columna('Esperado', (t) => _monto(t.turno.efectivoEsperado), ancho: 120, derecha: true),
          Columna('Contado', (t) => _monto(t.turno.efectivoContado), ancho: 120, derecha: true),
          Columna('Diferencia', (t) => _monto(t.turno.diferencia), ancho: 120, derecha: true),
        ],
      );
}

/// [arriba] con su alto natural y [resto] con lo que quede de [alto], pero al
/// menos [minimo]. Si no cabe, el total pasa de [alto].
class _ArribaYResto extends MultiChildRenderObjectWidget {
  _ArribaYResto({required Widget arriba, required Widget resto, required this.alto, required this.minimo})
      : super(children: [arriba, resto]);

  final double alto;
  final double minimo;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderArribaYResto(alto, minimo);

  @override
  void updateRenderObject(BuildContext context, _RenderArribaYResto renderObject) => renderObject
    ..alto = alto
    ..minimo = minimo;
}

class _Parte extends ContainerBoxParentData<RenderBox> {}

class _RenderArribaYResto extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _Parte>, RenderBoxContainerDefaultsMixin<RenderBox, _Parte> {
  _RenderArribaYResto(this._alto, this._minimo);

  double _alto;
  set alto(double v) {
    if (v == _alto) return;
    _alto = v;
    markNeedsLayout();
  }

  double _minimo;
  set minimo(double v) {
    if (v == _minimo) return;
    _minimo = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Parte) child.parentData = _Parte();
  }

  @override
  void performLayout() {
    final ancho = constraints.maxWidth;
    final arriba = firstChild!;
    final resto = childAfter(arriba)!;
    arriba.layout(BoxConstraints.tightFor(width: ancho), parentUsesSize: true);
    final altoArriba = arriba.size.height;
    final altoResto = _alto.isFinite ? math.max(_minimo, _alto - altoArriba) : _minimo;
    resto.layout(BoxConstraints.tight(Size(ancho, altoResto)));
    (arriba.parentData! as _Parte).offset = Offset.zero;
    (resto.parentData! as _Parte).offset = Offset(0, altoArriba);
    size = constraints.constrain(Size(ancho, altoArriba + altoResto));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
