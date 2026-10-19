import 'package:flutter/material.dart';

import 'estilo.dart';

enum TipoBoton {
  /// Blanco con borde gris.
  normal,

  /// Azul: la acción de la pantalla (Guardar, Abrir caja).
  principal,

  /// Rojo: solo la más importante (Cobrar, Entrar, Despachar).
  accion,
}

/// El botón de la 0.7: blanco con borde, azul o rojo.
class Boton extends StatelessWidget {
  const Boton(
    this.texto, {
    super.key,
    required this.onPressed,
    this.tipo = TipoBoton.normal,
    this.tamano = 16,
    this.anchoMinimo = 0,
    this.alto = 40,
    this.margen = const EdgeInsets.all(4),
    this.foco,
  });

  final String texto;
  final VoidCallback? onPressed;
  final TipoBoton tipo;
  final double tamano;
  final double anchoMinimo;
  final double alto;
  final EdgeInsets margen;
  final FocusNode? foco;

  @override
  Widget build(BuildContext context) {
    final (fondo, letra, borde, peso) = switch (tipo) {
      TipoBoton.normal => (Colors.white, Estilo.azul, Estilo.borde, FontWeight.w400),
      TipoBoton.principal => (Estilo.azul, Colors.white, Estilo.azul, FontWeight.w600),
      TipoBoton.accion => (Estilo.rojo, Colors.white, Estilo.rojo, FontWeight.w700),
    };
    return Padding(
      padding: margen,
      child: TextButton(
        focusNode: foco,
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? fondo.withValues(alpha: 0.5) : fondo,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? letra.withValues(alpha: 0.5) : letra,
          ),
          overlayColor: WidgetStatePropertyAll(
            tipo == TipoBoton.normal ? Estilo.azul.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.12),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: borde)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3)))),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          minimumSize: WidgetStatePropertyAll(Size(anchoMinimo, alto)),
          // En escritorio Material los compacta 8 px; la 0.7 los tiene de 40.
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: tamano, fontWeight: peso)),
        ),
        child: Text(texto, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Botón de esquinas redondas de las pantallas de venta y compras. No toma el
/// foco: la casilla del código nunca lo pierde.
class BotonRedondo extends StatelessWidget {
  const BotonRedondo({
    super.key,
    required this.onPressed,
    this.texto,
    this.child,
    this.fondo = Colors.white,
    this.letra = Estilo.azul,
    this.borde = Estilo.bordeSuave,
    this.grosorBorde = 1,
    this.tamano = 15,
    this.peso = FontWeight.w600,
    this.alto = 44,
    this.ancho,
    this.relleno = const EdgeInsets.symmetric(horizontal: 14),
    this.radio = 10,
    this.mensaje,
  }) : assert(texto != null || child != null);

  final VoidCallback? onPressed;
  final String? texto;
  final Widget? child;
  final Color fondo;
  final Color letra;
  final Color borde;
  final double grosorBorde;
  final double tamano;
  final FontWeight peso;
  final double alto;
  final double? ancho;
  final EdgeInsets relleno;
  final double radio;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final boton = ExcludeFocus(
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: fondo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radio),
            side: grosorBorde == 0 ? BorderSide.none : BorderSide(color: borde, width: grosorBorde),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radio),
            child: Container(
              height: alto,
              width: ancho,
              padding: relleno,
              // Del ancho de lo que dice, como un botón de la 0.7 en un WrapPanel;
              // si lo estiran (Expanded, stretch), el texto queda centrado.
              child: Center(
                widthFactor: 1,
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: tamano, fontWeight: peso, color: letra),
                  child: child ?? Text(texto!, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return mensaje == null ? boton : Tooltip(message: mensaje, child: boton);
  }
}

/// Una tecla de la barra de abajo de ventas: [F4] Cantidad.
class Tecla extends StatelessWidget {
  const Tecla({super.key, required this.tecla, required this.texto, required this.onPressed, this.mensaje});

  final String tecla;
  final String texto;
  final VoidCallback onPressed;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final contenido = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(
                    left: BorderSide(color: Estilo.bordeSuave),
                    top: BorderSide(color: Estilo.bordeSuave),
                    right: BorderSide(color: Estilo.bordeSuave),
                    bottom: BorderSide(color: Estilo.bordeSuave, width: 3),
                  ),
                ),
                child: Text(tecla, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Estilo.azul)),
              ),
              const SizedBox(width: 8),
              Text(texto, style: const TextStyle(fontSize: 14, color: Estilo.azul)),
            ],
          ),
        ),
      ),
    );
    return mensaje == null ? contenido : Tooltip(message: mensaje, child: contenido);
  }
}
