import 'dart:convert';
import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

const _igual = Object();

class ProductosEstado {
  const ProductosEstado({
    required this.esDueno,
    this.texto = '',
    this.verInactivos = false,
    this.soloBajoMinimo = false,
    this.filas = const [],
    this.bajos = 0,
    this.escogidaId,
  });

  /// El cajero ve todo, pero no crea, edita, ajusta ni importa.
  final bool esDueno;
  final String texto;
  final bool verInactivos;
  final bool soloBajoMinimo;
  final List<ProductoListado> filas;

  /// Por agotarse en todo el inventario, no solo en lo que se ve.
  final int bajos;
  final int? escogidaId;

  int? get escogida {
    final i = filas.indexWhere((f) => f.producto.id == escogidaId);
    return i < 0 ? null : i;
  }

  Producto? get seleccionado => escogida == null ? null : filas[escogida!].producto;

  String get resumen =>
      '${filas.length} productos mostrados${bajos > 0 ? '  ·  $bajos por agotarse (en amarillo)' : ''}';

  ProductosEstado copyWith({
    String? texto,
    bool? verInactivos,
    bool? soloBajoMinimo,
    List<ProductoListado>? filas,
    int? bajos,
    Object? escogidaId = _igual,
  }) =>
      ProductosEstado(
        esDueno: esDueno,
        texto: texto ?? this.texto,
        verInactivos: verInactivos ?? this.verInactivos,
        soloBajoMinimo: soloBajoMinimo ?? this.soloBajoMinimo,
        filas: filas ?? this.filas,
        bajos: bajos ?? this.bajos,
        escogidaId: identical(escogidaId, _igual) ? this.escogidaId : escogidaId as int?,
      );
}

/// Los motivos de "Ajustar existencia", en el orden de la 0.7.
const motivosAjuste = [TipoMovInventario.ajuste, TipoMovInventario.perdida, TipoMovInventario.compra];

String textoMotivo(TipoMovInventario t) => switch (t) {
      TipoMovInventario.perdida => 'Pérdida o daño (sale)',
      TipoMovInventario.compra => 'Llegó mercancía (entra)',
      _ => 'Conteo físico (se pone lo que hay)',
    };

/// "productos_2026-10-18.csv".
String nombreExportacion(DateTime f) =>
    'productos_${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}.csv';

/// El texto de un CSV: UTF-8 (con o sin BOM) o, si no lo es, latin1 (Excel viejo).
String leerTextoCsv(List<int> bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}

final productosViewModelProvider =
    AsyncNotifierProvider.autoDispose<ProductosViewModel, ProductosEstado>(ProductosViewModel.new);

class ProductosViewModel extends AsyncNotifier<ProductosEstado> {
  var _vuelta = 0;

  ProductoService get _productos => ref.read(productoServiceProvider);

  @override
  Future<ProductosEstado> build() async {
    final base = ProductosEstado(esDueno: ref.sesion.esDueno);
    final (filas, bajos) = await _consultar(base);
    return base.copyWith(filas: filas, bajos: bajos);
  }

  Future<(List<ProductoListado>, int)> _consultar(ProductosEstado s) async {
    final productos = _productos;
    final bajoMinimo = await productos.bajoMinimo();
    List<ProductoListado> lista;
    if (s.soloBajoMinimo) {
      // Como la 0.7: con "Solo por agotarse" se busca solo por el nombre.
      final t = s.texto.trim().toLowerCase();
      lista = t.isEmpty ? bajoMinimo : bajoMinimo.where((f) => f.producto.nombre.toLowerCase().contains(t)).toList();
    } else {
      lista = await productos.listado(texto: s.texto, incluirInactivos: s.verInactivos);
    }
    return (lista, bajoMinimo.length);
  }

  /// Vuelve a leer la lista con los filtros de ahora. Si se escribe rápido,
  /// gana la última búsqueda.
  Future<void> recargar() async {
    final s = state.value;
    if (s == null) return;
    final vuelta = ++_vuelta;
    final (filas, bajos) = await _consultar(s);
    if (!ref.mounted || vuelta != _vuelta) return;
    state = AsyncData((state.value ?? s).copyWith(filas: filas, bajos: bajos));
  }

  Future<void> _filtrar(ProductosEstado Function(ProductosEstado s) cambio) async {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(cambio(s));
    await recargar();
  }

  Future<void> buscar(String texto) => _filtrar((s) => s.copyWith(texto: texto));

  Future<void> verInactivos(bool v) => _filtrar((s) => s.copyWith(verInactivos: v));

  Future<void> soloBajoMinimo(bool v) => _filtrar((s) => s.copyWith(soloBajoMinimo: v));

  void escoger(int i) {
    final s = state.value;
    if (s == null || i < 0 || i >= s.filas.length) return;
    state = AsyncData(s.copyWith(escogidaId: s.filas[i].producto.id));
  }

  /// "Conteo físico" pone la existencia en [cantidad]; los otros motivos la
  /// suman o la restan. Si no cambia nada no se anota.
  Future<void> ajustar(int productoId, TipoMovInventario motivo, int cantidad, String? nota) async {
    final productos = _productos;
    final sesion = ref.sesion;
    final delta = switch (motivo) {
      TipoMovInventario.perdida => -cantidad,
      TipoMovInventario.compra => cantidad,
      _ => cantidad - ((await productos.porId(productoId))?.existencia ?? 0),
    };
    if (delta == 0) return;
    await productos.ajustar(sesion, productoId, delta, motivo, nota: nota);
    if (ref.mounted) await recargar();
  }

  Future<List<MovimientoInventario>> movimientos(int productoId) => _productos.movimientos(productoId);

  /// Importa el CSV de [ruta] y devuelve el resumen para mostrar.
  Future<String> importar(String ruta) async {
    final productos = _productos;
    final sesion = ref.sesion;
    try {
      final List<int> bytes;
      try {
        bytes = await File(ruta).readAsBytes();
      } on FileSystemException {
        throw const DatoInvalido('No se pudo abrir ese archivo. Si está abierto en Excel, ciérrelo y pruebe otra vez.');
      }
      final r = await productos.importarCsv(sesion, leerTextoCsv(bytes));
      var msg = 'Productos nuevos: ${r.creados}\nActualizados: ${r.actualizados}';
      if (r.errores.isNotEmpty) {
        msg += '\n\nFilas con problemas (${r.errores.length}):\n${r.errores.take(15).join('\n')}';
      }
      return msg;
    } finally {
      if (ref.mounted) await recargar();
    }
  }

  /// Guarda todos los productos en [ruta] y devuelve la ruta final.
  Future<String> exportar(String ruta) async {
    final destino = ruta.toLowerCase().endsWith('.csv') ? ruta : '$ruta.csv';
    final csv = await _productos.exportarCsv();
    try {
      await File(destino).writeAsString(csv, encoding: utf8);
    } on FileSystemException {
      throw const DatoInvalido('No se pudo guardar el archivo. Si está abierto en Excel, ciérrelo y pruebe otra vez.');
    }
    return destino;
  }
}
