import 'package:drift/drift.dart';
import 'package:emma_core/emma_core.dart';

/// Productos de colmado para probar la caja en modo debug. Solo se siembran en
/// una base nueva (la que
/// solo tiene los productos internos "Varios" y el envío). Precios en
/// centavos, existencia en milésimas.
Future<void> sembrarDatosDePrueba(EmmaDatabase db) async {
  final hay = await db.select(db.productos).get();
  if (hay.any((p) => !esServicio(p))) return;

  const lista = <(String, String, int, int, UnidadVenta, bool)>[
    // (código, nombre, precio, existencia, unidad, venta rápida)
    ('200', 'Arroz Selecto', 4500, 50000, UnidadVenta.libra, true),
    ('201', 'Habichuelas rojas', 9000, 20000, UnidadVenta.libra, false),
    ('202', 'Azúcar crema', 4000, 30000, UnidadVenta.libra, true),
    ('203', 'Salami Induveca', 19000, 10000, UnidadVenta.libra, true),
    ('204', 'Queso de freír', 22000, 8000, UnidadVenta.libra, false),
    ('300', 'Pan de agua', 1000, 100000, UnidadVenta.unidad, true),
    ('301', 'Huevo', 1000, 90000, UnidadVenta.unidad, true),
    ('302', 'Plátano', 2500, 60000, UnidadVenta.unidad, true),
    ('7460001', 'Refresco Country Club 2 L', 9500, 24000, UnidadVenta.unidad, true),
    ('7460002', 'Aceite Crisol 32 oz', 16500, 12000, UnidadVenta.unidad, false),
    ('7460003', 'Agua 20 oz', 2500, 48000, UnidadVenta.unidad, false),
    ('7460004', 'Leche 1 L', 9000, 18000, UnidadVenta.unidad, false),
    ('7460005', 'Café molido 1 lb', 26000, 10000, UnidadVenta.unidad, false),
    ('7460006', 'Jabón de cuaba', 3500, 20000, UnidadVenta.unidad, false),
    ('7460007', 'Sopita de pollo (tira)', 1500, 40000, UnidadVenta.unidad, false),
  ];

  await db.batch((b) {
    b.insertAll(db.productos, [
      for (final (codigo, nombre, precio, existencia, unidad, rapido) in lista)
        ProductosCompanion.insert(
          codigo: Value(codigo),
          nombre: nombre,
          precio: precio,
          costo: Value(precio * 3 ~/ 4),
          existencia: Value(existencia),
          unidad: Value(unidad),
          esRapido: Value(rapido),
        ),
    ]);
  });
}
