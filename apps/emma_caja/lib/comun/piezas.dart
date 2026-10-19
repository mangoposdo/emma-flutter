import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'estilo.dart';

/// Recuadro blanco con borde de la 0.7 ("Tarjeta").
class Tarjeta extends StatelessWidget {
  const Tarjeta({super.key, required this.child, this.relleno = const EdgeInsets.all(12), this.margen = const EdgeInsets.all(4), this.ancho});

  final Widget child;
  final EdgeInsets relleno;
  final EdgeInsets margen;
  final double? ancho;

  @override
  Widget build(BuildContext context) => Container(
        width: ancho,
        margin: margen,
        padding: relleno,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Estilo.borde),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );
}

/// Título de la pantalla: "Productos e inventario".
class TituloPantalla extends StatelessWidget {
  const TituloPantalla(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(texto, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Estilo.azul)),
      );
}

/// Texto de apoyo gris.
class TextoGris extends StatelessWidget {
  const TextoGris(this.texto, {super.key, this.tamano = 16, this.margen = const EdgeInsets.all(4)});

  final String texto;
  final double tamano;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margen,
        child: Text(texto, style: TextStyle(fontSize: tamano, color: Estilo.atenuado)),
      );
}

/// Rótulo en mayúsculas de las pantallas de venta y compras ("CÓMO PAGA").
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(3, 0, 0, 6),
        child: Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Estilo.gris)),
      );
}

/// La casilla de texto de la 0.7: blanca, con borde gris y azul al escribir.
class Casilla extends StatelessWidget {
  const Casilla({
    super.key,
    this.controller,
    this.foco,
    this.autofocus = false,
    this.marcador,
    this.derecha = false,
    this.oculta = false,
    this.onSubmitted,
    this.onChanged,
    this.tamano = 16,
    this.lineas = 1,
    this.habilitada = true,
    this.maxLargo,
    this.mayusculas = false,
    this.ancho,
    this.margen = const EdgeInsets.all(4),
    this.mensaje,
    this.negrita = false,
  });

  final TextEditingController? controller;
  final FocusNode? foco;
  final bool autofocus;
  final String? marcador;
  final bool derecha;
  final bool oculta;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final double tamano;
  final int lineas;
  final bool habilitada;
  final int? maxLargo;
  final bool mayusculas;
  final double? ancho;
  final EdgeInsets margen;
  final String? mensaje;
  final bool negrita;

  @override
  Widget build(BuildContext context) {
    const radio = BorderRadius.all(Radius.circular(2));
    Widget campo = TextField(
      controller: controller,
      focusNode: foco,
      autofocus: autofocus,
      obscureText: oculta,
      enabled: habilitada,
      textAlign: derecha ? TextAlign.right : TextAlign.left,
      maxLines: oculta ? 1 : lineas,
      minLines: 1,
      maxLength: maxLargo,
      textCapitalization: mayusculas ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: mayusculas ? [_Mayusculas()] : null,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      // Enter acepta sin soltar el foco.
      onEditingComplete: lineas > 1 ? null : () {},
      style: TextStyle(fontSize: tamano, color: Estilo.azul, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: marcador,
        hintStyle: TextStyle(fontSize: tamano, color: Estilo.marcador),
        filled: true,
        fillColor: habilitada ? Colors.white : const Color(0xFFFBFBFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: const OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: Estilo.borde)),
        enabledBorder: const OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: Estilo.borde)),
        disabledBorder: OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: Estilo.borde.withValues(alpha: 0.6))),
        focusedBorder: const OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: Estilo.enfoque, width: 1.5)),
      ),
    );
    if (mensaje != null) campo = Tooltip(message: mensaje, child: campo);
    return Padding(padding: margen, child: SizedBox(width: ancho, child: campo));
  }
}

class _Mayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Casilla de marcar con su texto al lado, como el CheckBox de la 0.7.
class Marca extends StatelessWidget {
  const Marca({super.key, required this.valor, required this.texto, required this.onChanged, this.margen = const EdgeInsets.symmetric(horizontal: 4, vertical: 4)});

  final bool valor;
  final String texto;
  final ValueChanged<bool>? onChanged;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margen,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!valor),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: valor,
                  onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Estilo.gris),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(child: Text(texto, style: const TextStyle(fontSize: 16, color: Estilo.azul))),
            ],
          ),
        ),
      );
}

/// Lista desplegable de la 0.7 (ComboBox).
class Desplegable<T> extends StatelessWidget {
  const Desplegable({
    super.key,
    required this.valor,
    required this.opciones,
    required this.texto,
    required this.onChanged,
    this.ancho,
    this.margen = const EdgeInsets.all(4),
  });

  final T? valor;
  final List<T> opciones;
  final String Function(T) texto;
  final ValueChanged<T>? onChanged;
  final double? ancho;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margen,
        child: SizedBox(
          width: ancho,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Estilo.borde),
              borderRadius: BorderRadius.circular(2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: opciones.contains(valor) ? valor : null,
                isExpanded: true,
                focusColor: Colors.transparent,
                style: const TextStyle(fontSize: 16, color: Estilo.azul),
                items: [for (final o in opciones) DropdownMenuItem(value: o, child: Text(texto(o), overflow: TextOverflow.ellipsis))],
                onChanged: onChanged == null ? null : (v) => v == null ? null : onChanged!(v),
              ),
            ),
          ),
        ),
      );
}

/// Fila "etiqueta | control" de los formularios (columna de 150 o 200 px).
class FilaCampo extends StatelessWidget {
  const FilaCampo({super.key, required this.etiqueta, required this.child, this.anchoEtiqueta = 150});

  final String etiqueta;
  final Widget child;
  final double anchoEtiqueta;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: anchoEtiqueta,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(etiqueta, style: const TextStyle(fontSize: 16, color: Estilo.azul)),
            ),
          ),
          Expanded(child: child),
        ],
      );
}
