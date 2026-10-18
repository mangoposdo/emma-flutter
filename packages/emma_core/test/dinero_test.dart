import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

void main() {
  group('formato de montos', () {
    test('miles con coma y dos decimales', () {
      expect(formatoMonto(123450), '1,234.50');
      expect(formatoMonto(5), '0.05');
      expect(formatoMonto(100000000), '1,000,000.00');
      expect(formatoMonto(-123450), '-1,234.50');
      expect(formatoRD(11750), 'RD\$ 117.50');
    });
  });

  group('leer montos', () {
    test('acepta las formas que se escriben en la caja', () {
      expect(parsearMonto('50'), 5000);
      expect(parsearMonto('\$50'), 5000);
      expect(parsearMonto('RD\$ 1,234.5'), 123450);
      expect(parsearMonto('0.05'), 5);
    });
    test('rechaza lo que no es monto', () {
      expect(parsearMonto('abc'), isNull);
      expect(parsearMonto('1.234'), isNull);
      expect(parsearMonto(''), isNull);
      expect(parsearMonto('-5'), isNull);
    });
  });

  group('cantidades', () {
    test('libras y unidades en milésimas', () {
      expect(parsearCantidad('3'), 3000);
      expect(parsearCantidad('0.5'), 500);
      expect(parsearCantidad('1.25'), 1250);
      expect(parsearCantidad('1.2345'), isNull);
      expect(formatoCantidad(1429), '1.429');
      expect(formatoCantidad(3000), '3');
      expect(formatoCantidad(500), '0.5');
    });

    test('total de línea redondea al centavo, la mitad sube', () {
      expect(totalLinea(5000, 3000), 15000); // 3 x 50.00
      expect(totalLinea(3500, 500), 1750); // 0.5 lb x 35.00
      expect(totalLinea(3333, 500), 1667); // 16.665 -> 16.67
      expect(totalLinea(3333, 1500), 5000); // 49.995 -> 50.00
    });

    test('cantidad por monto', () {
      expect(cantidadPorMonto(5000, 3500), 1429);
      expect(cantidadPorMonto(3500, 3500), 1000);
      expect(() => cantidadPorMonto(5000, 0), throwsArgumentError);
    });
  });

  test('montos para el JSON de la nube', () {
    expect(montoJson(11750), 117.5);
    expect(montoJson(5000), 50);
    expect(montoJson(5), 0.05);
    expect(cantidadJson(500), 0.5);
    expect(cantidadJson(2000), 2);
  });

  test('fecha de evento en hora local sin zona', () {
    expect(fechaLocalIso(DateTime(2026, 1, 5, 7, 3, 9)), '2026-01-05T07:03:09');
  });
}
