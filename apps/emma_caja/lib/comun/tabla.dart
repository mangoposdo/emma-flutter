import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'estilo.dart';

/// Una columna de [Tabla]. Con [ancho] es fija; si no, reparte el espacio con [flex].
class Columna<T> {
  const Columna(this.titulo, this.texto, {this.ancho, this.flex = 1, this.derecha = false, this.celda});

  final String titulo;
  final String Function(T fila) texto;
  final double? ancho;
  final int flex;
  final bool derecha;

  /// Para algo distinto de texto (una casilla marcada).
  final Widget Function(T fila)? celda;
}

/// Casilla marcada o no, para columnas como "Activo" o "Rápido".
Widget celdaMarcada(bool marcado) => Icon(
      marcado ? Icons.check_box_outlined : Icons.check_box_outline_blank,
      size: 20,
      color: Estilo.gris,
    );

/// La tabla de la 0.7 (DataGrid): encabezado, filas de 34 px con línea, una
/// fila escogida. Flechas para moverse y Enter (o doble clic) para abrir.
class Tabla<T> extends StatefulWidget {
  const Tabla({
    super.key,
    required this.columnas,
    required this.filas,
    this.escogida,
    this.alEscoger,
    this.alAbrir,
    this.colorFila,
    this.colorTexto,
    this.altoFila = 34,
    this.tamano = 16,
    this.margen = const EdgeInsets.all(4),
    this.irAlFinal = false,
  });

  final List<Columna<T>> columnas;
  final List<T> filas;
  final int? escogida;
  final ValueChanged<int>? alEscoger;
  final ValueChanged<int>? alAbrir;
  final Color? Function(T fila)? colorFila;
  final Color? Function(T fila)? colorTexto;
  final double altoFila;
  final double tamano;
  final EdgeInsets margen;

  /// Muestra la última fila al cargar (estado de cuenta).
  final bool irAlFinal;

  @override
  State<Tabla<T>> createState() => _TablaState<T>();
}

class _TablaState<T> extends State<Tabla<T>> {
  final _scroll = ScrollController();
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.irAlFinal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void didUpdateWidget(covariant Tabla<T> anterior) {
    super.didUpdateWidget(anterior);
    if (widget.escogida != anterior.escogida) _mostrar(widget.escogida);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _mostrar(int? i) {
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      final arriba = i * widget.altoFila;
      final abajo = arriba + widget.altoFila;
      if (arriba < p.pixels) {
        _scroll.jumpTo(arriba);
      } else if (abajo > p.pixels + p.viewportDimension) {
        _scroll.jumpTo((abajo - p.viewportDimension).clamp(0, p.maxScrollExtent));
      }
    });
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final n = widget.filas.length;
    if (n == 0) return KeyEventResult.ignored;
    final actual = widget.escogida;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.alEscoger?.call(actual == null ? 0 : (actual + 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.alEscoger?.call(actual == null ? 0 : (actual - 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if ((e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) && actual != null) {
      widget.alAbrir?.call(actual);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _celdas(Widget Function(Columna<T> c) hacer) => Row(
        children: [
          for (final c in widget.columnas)
            c.ancho != null ? SizedBox(width: c.ancho, child: hacer(c)) : Expanded(flex: c.flex, child: hacer(c)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final estiloTexto = TextStyle(fontSize: widget.tamano, color: Colors.black87);
    return Container(
      margin: widget.margen,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Estilo.borde)),
      child: Focus(
        focusNode: _foco,
        onKeyEvent: _tecla,
        child: Column(
          children: [
            Container(
              height: 30,
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF2F3F5)]),
                border: Border(bottom: BorderSide(color: Color(0xFFD5D5D5))),
              ),
              child: _celdas((c) => Container(
                    alignment: c.derecha ? Alignment.centerRight : Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE5E5E5)))),
                    child: Text(c.titulo, style: TextStyle(fontSize: widget.tamano, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: widget.filas.length,
                itemExtent: widget.altoFila,
                itemBuilder: (context, i) {
                  final f = widget.filas[i];
                  final escogida = i == widget.escogida;
                  final color = escogida ? Estilo.seleccionTabla : (widget.colorFila?.call(f) ?? Colors.white);
                  final letra = widget.colorTexto?.call(f);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // Se marca al bajar el botón: con doble clic, onTap llegaría 300 ms después.
                    onTapDown: (_) {
                      _foco.requestFocus();
                      widget.alEscoger?.call(i);
                    },
                    onDoubleTap: widget.alAbrir == null
                        ? null
                        : () {
                            widget.alEscoger?.call(i);
                            widget.alAbrir!(i);
                          },
                    child: Container(
                      decoration: BoxDecoration(color: color, border: const Border(bottom: BorderSide(color: Estilo.lineaTabla))),
                      child: _celdas((c) => Container(
                            alignment: c.derecha ? Alignment.centerRight : Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: c.celda?.call(f) ??
                                Text(
                                  c.texto(f),
                                  style: letra == null ? estiloTexto : estiloTexto.copyWith(color: letra),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          )),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
