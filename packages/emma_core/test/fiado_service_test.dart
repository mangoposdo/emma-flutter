import 'dart:convert';

import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

void main() {
  late EmmaDatabase db;
  late FiadoService fiado;
  late VentaService ventas;
  late Sesion dueno;
  late int pan; // RD$ 10.00

  setUp(() async {
    db = baseDePrueba();
    fiado = FiadoService(db);
    ventas = VentaService(db);
    dueno = await sesionDueno(db);
    pan = await crearProducto(db, codigo: '300', nombre: 'Pan', precio: 1000);
  });

  tearDown(() => db.close());

  Future<int> fiar(int clienteId, int panes) async => (await ventas.cobrar(
        dueno,
        SolicitudCobro(
          lineas: [LineaCobro(productoId: pan, descripcion: 'Pan', cantidad: panes * 1000, precioUnitario: 1000)],
          formaPago: FormaPago.fiado,
          clienteId: clienteId,
        ),
      ))
          .ventaId;

  test('el fiado suma deuda y el abono la reduce; el estado de cuenta lo cuenta todo', () async {
    final rosa = await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Doña Rosa', limiteCredito: 100000));
    await abrirTurno(db, dueno);
    final v1 = await fiar(rosa.id, 30); // 300
    await fiar(rosa.id, 20); // 200
    expect(await fiado.balance(rosa.id), 50000);

    await fiado.abonar(dueno, rosa.id, 15000, forma: FormaPago.transferencia, nota: 'Por el banco');
    expect(await fiado.balance(rosa.id), 35000);

    final ec = await fiado.estadoCuenta(rosa.id);
    expect(ec.map((l) => l.concepto), ['Compra #$v1', 'Compra #${v1 + 1}', 'Abono (Transferencia) - Por el banco']);
    expect(ec.last.abono, 15000);
    expect(ec.last.balance, 35000);

    final ev = await (db.select(db.eventosSalida)..where((e) => e.tipo.equals(TipoEvento.fiadoAbono))).getSingle();
    expect(jsonDecode(ev.datos), containsPair('Monto', 150));
  });

  test('el abono no puede pasar la deuda, ni ser fiado, ni hacerse con la caja cerrada', () async {
    final luis = await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Luis'));
    await expectLater(fiado.abonar(dueno, luis.id, 100), throwsA(isA<CajaCerrada>()));
    await abrirTurno(db, dueno);
    await fiar(luis.id, 5);
    await expectLater(
      fiado.abonar(dueno, luis.id, 6000),
      throwsA(isA<DatoInvalido>().having((e) => e.mensaje, 'mensaje', 'Luis solo debe RD\$ 50.00.')),
    );
    await expectLater(fiado.abonar(dueno, luis.id, 100, forma: FormaPago.fiado), throwsA(isA<DatoInvalido>()));
    await expectLater(fiado.abonar(dueno, luis.id, 0), throwsA(isA<DatoInvalido>()));
  });

  test('el cajero no puede dar ni cambiar el límite de crédito', () async {
    final maria = await crearCajero(db);
    await expectLater(
      fiado.guardarCliente(maria, const DatosCliente(nombre: 'Pedro', limiteCredito: 50000)),
      throwsA(isA<PermisoDenegado>()),
    );
    final pedro = await fiado.guardarCliente(maria, const DatosCliente(nombre: 'Pedro', telefono: '809-555-1234'));
    await expectLater(
      fiado.guardarCliente(maria, DatosCliente(id: pedro.id, nombre: 'Pedro', limiteCredito: 1)),
      throwsA(isA<PermisoDenegado>()),
    );
    // Lo demás sí lo puede cambiar.
    final cambiado = await fiado.guardarCliente(maria, DatosCliente(id: pedro.id, nombre: 'Pedro Pérez', sector: 'Los Mina'));
    expect(cambiado.sector, 'Los Mina');
  });

  test('el cumpleaños se guarda como día/mes y se revisa', () async {
    final c = await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Ana', cumpleanos: '5-8'));
    expect(c.cumpleanos, '05/08');
    await expectLater(fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Ana', cumpleanos: '31/02')), throwsA(isA<DatoInvalido>()));
  });

  test('la lista busca por nombre o teléfono y pone los fijos primero', () async {
    await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Beto', esFijo: false));
    await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'Zoila', telefono: '8095551234'));
    expect((await fiado.clientes()).map((c) => c.nombre), ['Zoila', 'Beto']);
    expect((await fiado.clientes(texto: '555')).single.nombre, 'Zoila');
  });

  test('los deudores salen de mayor a menor con los días sin pagar', () async {
    final a = await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'A'));
    final b = await fiado.guardarCliente(dueno, const DatosCliente(nombre: 'B'));
    await abrirTurno(db, dueno);
    await fiar(a.id, 1);
    await fiar(b.id, 3);
    final d = await fiado.deudores();
    expect(d.map((x) => x.cliente.nombre), ['B', 'A']);
    expect(d.first.diasSinPagar(horaPrueba.add(const Duration(days: 3))), 3);
    expect(await fiado.totalEnLaCalle(), 4000);
  });
}
