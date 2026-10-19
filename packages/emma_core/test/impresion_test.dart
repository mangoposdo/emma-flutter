
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:emma_core/emma_core.dart';
import 'package:test/test.dart';

import 'ayudantes.dart';

bool _contiene(Uint8List b, List<int> parte) {
  for (var i = 0; i + parte.length <= b.length; i++) {
    var igual = true;
    for (var j = 0; j < parte.length; j++) {
      if (b[i + j] != parte[j]) {
        igual = false;
        break;
      }
    }
    if (igual) return true;
  }
  return false;
}

void main() {
  late EmmaDatabase db;
  setUp(() => db = baseDePrueba());
  tearDown(() => db.close());

  TicketVenta ejemplo({int total = 123450, FormaPago forma = FormaPago.efectivo}) => TicketVenta(
        id: 7,
        fecha: DateTime(2026, 10, 17, 19, 42),
        cajero: 'María',
        cliente: 'Doña Rosa',
        lineas: const [
          LineaTicket('Acentos: áéíóú ñ Ñ ¿?', 1000, 100000, 100000),
          LineaTicket('Arroz selecto (libra)', 5000, 4690, 23450),
        ],
        subtotal: total,
        total: total,
        formaPago: forma,
        recibido: 150000,
        devuelta: 26550,
      );

  test('el ticket tiene acentos, total, corte y gaveta', () async {
    final n = await db.negocio();
    final b = TicketEscPos.venta(n, ejemplo());
    expect(_contiene(b, codificarCp850('Acentos: áéíóú ñ Ñ ¿?')), isTrue);
    expect(_contiene(b, codificarCp850('RD\$1,234.50')), isTrue);
    expect(_contiene(b, const [0x1D, 0x56, 0x42, 0x03]), isTrue); // corte
    expect(_contiene(b, TicketEscPos.abrirGaveta), isTrue);
    expect(_contiene(b, codificarCp850('Documento no fiscal')), isTrue);
    // Con tarjeta no abre la gaveta.
    expect(_contiene(TicketEscPos.venta(n, ejemplo(forma: FormaPago.tarjeta)), TicketEscPos.abrirGaveta), isFalse);
  });

  test('la hora sale sin letras raras que la impresora no tiene', () async {
    final b = TicketEscPos.venta(await db.negocio(), ejemplo());
    expect(_contiene(b, codificarCp850('Fecha: 17/10/2026 07:42 PM')), isTrue);
  });

  test('el total sale triple si cabe y doble si no', () async {
    final n = await db.negocio();
    expect(_contiene(TicketEscPos.venta(n, ejemplo(total: 12345)), const [0x1D, 0x21, 0x22]), isTrue);
    final angosto = n.copyWith(anchoTicket: 32);
    final b = TicketEscPos.venta(angosto, ejemplo(total: 123456789));
    expect(_contiene(b, const [0x1D, 0x21, 0x22]), isFalse);
    expect(_contiene(b, const [0x1D, 0x21, 0x11]), isTrue);
  });

  test('el ticket oscuro deja la negrita puesta todo el ticket', () async {
    final n = await db.negocio();
    final oscuro = TicketEscPos.venta(n.copyWith(ticketOscuro: true), ejemplo());
    expect(_contiene(oscuro, const [0x1B, 0x45, 0x00]), isFalse);
    final claro = TicketEscPos.venta(n.copyWith(ticketOscuro: false), ejemplo());
    expect(_contiene(claro, const [0x1B, 0x45, 0x00]), isTrue);
  });

  test('la intensidad manda los comandos de calor justo después de iniciar', () async {
    final n = (await db.negocio()).copyWith(intensidadTicket: IntensidadTicket.maxima);
    final b = TicketEscPos.venta(n, ejemplo());
    expect(b.sublist(0, 2), [0x1B, 0x40]);
    expect(b.sublist(2, 2 + 7), [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0x06]);
  });

  test('el logo se reduce, se vuelve blanco y negro y va arriba del ticket', () async {
    // Imagen de 720 x 100: mitad izquierda negra, mitad derecha blanca.
    const ancho = 720, alto = 100;
    final grises = Uint8List(ancho * alto);
    for (var y = 0; y < alto; y++) {
      for (var x = 0; x < ancho; x++) {
        grises[y * ancho + x] = x < ancho ~/ 2 ? 0 : 255;
      }
    }
    final logo = LogoTermico.convertir(grises, ancho, alto);
    expect(logo.ancho, 360);
    expect(logo.alto, 50);
    expect(logo.puntos.first, 0xFF); // izquierda negra
    expect(logo.puntos[logo.ancho ~/ 8 - 1], 0x00); // derecha blanca
    final n = (await db.negocio()).copyWith(logoTicket: Value(logo.puntos), logoAncho: Value(logo.ancho));
    final b = TicketEscPos.venta(n, ejemplo());
    expect(_contiene(b, const [0x1D, 0x76, 0x30, 0x00, 45, 0, 50, 0]), isTrue);
  });

  test('un logo alto se manda en tiras de 128 filas', () {
    final puntos = Uint8List(10 * 300); // 80 puntos de ancho, 300 filas
    final c = LogoTermico.comando(puntos, 80);
    expect(c.length, 3 * 8 + puntos.length);
    expect(c.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 10, 0, 128, 0]);
    expect(c.sublist(8 + 1280, 8 + 1280 + 8), [0x1D, 0x76, 0x30, 0x00, 10, 0, 128, 0]);
    expect(c.sublist(2 * (8 + 1280), 2 * (8 + 1280) + 8), [0x1D, 0x76, 0x30, 0x00, 10, 0, 44, 0]);
  });

  test('el cuadre y el recibo de abono salen con sus títulos', () async {
    final n = await db.negocio();
    final dueno = await sesionDueno(db);
    final caja = CajaService(db);
    await caja.abrir(dueno, 100000);
    final r = await caja.cerrar(dueno, {500: 1});
    final cuadre = TicketEscPos.cierreCaja(n, r);
    expect(_contiene(cuadre, codificarCp850('CUADRE DE CAJA')), isTrue);
    expect(_contiene(cuadre, codificarCp850('FALTANTE')), isTrue);
    final abono = TicketEscPos.abono(n, cliente: 'Rosa', monto: 5000, balance: 10000, fecha: horaPrueba, cajero: 'Dueño');
    expect(_contiene(abono, codificarCp850('RECIBO DE ABONO')), isTrue);
  });
}
