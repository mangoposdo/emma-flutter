import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Lo que el formulario del producto necesita del núcleo. No tiene estado y
/// vive mientras viva la app: el formulario se abre desde Productos, Ventas y
/// Compras.
final editorProductoProvider = Provider<EditorProducto>(EditorProducto.new);

class EditorProducto {
  EditorProducto(this._ref);

  final Ref _ref;

  ProductoService get _productos => _ref.read(productoServiceProvider);

  Future<Producto?> porId(int id) => _productos.porId(id);

  Future<String?> nombreCategoria(int? id) async {
    if (id == null) return null;
    return (await _productos.categorias()).where((c) => c.id == id).firstOrNull?.nombre;
  }

  Future<Producto> guardar(DatosProducto d) => _productos.guardar(_ref.sesion, d);
}
