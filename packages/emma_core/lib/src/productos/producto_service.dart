import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../formato.dart';
import '../reportes/csv.dart';
import '../sesion.dart';

/// Lo que se escribe en el formulario de un producto. Montos en centavos,
/// cantidades en milésimas. [id] null = producto nuevo.
class DatosProducto {
  const DatosProducto({
    this.id,
    this.codigo,
    required this.nombre,
    this.categoria,
    this.costo = 0,
    required this.precio,
    this.existencia = 0,
    this.existenciaMinima = 0,
    this.unidad = UnidadVenta.unidad,
    this.esRapido = false,
    this.activo = true,
    this.tasaItbis = 0,
  });

  final int? id;
  final String? codigo;
  final String nombre;

  /// Nombre de la categoría; si no existe se crea.
  final String? categoria;
  final int costo;
  final int precio;

  /// Solo al crear. La de un producto que ya existe se cambia con un ajuste.
  final int existencia;
  final int existenciaMinima;
  final UnidadVenta unidad;
  final bool esRapido;
  final bool activo;

  /// Centésimas de por ciento: 0, 1600 o 1800.
  final int tasaItbis;
}

/// Una fila de la lista de productos, con el nombre de su categoría.
class ProductoListado {
  const ProductoListado(this.producto, this.categoria);

  final Producto producto;
  final String? categoria;

  bool get bajoMinimo => producto.activo && producto.existencia <= producto.existenciaMinima;
}

class ResultadoImportacion {
  const ResultadoImportacion(this.creados, this.actualizados, this.errores);

  final int creados;
  final int actualizados;
  final List<String> errores;
}

/// Productos e inventario.
///
/// Las listas nunca traen los productos de servicio ("Varios" y el envío):
/// esos se usan solos desde la venta y el delivery.
class ProductoService {
  ProductoService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  Expression<bool> _noServicio(Productos p) =>
      p.codigo.isNull() | p.codigo.isNotIn(const [codigoVarios, codigoEnvio]);

  Expression<bool> _vendible(Productos p) => p.activo.equals(true) & _noServicio(p);

  /// Lo que manda el lector de código de barras.
  Future<Producto?> porCodigo(String codigo) {
    final c = codigo.trim();
    if (c.isEmpty) return Future.value(null);
    return (db.select(db.productos)..where((p) => _vendible(p) & p.codigo.equals(c))).getSingleOrNull();
  }

  Future<Producto?> porId(int id) =>
      (db.select(db.productos)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Map<int, Producto>> porIds(Iterable<int> ids) async {
    final lista = ids.toSet().toList();
    if (lista.isEmpty) return {};
    final ps = await (db.select(db.productos)..where((p) => p.id.isIn(lista))).get();
    return {for (final p in ps) p.id: p};
  }

  /// Por parte del nombre o por el comienzo del código, en orden alfabético.
  Future<List<Producto>> buscar(String texto, {int limite = 20, bool incluirInactivos = false}) {
    // % y _ son comodines de LIKE: se quitan para que busquen tal cual.
    final t = texto.trim().replaceAll(RegExp('[%_]'), '');
    if (t.isEmpty) return Future.value(const []);
    return (db.select(db.productos)
          ..where((p) =>
              (incluirInactivos ? _noServicio(p) : _vendible(p)) &
              (p.nombre.like('%$t%') | p.codigo.like('$t%')))
          // Primero los que empiezan con lo escrito, después los que tienen una
          // palabra que empieza así ("arr" → "Pan de arroz"), y el resto.
          ..orderBy([
            (p) => OrderingTerm.desc(p.nombre.like('$t%')),
            (p) => OrderingTerm.desc(p.nombre.like('% $t%')),
            (p) => OrderingTerm.asc(p.nombre),
          ])
          ..limit(limite))
        .get();
  }

  /// La pantalla de productos: con su categoría, hasta 500.
  Future<List<ProductoListado>> listado({String texto = '', bool incluirInactivos = false}) async {
    final t = texto.trim().replaceAll(RegExp('[%_]'), '');
    final q = db.select(db.productos).join([
      leftOuterJoin(db.categorias, db.categorias.id.equalsExp(db.productos.categoriaId)),
    ]);
    var filtro = incluirInactivos ? _noServicio(db.productos) : _vendible(db.productos);
    if (t.isNotEmpty) {
      filtro = filtro & (db.productos.nombre.like('%$t%') | db.productos.codigo.like('$t%'));
    }
    q
      ..where(filtro)
      ..orderBy([OrderingTerm.asc(db.productos.nombre)])
      ..limit(500);
    final filas = await q.get();
    return [
      for (final f in filas) ProductoListado(f.readTable(db.productos), f.readTableOrNull(db.categorias)?.nombre),
    ];
  }

  /// Los botones de venta rápida.
  Future<List<Producto>> rapidos() => (db.select(db.productos)
        ..where((p) => _vendible(p) & p.esRapido.equals(true))
        ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
      .get();

  /// Activos con la existencia en el mínimo o por debajo (todos, sin el tope de [listado]).
  Future<List<ProductoListado>> bajoMinimo() async {
    final q = db.select(db.productos).join([
      leftOuterJoin(db.categorias, db.categorias.id.equalsExp(db.productos.categoriaId)),
    ])
      ..where(_vendible(db.productos) & db.productos.existencia.isSmallerOrEqual(db.productos.existenciaMinima))
      ..orderBy([OrderingTerm.asc(db.productos.nombre)]);
    final filas = await q.get();
    return [
      for (final f in filas) ProductoListado(f.readTable(db.productos), f.readTableOrNull(db.categorias)?.nombre),
    ];
  }

  Future<List<Categoria>> categorias() =>
      (db.select(db.categorias)..orderBy([(c) => OrderingTerm.asc(c.nombre)])).get();

  Future<int> _categoriaId(String nombre) async {
    final n = nombre.trim();
    final c = await (db.select(db.categorias)..where((x) => x.nombre.equals(n))).getSingleOrNull();
    if (c != null) return c.id;
    return db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: n));
  }

  /// Crea o modifica un producto. Solo el dueño.
  Future<Producto> guardar(Sesion sesion, DatosProducto d) async {
    requiereDueno(sesion.esDueno, 'modificar productos');
    final nombre = d.nombre.trim();
    if (nombre.isEmpty) throw const DatoInvalido('El producto necesita un nombre.');
    if (d.precio < 0 || d.costo < 0) throw const DatoInvalido('El precio y el costo no pueden ser negativos.');
    if (d.existenciaMinima < 0) throw const DatoInvalido('La existencia mínima no puede ser negativa.');
    if (!const [0, 1600, 1800].contains(d.tasaItbis)) throw const DatoInvalido('El ITBIS debe ser 0, 16 o 18.');
    final codigo = _limpio(d.codigo);
    if (codigo == codigoVarios || codigo == codigoEnvio) {
      throw DatoInvalido('El código $codigo está reservado.');
    }
    final fecha = _reloj();

    return db.transaction(() async {
      if (codigo != null) {
        final otro = await (db.select(db.productos)
              ..where((p) => p.codigo.equals(codigo) & (d.id == null ? const Constant(true) : p.id.equals(d.id!).not())))
            .getSingleOrNull();
        if (otro != null) throw DatoInvalido('Ya existe otro producto con el código $codigo.');
      }
      final categoriaId = _limpio(d.categoria) == null ? null : await _categoriaId(d.categoria!);
      final datos = ProductosCompanion(
        codigo: Value(codigo),
        nombre: Value(nombre),
        categoriaId: Value(categoriaId),
        costo: Value(d.costo),
        precio: Value(d.precio),
        existenciaMinima: Value(d.existenciaMinima),
        unidad: Value(d.unidad),
        esRapido: Value(d.esRapido),
        activo: Value(d.activo),
        tasaItbis: Value(d.tasaItbis),
      );

      if (d.id == null) {
        if (d.unidad == UnidadVenta.unidad && d.existencia % milesimasPorUnidad != 0) {
          throw DatoInvalido('$nombre se cuenta por unidad: la existencia va sin decimales.');
        }
        final id = await db.into(db.productos).insert(datos.copyWith(existencia: Value(d.existencia)));
        if (d.existencia != 0) {
          await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
                productoId: id,
                fecha: fecha,
                tipo: TipoMovInventario.inventarioInicial,
                cantidad: d.existencia,
                existenciaResultante: d.existencia,
                usuarioId: Value(sesion.usuarioId),
              ));
        }
        await db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Producto creado', detalle: nombre, fecha: fecha);
        return (await porId(id))!;
      }

      final antes = await porId(d.id!);
      if (antes == null) throw const DatoInvalido('El producto no existe.');
      if (esServicio(antes)) throw const DatoInvalido('Ese producto es interno y no se cambia.');
      if (antes.precio != d.precio) {
        await db.anotarBitacora(
          usuarioId: sesion.usuarioId,
          accion: 'Cambio de precio',
          detalle: '${antes.nombre}: ${formatoRD(antes.precio)} -> ${formatoRD(d.precio)}',
          fecha: fecha,
        );
      }
      await (db.update(db.productos)..where((p) => p.id.equals(d.id!))).write(datos);
      return (await porId(d.id!))!;
    });
  }

  /// Corrige la existencia: [cantidad] (milésimas) positiva entra, negativa sale.
  /// Solo el dueño.
  Future<Producto> ajustar(
    Sesion sesion,
    int productoId,
    int cantidad,
    TipoMovInventario tipo, {
    String? nota,
  }) async {
    requiereDueno(sesion.esDueno, 'ajustar el inventario');
    if (cantidad == 0) throw const DatoInvalido('La cantidad del ajuste no puede ser cero.');
    final fecha = _reloj();
    return db.transaction(() async {
      final p = await porId(productoId);
      if (p == null) throw const DatoInvalido('El producto no existe.');
      if (p.unidad == UnidadVenta.unidad && cantidad % milesimasPorUnidad != 0) {
        throw DatoInvalido('${p.nombre} se cuenta por unidad: la cantidad va sin decimales.');
      }
      final nueva = p.existencia + cantidad;
      await (db.update(db.productos)..where((x) => x.id.equals(p.id)))
          .write(ProductosCompanion(existencia: Value(nueva)));
      await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
            productoId: p.id,
            fecha: fecha,
            tipo: tipo,
            cantidad: cantidad,
            existenciaResultante: nueva,
            referencia: Value(_limpio(nota)),
            usuarioId: Value(sesion.usuarioId),
          ));
      final signo = cantidad > 0 ? '+' : '-';
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Ajuste de inventario',
        detalle: '${p.nombre}: $signo${formatoCantidad(cantidad.abs())} (${etiquetaMovimiento(tipo)})'
            '${_limpio(nota) == null ? '' : ' ${nota!.trim()}'}',
        fecha: fecha,
      );
      return (await porId(p.id))!;
    });
  }

  /// Los últimos 200 movimientos del producto, del más nuevo al más viejo.
  Future<List<MovimientoInventario>> movimientos(int productoId) => (db.select(db.movimientosInventario)
        ..where((m) => m.productoId.equals(productoId))
        ..orderBy([(m) => OrderingTerm.desc(m.id)])
        ..limit(200))
      .get();

  /// Importa productos desde un CSV guardado en Excel. Columnas:
  /// codigo, nombre, categoria, costo, precio, existencia, minimo, unidad.
  /// La primera fila son los títulos. Si el código ya existe se actualizan
  /// nombre, categoría, costo, precio, mínimo y unidad (no la existencia).
  Future<ResultadoImportacion> importarCsv(Sesion sesion, String contenido) async {
    requiereDueno(sesion.esDueno, 'importar productos');
    final errores = <String>[];
    var creados = 0;
    var actualizados = 0;
    final fecha = _reloj();
    final lineas = contenido.replaceAll('﻿', '').split(RegExp(r'\r?\n'));
    if (lineas.isEmpty) return const ResultadoImportacion(0, 0, []);
    // Excel en español guarda con punto y coma.
    final titulos = lineas.first;
    final separador = ';'.allMatches(titulos).length > ','.allMatches(titulos).length ? ';' : ',';

    await db.transaction(() async {
      for (var i = 1; i < lineas.length; i++) {
        final fila = i + 1;
        final linea = lineas[i];
        if (linea.trim().isEmpty) continue;
        final c = dividirCsv(linea, separador);
        String col(int n) => n < c.length ? c[n].trim() : '';

        final nombre = col(1);
        if (nombre.isEmpty) {
          errores.add('Fila $fila: falta el nombre.');
          continue;
        }
        final precio = parsearMonto(col(4));
        if (col(4).isEmpty || precio == null) {
          errores.add('Fila $fila: precio inválido "${col(4)}".');
          continue;
        }
        final costo = col(3).isEmpty ? 0 : (parsearMonto(col(3)) ?? 0);
        final existencia = col(5).isEmpty ? 0 : (parsearCantidad(col(5)) ?? 0);
        final minimo = col(6).isEmpty ? 0 : (parsearCantidad(col(6)) ?? 0);
        final unidad = col(7).toLowerCase().startsWith('l') ? UnidadVenta.libra : UnidadVenta.unidad;
        final categoriaId = col(2).isEmpty ? null : await _categoriaId(col(2));
        final codigo = col(0).isEmpty ? null : col(0);
        if (codigo == codigoVarios || codigo == codigoEnvio) {
          errores.add('Fila $fila: el código $codigo está reservado.');
          continue;
        }

        final existente = codigo == null
            ? null
            : await (db.select(db.productos)..where((p) => p.codigo.equals(codigo))).getSingleOrNull();
        if (existente != null) {
          await (db.update(db.productos)..where((p) => p.id.equals(existente.id))).write(ProductosCompanion(
            nombre: Value(nombre),
            categoriaId: Value(categoriaId ?? existente.categoriaId),
            costo: Value(costo),
            precio: Value(precio),
            existenciaMinima: Value(minimo),
            unidad: Value(unidad),
          ));
          actualizados++;
        } else {
          final id = await db.into(db.productos).insert(ProductosCompanion.insert(
                codigo: Value(codigo),
                nombre: nombre,
                categoriaId: Value(categoriaId),
                costo: Value(costo),
                precio: precio,
                existencia: Value(existencia),
                existenciaMinima: Value(minimo),
                unidad: Value(unidad),
              ));
          if (existencia != 0) {
            await db.into(db.movimientosInventario).insert(MovimientosInventarioCompanion.insert(
                  productoId: id,
                  fecha: fecha,
                  tipo: TipoMovInventario.inventarioInicial,
                  cantidad: existencia,
                  existenciaResultante: existencia,
                  referencia: const Value('Importación'),
                  usuarioId: Value(sesion.usuarioId),
                ));
          }
          creados++;
        }
      }
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Importación de productos',
        detalle: '$creados creados, $actualizados actualizados, ${errores.length} errores',
        fecha: fecha,
      );
    });
    return ResultadoImportacion(creados, actualizados, errores);
  }

  /// Todos los productos (también los desactivados) en CSV para Excel.
  Future<String> exportarCsv() async {
    final lista = await listado(incluirInactivos: true);
    return armarCsv(
      const ['codigo', 'nombre', 'categoria', 'costo', 'precio', 'existencia', 'minimo', 'unidad', 'activo'],
      [
        for (final f in lista)
          [
            f.producto.codigo,
            f.producto.nombre,
            f.categoria,
            montoCsv(f.producto.costo),
            montoCsv(f.producto.precio),
            formatoCantidad(f.producto.existencia),
            formatoCantidad(f.producto.existenciaMinima),
            f.producto.unidad.name,
            f.producto.activo ? 'si' : 'no',
          ],
      ],
    );
  }

  static String? _limpio(String? t) {
    final x = t?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}

/// Como se nombra cada movimiento en pantalla y en la bitácora.
String etiquetaMovimiento(TipoMovInventario t) => switch (t) {
      TipoMovInventario.venta => 'Venta',
      TipoMovInventario.anulacionVenta => 'Anulación',
      TipoMovInventario.ajuste => 'Ajuste',
      TipoMovInventario.perdida => 'Pérdida',
      TipoMovInventario.compra => 'Compra',
      TipoMovInventario.inventarioInicial => 'Inventario inicial',
    };

/// "1.5 lb" o "3" para un producto.
String cantidadDe(Producto p, int milesimas) => formatoCantidadUnidad(milesimas, p.unidad);
