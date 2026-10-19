import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'logo_en_grises.dart';

/// El cuadro del logo: en blanco y negro, tal como lo va a imprimir la
/// impresora, o "Sin logo".
class VistaLogo extends StatefulWidget {
  const VistaLogo({super.key, required this.puntos, required this.ancho});

  final Uint8List? puntos;
  final int? ancho;

  @override
  State<VistaLogo> createState() => _VistaLogoState();
}

class _VistaLogoState extends State<VistaLogo> {
  ui.Image? _imagen;
  var _vuelta = 0;

  bool get _hay => (widget.puntos?.isNotEmpty ?? false) && (widget.ancho ?? 0) >= 8;

  @override
  void initState() {
    super.initState();
    _dibujar();
  }

  @override
  void didUpdateWidget(covariant VistaLogo anterior) {
    super.didUpdateWidget(anterior);
    if (!identical(anterior.puntos, widget.puntos) || anterior.ancho != widget.ancho) _dibujar();
  }

  @override
  void dispose() {
    _imagen?.dispose();
    super.dispose();
  }

  Future<void> _dibujar() async {
    final vuelta = ++_vuelta;
    if (!_hay) {
      _imagen?.dispose();
      _imagen = null;
      return;
    }
    final puntos = widget.puntos!;
    final ancho = widget.ancho!;
    final listo = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgbaDelLogo(puntos, ancho), ancho, altoDelLogo(puntos, ancho), ui.PixelFormat.rgba8888, listo.complete);
    final imagen = await listo.future;
    if (!mounted || vuelta != _vuelta) {
      imagen.dispose();
      return;
    }
    setState(() {
      _imagen?.dispose();
      _imagen = imagen;
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: 110,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD3D3D3))),
        child: !_hay
            ? const Center(child: Text('Sin logo', style: TextStyle(fontSize: 16, color: Color(0xFF808080))))
            : _imagen == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: RawImage(image: _imagen, fit: BoxFit.contain, filterQuality: FilterQuality.none),
                  ),
      );
}
