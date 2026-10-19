import 'dart:convert';
import 'dart:typed_data';

import 'package:emma_core/emma_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  test('normaliza los nombres de la factura', () {
    expect(Emparejador.normalizar('Arroz SELECTO 25Lbs.'), 'arroz selecto 25 lb');
    expect(Emparejador.normalizar('Aceite Crisol 1/2 Galón'), 'aceite crisol 1 2 galon');
    expect(Emparejador.normalizar('LECHE RICA 1LT'), 'leche rica 1 l');
    expect(Emparejador.normalizar('  '), '');
  });

  test('un tamaño distinto no se confunde', () {
    expect(Emparejador.parecido('arroz selecto 25 lb', 'arroz selecto 10 lb'), lessThan(Emparejador.minimoParecido));
    expect(Emparejador.parecido('arroz sel 25 lb', 'arroz selecto 25 lb'), greaterThanOrEqualTo(Emparejador.minimoParecido));
  });

  test('empareja por código, nombre y parecido, y aprende lo que escoge el dueño', () async {
    final db = baseDePrueba();
    addTearDown(db.close);
    final dueno = await sesionDueno(db);
    final compras = CompraService(db);
    final arroz = await crearProducto(db, codigo: '7460001000011', nombre: 'Arroz Selecto 25 lb', precio: 150000, costo: 125000);
    final leche = await crearProducto(db, codigo: 'L1', nombre: 'Leche Rica 1 L', precio: 9500, costo: 8000);
    final salami = await crearProducto(db, codigo: 'S1', nombre: 'Salami Induveca', precio: 15000, costo: 11000);
    final malta = await crearProducto(db, codigo: 'M1', nombre: 'Malta Morena 12 oz', precio: 4500, costo: 3200, existencia: 10000);

    const factura = FacturaLeida(suplidor: 'Distribuidora Ramos', factura: 'B-0042', lineas: [
      LineaFacturaLeida(descripcion: 'ARROZ 25LB', codigo: '7460001000011', cantidad: 2000, costo: 126000, total: 252000),
      LineaFacturaLeida(descripcion: 'LECHE RICA 1LT', cantidad: 12000, costo: 8200, total: 98400),
      LineaFacturaLeida(descripcion: 'SALAMI INDUV.', cantidad: 5000, costo: 11500, total: 57500),
      LineaFacturaLeida(descripcion: 'MALTA MOR 12OZ CJ24', cantidad: 1000, costo: 72000, total: 72000),
    ]);

    final r = await compras.emparejar(factura);
    expect((r[0].producto?.id, r[0].seguro), (arroz, true));
    expect((r[1].producto?.id, r[1].seguro), (leche, true));
    expect((r[2].producto?.id, r[2].seguro), (salami, false));
    expect(r[3].producto, isNull);

    // El dueño escoge la malta y guarda: la próxima factura de Ramos ya la trae.
    await compras.registrar(dueno, SolicitudCompra(suplidor: 'Distribuidora Ramos', factura: 'B-0042', pago: PagoCompra.porFuera, lineas: [
      LineaCompra(productoId: arroz, cantidad: 2000, costo: 126000, textoFactura: 'ARROZ 25LB'),
      LineaCompra(productoId: malta, cantidad: 24000, costo: 3000, textoFactura: 'MALTA MOR 12OZ CJ24'),
      LineaCompra(productoId: salami, cantidad: 5000, costo: 11500, textoFactura: 'SALAMI INDUV.'),
    ]));
    expect((await producto(db, malta)).existencia, 34000);

    final otra = await compras.emparejar(factura);
    expect((otra[3].producto?.id, otra[3].seguro), (malta, true));
    expect(otra[2].seguro, isTrue);

    // Guardar otra vez el mismo texto no repite el alias.
    await compras.registrar(dueno, SolicitudCompra(suplidor: 'Distribuidora Ramos', pago: PagoCompra.porFuera, lineas: [
      LineaCompra(productoId: malta, cantidad: 24000, costo: 3000, textoFactura: 'malta mor 12oz cj24'),
    ]));
    expect(await contar(db, 'alias_productos'), 3);
  });

  test('leer la factura manda la foto a la nube con la autorización de la caja', () async {
    final db = baseDePrueba();
    addTearDown(db.close);
    final dueno = await sesionDueno(db);
    late http.Request pedido;
    final cliente = MockClient((req) async {
      pedido = req;
      if (req.url.path == '/api/caja/activar') {
        return http.Response(jsonEncode({'cajaId': 'c1', 'llave': 'k', 'negocio': 'N', 'caja': 'C'}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(
        jsonEncode({
          'suplidor': 'Distribuidora Ramos',
          'factura': 'B-1',
          'lineas': [
            {'descripcion': 'ARROZ 25LB', 'codigo': null, 'cantidad': 2, 'costo': 1260.5, 'total': 2521},
          ],
          'total': 2521,
          'nota': null,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final nube = NubeService(db, version: '1.0.0', cliente: cliente, direccion: 'https://emma.test');
    await expectLater(nube.leerFactura(dueno, Uint8List(3), 'image/jpeg'), throwsA(isA<DatoInvalido>()));
    await nube.conectar(dueno, 'X');
    final f = await nube.leerFactura(dueno, Uint8List.fromList([1, 2, 3]), 'image/png');
    expect(pedido.url.path, '/api/caja/leer-factura');
    expect(pedido.headers['Authorization'], 'Emma c1.k');
    expect(jsonDecode(pedido.body), {'archivo': 'AQID', 'tipo': 'image/png'});
    expect(f.suplidor, 'Distribuidora Ramos');
    expect(f.lineas.single.cantidad, 2000);
    expect(f.lineas.single.costo, 126050);
    expect(f.total, 252100);
    expect(NubeService.tipoFactura('foto.PNG'), 'image/png');
    expect(NubeService.tipoFactura('f.pdf'), 'application/pdf');
    expect(NubeService.tipoFactura('f.jpeg'), 'image/jpeg');

    final cajero = await crearCajero(db);
    await expectLater(nube.leerFactura(cajero, Uint8List(1), 'image/jpeg'), throwsA(isA<PermisoDenegado>()));
  });
}
