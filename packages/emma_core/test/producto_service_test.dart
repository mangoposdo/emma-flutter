import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late ProductoService productos;

  setUp(() async {
    db = baseDePrueba();
    productos = ProductoService(db);
    await crearProducto(db, codigo: '7460001', nombre: 'Refresco Country Club 2 L', precio: 9500);
    await crearProducto(db, codigo: '7460002', nombre: 'Aceite Crisol 32 oz', precio: 16500);
    await crearProducto(db, codigo: '200', nombre: 'Arroz Selecto', precio: 4500, unidad: UnidadVenta.libra);
  });

  tearDown(() => db.close());

  Future<void> marcar(String codigo, ProductosCompanion cambio) =>
      (db.update(db.productos)..where((p) => p.codigo.equals(codigo))).write(cambio);

  group('por código', () {
    test('encuentra el producto exacto, sin espacios de más', () async {
      final p = await productos.porCodigo(' 7460002 ');
      expect(p?.nombre, 'Aceite Crisol 32 oz');
    });

    test('un código que no existe da null', () async {
      expect(await productos.porCodigo('999'), isNull);
      expect(await productos.porCodigo(''), isNull);
    });

    test('no devuelve Varios ni productos inactivos', () async {
      await marcar('200', const ProductosCompanion(activo: Value(false)));
      expect(await productos.porCodigo(codigoVarios), isNull);
      expect(await productos.porCodigo('200'), isNull);
    });
  });

  group('buscar', () {
    test('por parte del nombre, sin importar mayúsculas, en orden alfabético', () async {
      final r = await productos.buscar('O');
      expect(r.map((p) => p.nombre), ['Aceite Crisol 32 oz', 'Arroz Selecto', 'Refresco Country Club 2 L']);
    });

    test('primero los que empiezan con lo escrito, luego por palabra', () async {
      await crearProducto(db, codigo: '201', nombre: 'Azúcar crema', precio: 4000);
      await crearProducto(db, codigo: '202', nombre: 'Pan de arroz', precio: 1500);
      final r = await productos.buscar('ar');
      expect(r.map((p) => p.nombre), ['Arroz Selecto', 'Pan de arroz', 'Azúcar crema']);
    });

    test('por el comienzo del código', () async {
      final r = await productos.buscar('7460');
      expect(r.map((p) => p.codigo), ['7460002', '7460001']);
    });

    test('los comodines de LIKE se buscan tal cual', () async {
      expect(await productos.buscar('%'), isEmpty);
      expect(await productos.buscar('_'), isEmpty);
    });

    test('texto vacío no busca nada', () async {
      expect(await productos.buscar('   '), isEmpty);
    });

    test('respeta el límite', () async {
      expect(await productos.buscar('a', limite: 1), hasLength(1));
    });

    test('no trae Varios ni inactivos', () async {
      await marcar('7460001', const ProductosCompanion(activo: Value(false)));
      final r = await productos.buscar('r');
      expect(r.map((p) => p.nombre), ['Aceite Crisol 32 oz', 'Arroz Selecto']);
      expect(r.where((p) => p.codigo == codigoVarios), isEmpty);
    });
  });

  test('rápidos: solo los marcados y activos', () async {
    await marcar('200', const ProductosCompanion(esRapido: Value(true)));
    await marcar('7460001', const ProductosCompanion(esRapido: Value(true), activo: Value(false)));
    final r = await productos.rapidos();
    expect(r.map((p) => p.codigo), ['200']);
  });
}
