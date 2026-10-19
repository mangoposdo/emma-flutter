import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/formulario.dart';
import 'editor_producto.dart';

const _unidades = [UnidadVenta.unidad, UnidadVenta.libra];
const _itbis = [0, 1600, 1800];

String textoUnidad(UnidadVenta u) => switch (u) {
      UnidadVenta.unidad => 'Unidad',
      UnidadVenta.libra => 'Libra',
    };

/// Abre el formulario del producto (nuevo o editar). También se usa al escanear
/// un código que no existe, con [codigo] ya puesto, y al crear un producto de
/// una factura leída, con [nombre] y [costo] (centavos) ya puestos. Devuelve el
/// producto guardado, o null si cancelan. Solo el dueño.
Future<Producto?> editarProducto(
  BuildContext context,
  WidgetRef ref, {
  Producto? producto,
  String? codigo,
  String? nombre,
  int? costo,
}) async {
  final editor = ref.read(editorProductoProvider);
  final actual = producto == null ? null : (await editor.porId(producto.id) ?? producto);
  final nuevo = actual == null;
  var datos = DatosProducto(
    id: actual?.id,
    codigo: actual?.codigo ?? codigo,
    nombre: actual?.nombre ?? nombre ?? '',
    categoria: await editor.nombreCategoria(actual?.categoriaId),
    unidad: actual?.unidad ?? UnidadVenta.unidad,
    costo: actual?.costo ?? costo ?? 0,
    precio: actual?.precio ?? 0,
    existenciaMinima: actual?.existenciaMinima ?? 0,
    tasaItbis: _itbis.contains(actual?.tasaItbis) ? actual!.tasaItbis : 0,
    esRapido: actual?.esRapido ?? false,
    activo: actual?.activo ?? true,
  );
  if (!context.mounted) return null;

  Producto? guardado;
  // Si dicen que no a "El precio es menor que el costo", el formulario vuelve
  // a salir con lo que escribieron, como en la 0.7.
  var otraVez = true;
  while (otraVez && context.mounted) {
    otraVez = false;
    final f = Formulario(nuevo ? 'Nuevo producto' : 'Editar producto', ancho: 520)
        .texto('codigo', 'Código de barras', valor: datos.codigo)
        .texto('nombre', 'Nombre', valor: datos.nombre, requerido: true)
        .texto('categoria', 'Categoría', valor: datos.categoria)
        .opciones('unidad', 'Se vende por', _unidades, datos.unidad, textoUnidad)
        .monto('costo', 'Costo RD\$', valor: datos.costo)
        .monto('precio', 'Precio RD\$', valor: datos.precio);
    if (nuevo) f.cantidad('existencia', 'Existencia inicial', valor: datos.existencia);
    f
        .cantidad('minimo', 'Existencia mínima', valor: datos.existenciaMinima)
        .opciones('itbis', 'ITBIS (para la Fase 2)', _itbis, datos.tasaItbis, (t) => '${t ~/ 100}%')
        .casilla('rapido', 'Botón rápido en ventas', datos.esRapido)
        .casilla('activo', 'Activo (se puede vender)', datos.activo)
        .nota('Para corregir la existencia de un producto que ya existe use "Ajustar existencia".');
    await f.mostrar(context, alAceptar: (v) async {
      datos = DatosProducto(
        id: actual?.id,
        codigo: v.txtONulo('codigo'),
        nombre: v.txt('nombre'),
        categoria: v.txtONulo('categoria'),
        unidad: v.opcion<UnidadVenta>('unidad'),
        costo: v.monto('costo'),
        precio: v.monto('precio'),
        existencia: nuevo ? v.cantidad('existencia') : 0,
        existenciaMinima: v.cantidad('minimo'),
        tasaItbis: v.opcion<int>('itbis'),
        esRapido: v.marcado('rapido'),
        activo: v.marcado('activo'),
      );
      if (datos.precio < datos.costo &&
          context.mounted &&
          !await confirmar(context, 'El precio es menor que el costo. ¿Guardar de todos modos?')) {
        otraVez = true;
        return;
      }
      guardado = await editor.guardar(datos);
    });
  }
  return guardado;
}
