import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import '../../plataforma/archivos.dart';
import 'producto_formulario.dart';
import 'productos_view_model.dart';

const _grisInactivo = Color(0xFF808080);

/// Productos e inventario, como la 0.7: buscar, la tabla con los que se están
/// agotando en amarillo, y los botones de abajo.
class ProductosView extends ConsumerStatefulWidget {
  const ProductosView({super.key});

  @override
  ConsumerState<ProductosView> createState() => _ProductosViewState();
}

class _ProductosViewState extends ConsumerState<ProductosView> {
  final _buscar = TextEditingController();

  ProductosViewModel get _vm => ref.read(productosViewModelProvider.notifier);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Producto? get _seleccionado => ref.read(productosViewModelProvider).value?.seleccionado;

  Future<void> _nuevo() async {
    if (await editarProducto(context, ref) != null) await _vm.recargar();
  }

  Future<void> _editar() async {
    final s = ref.read(productosViewModelProvider).value;
    final p = s?.seleccionado;
    if (s == null || !s.esDueno || p == null) return;
    if (await editarProducto(context, ref, producto: p) != null) await _vm.recargar();
  }

  Future<void> _ajustar() async {
    final p = _seleccionado;
    if (p == null) return informar(context, 'Seleccione un producto.');
    await Formulario('Ajustar: ${p.nombre}', ancho: 500)
        .opciones('tipo', 'Motivo', motivosAjuste, TipoMovInventario.ajuste, textoMotivo)
        .cantidad('cantidad', 'Cantidad')
        .texto('nota', 'Nota')
        .nota('Existencia actual: ${formatoCantidad(p.existencia)}. En "Conteo físico" escriba lo que contó; '
            'en los otros, cuánto entra o sale.')
        .mostrar(context,
            alAceptar: (v) =>
                _vm.ajustar(p.id, v.opcion<TipoMovInventario>('tipo'), v.cantidad('cantidad'), v.txtONulo('nota')));
  }

  Future<void> _movimientos() async {
    final p = _seleccionado;
    if (p == null) return informar(context, 'Seleccione un producto.');
    final movs = await _vm.movimientos(p.id);
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _Movimientos(producto: p, movimientos: movs));
  }

  Future<void> _importar() async {
    await informar(
      context,
      'El archivo debe ser CSV (en Excel: Guardar como > CSV) con estas columnas en la primera fila:\n\n'
      'codigo, nombre, categoria, costo, precio, existencia, minimo, unidad\n\n'
      'En "unidad" escriba unidad o libra. Si un código ya existe se actualiza el precio, no la existencia.',
    );
    final ruta = await escogerArchivo(descripcion: 'Archivo CSV', extensiones: ['csv']);
    if (ruta == null || !mounted) return;
    await intentar(context, () async {
      final msg = await _vm.importar(ruta);
      if (mounted) await informar(context, msg);
    });
  }

  Future<void> _exportar() async {
    final ruta = await escogerDondeGuardar(
      nombre: nombreExportacion(DateTime.now()),
      descripcion: 'Archivo CSV',
      extensiones: ['csv'],
    );
    if (ruta == null || !mounted) return;
    await intentar(context, () async {
      final destino = await _vm.exportar(ruta);
      if (mounted) await informar(context, 'Exportado a $destino');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(productosViewModelProvider).value;
    final dueno = s?.esDueno ?? false;
    VoidCallback? soloDueno(Future<void> Function() accion) => dueno ? () => accion() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloPantalla('Productos e inventario'),
        Row(
          children: [
            Expanded(
              child: Casilla(
                controller: _buscar,
                autofocus: true,
                mensaje: 'Buscar por nombre o código',
                onChanged: _vm.buscar,
              ),
            ),
            Marca(
                valor: s?.verInactivos ?? false,
                texto: 'Ver desactivados',
                onChanged: s == null ? null : _vm.verInactivos),
            Marca(
                valor: s?.soloBajoMinimo ?? false,
                texto: 'Solo por agotarse',
                onChanged: s == null ? null : _vm.soloBajoMinimo),
          ],
        ),
        Expanded(
          child: Tabla<ProductoListado>(
            filas: s?.filas ?? const [],
            escogida: s?.escogida,
            alEscoger: _vm.escoger,
            alAbrir: (_) => _editar(),
            colorFila: (f) => f.bajoMinimo ? Estilo.amarillo : null,
            colorTexto: (f) => f.producto.activo ? null : _grisInactivo,
            columnas: [
              Columna('Código', (f) => f.producto.codigo ?? '', ancho: 150),
              Columna('Nombre', (f) => f.producto.nombre),
              Columna('Categoría', (f) => f.categoria ?? '', ancho: 140),
              Columna('Unidad', (f) => textoUnidad(f.producto.unidad), ancho: 90),
              Columna('Costo', (f) => formatoMonto(f.producto.costo), ancho: 100, derecha: true),
              Columna('Precio', (f) => formatoMonto(f.producto.precio), ancho: 100, derecha: true),
              Columna('Existencia', (f) => formatoCantidad(f.producto.existencia), ancho: 100, derecha: true),
              Columna('Mínimo', (f) => formatoCantidad(f.producto.existenciaMinima), ancho: 90, derecha: true),
              Columna('Rápido', (f) => '', ancho: 70, celda: (f) => celdaMarcada(f.producto.esRapido)),
            ],
          ),
        ),
        TextoGris(s?.resumen ?? ''),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            children: [
              if (dueno)
                Boton('Nuevo producto', tipo: TipoBoton.principal, onPressed: soloDueno(_nuevo))
              else
                const Tooltip(
                  message: 'Solo el dueño puede modificar productos',
                  child: Boton('Nuevo producto', tipo: TipoBoton.principal, onPressed: null),
                ),
              Boton('Editar', onPressed: soloDueno(_editar)),
              Boton('Ajustar existencia', onPressed: soloDueno(_ajustar)),
              Boton('Ver movimientos', onPressed: _movimientos),
              Boton('Importar desde Excel (CSV)', onPressed: soloDueno(_importar)),
              Boton('Exportar a Excel', onPressed: _exportar),
            ],
          ),
        ),
      ],
    );
  }
}

/// La ventanita "Movimientos: producto".
class _Movimientos extends StatelessWidget {
  const _Movimientos({required this.producto, required this.movimientos});

  final Producto producto;
  final List<MovimientoInventario> movimientos;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 760,
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
                        child: Text('Movimientos: ${producto.nombre}',
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
                  height: 420,
                  child: Tabla<MovimientoInventario>(
                    filas: movimientos,
                    columnas: [
                      Columna('Fecha', (m) => formatoFechaHora(m.fecha), ancho: 190),
                      Columna('Tipo', (m) => etiquetaMovimiento(m.tipo), ancho: 140),
                      Columna('Cantidad', (m) => '${m.cantidad < 0 ? '-' : '+'}${formatoCantidad(m.cantidad.abs())}',
                          ancho: 90),
                      Columna('Queda', (m) => formatoCantidad(m.existenciaResultante), ancho: 90),
                      Columna('Referencia', (m) => m.referencia ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
