import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avisos.dart';
import 'botones.dart';
import 'estilo.dart';
import 'piezas.dart';

/// Ventana de formulario como la de la 0.7: etiqueta y campo por fila, con
/// Aceptar y Cancelar. Se usa para productos, clientes, usuarios y para pedir
/// un valor. Montos en centavos y cantidades en milésimas.
///
/// ```dart
/// final v = await Formulario('Entrada de efectivo')
///     .monto('monto', 'Monto RD\$', minimo: 1)
///     .texto('concepto', 'Concepto', requerido: true)
///     .mostrar(context, alAceptar: (v) => vm.entrada(v.monto('monto'), v.txt('concepto')));
/// ```
class Formulario {
  Formulario(this.titulo, {this.ancho = 480, this.anchoEtiqueta = 150});

  final String titulo;
  final double ancho;
  final double anchoEtiqueta;
  final _campos = <_Campo>[];

  Formulario texto(String clave, String etiqueta, {String? valor, bool requerido = false, int lineas = 1, bool mayusculas = false}) {
    _campos.add(_Campo(_Tipo.texto, clave, etiqueta, valor: valor, requerido: requerido, lineas: lineas, mayusculas: mayusculas));
    return this;
  }

  Formulario clave(String clave, String etiqueta) {
    _campos.add(_Campo(_Tipo.clave, clave, etiqueta));
    return this;
  }

  /// [valor] y [minimo] en centavos.
  Formulario monto(String clave, String etiqueta, {int? valor, bool requerido = true, int minimo = 0}) {
    _campos.add(_Campo(_Tipo.monto, clave, etiqueta,
        valor: valor == null ? null : _textoMonto(valor), requerido: requerido, minimo: minimo));
    return this;
  }

  /// [valor] y [minimo] en milésimas.
  Formulario cantidad(String clave, String etiqueta, {int? valor, bool requerido = true, int minimo = 0}) {
    _campos.add(_Campo(_Tipo.cantidad, clave, etiqueta,
        valor: valor == null ? null : formatoCantidad(valor), requerido: requerido, minimo: minimo));
    return this;
  }

  Formulario opciones<T>(String clave, String etiqueta, List<T> opciones, T seleccion, String Function(T) texto) {
    _campos.add(_Campo(_Tipo.opciones, clave, etiqueta,
        opciones: opciones, seleccion: seleccion, textoOpcion: (Object? o) => texto(o as T)));
    return this;
  }

  Formulario casilla(String clave, String etiqueta, bool valor) {
    _campos.add(_Campo(_Tipo.casilla, clave, etiqueta, marcado: valor));
    return this;
  }

  Formulario nota(String texto) {
    _campos.add(_Campo(_Tipo.nota, '', texto));
    return this;
  }

  /// Muestra la ventana. Si [alAceptar] lanza una regla del negocio, se muestra
  /// el mensaje y la ventana sigue abierta. Devuelve los valores, o null si cancelan.
  Future<ValoresFormulario?> mostrar(BuildContext context, {Future<void> Function(ValoresFormulario v)? alAceptar}) =>
      showDialog<ValoresFormulario>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _Dialogo(formulario: this, alAceptar: alAceptar),
      );

  static String _textoMonto(int c) => c % 100 == 0 ? '${c ~/ 100}' : formatoMonto(c).replaceAll(',', '');
}

/// Pide un monto (centavos) en una ventanita. null si cancelan.
Future<int?> pedirMonto(BuildContext context, String titulo, String etiqueta, {int? valor, String? nota, int minimo = 0}) async {
  final f = Formulario(titulo, ancho: 420).monto('n', etiqueta, valor: valor, minimo: minimo);
  if (nota != null) f.nota(nota);
  final v = await f.mostrar(context);
  return v?.monto('n');
}

/// Pide una cantidad (milésimas). null si cancelan.
Future<int?> pedirCantidad(BuildContext context, String titulo, String etiqueta, {int? valor, String? nota, int minimo = 0}) async {
  final f = Formulario(titulo, ancho: 420).cantidad('n', etiqueta, valor: valor, minimo: minimo);
  if (nota != null) f.nota(nota);
  final v = await f.mostrar(context);
  return v?.cantidad('n');
}

Future<String?> pedirTexto(BuildContext context, String titulo, String etiqueta, {String? valor}) async {
  final v = await Formulario(titulo, ancho: 460).texto('t', etiqueta, valor: valor, requerido: true).mostrar(context);
  return v?.txt('t');
}

class ValoresFormulario {
  ValoresFormulario._(this._valores);

  final Map<String, Object?> _valores;

  String txt(String clave) => (_valores[clave] as String? ?? '').trim();
  String? txtONulo(String clave) => txt(clave).isEmpty ? null : txt(clave);

  /// Centavos (0 si vacío).
  int monto(String clave) => txt(clave).isEmpty ? 0 : parsearMonto(txt(clave)) ?? 0;

  /// Milésimas (0 si vacío).
  int cantidad(String clave) => txt(clave).isEmpty ? 0 : parsearCantidad(txt(clave)) ?? 0;
  bool marcado(String clave) => _valores[clave] as bool? ?? false;
  T opcion<T>(String clave) => _valores[clave] as T;
}

enum _Tipo { texto, clave, monto, cantidad, opciones, casilla, nota }

class _Campo {
  _Campo(
    this.tipo,
    this.clave,
    this.etiqueta, {
    this.valor,
    this.requerido = false,
    this.minimo = 0,
    this.lineas = 1,
    this.mayusculas = false,
    this.opciones = const [],
    this.seleccion,
    this.textoOpcion,
    this.marcado = false,
  });

  final _Tipo tipo;
  final String clave;
  final String etiqueta;
  final String? valor;
  final bool requerido;
  final int minimo;
  final int lineas;
  final bool mayusculas;
  final List<Object?> opciones;
  final Object? seleccion;
  final String Function(Object?)? textoOpcion;
  final bool marcado;
}

class _Dialogo extends StatefulWidget {
  const _Dialogo({required this.formulario, this.alAceptar});

  final Formulario formulario;
  final Future<void> Function(ValoresFormulario v)? alAceptar;

  @override
  State<_Dialogo> createState() => _DialogoState();
}

class _DialogoState extends State<_Dialogo> {
  final _textos = <String, TextEditingController>{};
  final _focos = <String, FocusNode>{};
  final _opciones = <String, Object?>{};
  final _marcas = <String, bool>{};
  var _ocupado = false;

  List<_Campo> get _campos => widget.formulario._campos;

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      switch (c.tipo) {
        case _Tipo.texto || _Tipo.clave || _Tipo.monto || _Tipo.cantidad:
          _textos[c.clave] = TextEditingController(text: c.valor ?? '');
          _focos[c.clave] = FocusNode();
        case _Tipo.opciones:
          _opciones[c.clave] = c.seleccion;
        case _Tipo.casilla:
          _marcas[c.clave] = c.marcado;
        case _Tipo.nota:
          break;
      }
    }
    // El primer campo de texto empieza con el foco y todo marcado.
    final primero = _campos.where((c) => _textos.containsKey(c.clave)).firstOrNull;
    if (primero != null) {
      final t = _textos[primero.clave]!;
      t.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
    }
  }

  @override
  void dispose() {
    for (final t in _textos.values) {
      t.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<bool> _validar() async {
    for (final c in _campos) {
      final t = _textos[c.clave]?.text.trim() ?? '';
      String? error;
      switch (c.tipo) {
        case _Tipo.texto:
          if (c.requerido && t.isEmpty) error = 'Falta: ${c.etiqueta}.';
        case _Tipo.monto:
          if (t.isEmpty && !c.requerido) break;
          final v = parsearMonto(t);
          if (v == null || v < c.minimo) error = '${c.etiqueta}: escriba un número válido${c.minimo == 0 ? ' (cero o más)' : ''}.';
        case _Tipo.cantidad:
          if (t.isEmpty && !c.requerido) break;
          final v = parsearCantidad(t);
          if (v == null || v < c.minimo) error = '${c.etiqueta}: escriba un número válido${c.minimo == 0 ? ' (cero o más)' : ''}.';
        default:
          break;
      }
      if (error != null) {
        await avisar(context, error);
        _focos[c.clave]?.requestFocus();
        return false;
      }
    }
    return true;
  }

  Future<void> _aceptar() async {
    if (_ocupado) return;
    if (!await _validar() || !mounted) return;
    final valores = ValoresFormulario._({
      for (final e in _textos.entries) e.key: e.value.text,
      ..._opciones,
      ..._marcas,
    });
    if (widget.alAceptar != null) {
      setState(() => _ocupado = true);
      try {
        await widget.alAceptar!(valores);
      } on EmmaError catch (e) {
        if (mounted) {
          setState(() => _ocupado = false);
          await avisar(context, e.mensaje);
        }
        return;
      }
    }
    if (mounted) Navigator.pop(context, valores);
  }

  Widget _control(_Campo c) => switch (c.tipo) {
        _Tipo.texto => Casilla(
            controller: _textos[c.clave],
            foco: _focos[c.clave],
            autofocus: c == _campos.firstWhere((x) => _textos.containsKey(x.clave)),
            lineas: c.lineas,
            mayusculas: c.mayusculas,
            onSubmitted: (_) => _aceptar(),
          ),
        _Tipo.clave => Casilla(
            controller: _textos[c.clave],
            foco: _focos[c.clave],
            autofocus: c == _campos.firstWhere((x) => _textos.containsKey(x.clave)),
            oculta: true,
            onSubmitted: (_) => _aceptar(),
          ),
        _Tipo.monto || _Tipo.cantidad => Casilla(
            controller: _textos[c.clave],
            foco: _focos[c.clave],
            autofocus: c == _campos.firstWhere((x) => _textos.containsKey(x.clave)),
            derecha: true,
            onSubmitted: (_) => _aceptar(),
          ),
        _Tipo.opciones => Desplegable<Object?>(
            valor: _opciones[c.clave],
            opciones: c.opciones,
            texto: c.textoOpcion!,
            onChanged: (v) => setState(() => _opciones[c.clave] = v),
          ),
        _Tipo.casilla => Marca(
            valor: _marcas[c.clave]!,
            texto: c.etiqueta,
            onChanged: (v) => setState(() => _marcas[c.clave] = v),
          ),
        _Tipo.nota => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    final f = widget.formulario;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: f.ancho,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(f.titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                ),
                for (final c in _campos)
                  switch (c.tipo) {
                    _Tipo.nota => Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                        child: Text(c.etiqueta, style: const TextStyle(fontSize: 15, color: Estilo.atenuado)),
                      ),
                    _Tipo.casilla => Padding(padding: EdgeInsets.only(left: f.anchoEtiqueta), child: _control(c)),
                    _ => FilaCampo(etiqueta: c.etiqueta, anchoEtiqueta: f.anchoEtiqueta, child: _control(c)),
                  },
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Boton('Cancelar', anchoMinimo: 110, onPressed: _ocupado ? null : () => Navigator.pop(context)),
                    Boton('Aceptar', tipo: TipoBoton.principal, anchoMinimo: 110, onPressed: _ocupado ? null : _aceptar),
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
