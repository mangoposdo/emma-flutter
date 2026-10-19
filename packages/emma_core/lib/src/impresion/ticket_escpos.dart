import 'dart:typed_data';

import '../caja/caja_service.dart';
import '../db/database.dart';
import '../dinero.dart';
import '../formato.dart';
import '../ventas/delivery_service.dart';
import '../ventas/venta_service.dart';
import 'cp850.dart';
import 'logo_termico.dart';

/// Una línea del ticket. Montos en centavos, cantidad en milésimas.
class LineaTicket {
  const LineaTicket(this.descripcion, this.cantidad, this.precio, this.total);

  final String descripcion;
  final int cantidad;
  final int precio;
  final int total;
}

/// Lo que sale en el ticket de una venta.
class TicketVenta {
  const TicketVenta({
    required this.id,
    required this.fecha,
    required this.cajero,
    this.cliente,
    this.esDelivery = false,
    this.repartidor,
    this.anulada = false,
    required this.lineas,
    required this.subtotal,
    this.descuento = 0,
    required this.total,
    required this.formaPago,
    this.recibido = 0,
    this.devuelta = 0,
  });

  factory TicketVenta.de(VentaDetalle d) => TicketVenta(
        id: d.venta.id,
        fecha: d.venta.fecha,
        cajero: d.cajero,
        cliente: d.nombreParaMostrar,
        esDelivery: d.venta.esDelivery,
        repartidor: d.venta.repartidor,
        anulada: d.venta.anulada,
        lineas: [for (final l in d.lineas) LineaTicket(l.descripcion, l.cantidad, l.precioUnitario, l.total)],
        subtotal: d.venta.subtotal,
        descuento: d.venta.descuento,
        total: d.venta.total,
        formaPago: d.venta.formaPago,
        recibido: d.venta.montoRecibido,
        devuelta: d.venta.devuelta,
      );

  final int id;
  final DateTime fecha;
  final String cajero;
  final String? cliente;
  final bool esDelivery;
  final String? repartidor;
  final bool anulada;
  final List<LineaTicket> lineas;
  final int subtotal;
  final int descuento;
  final int total;
  final FormaPago formaPago;
  final int recibido;
  final int devuelta;
}

/// Arma los bytes ESC/POS de un ticket. Funciona con la mayoría de las
/// impresoras térmicas (2Connect, Epson, Xprinter, Bixolon...). El ancho es en
/// letras: 48 para papel de 80 mm, 32 para 58 mm. Igual que la 0.7.
class TicketEscPos {
  TicketEscPos({this.ancho = 48, this.oscuro = false, IntensidadTicket intensidad = IntensidadTicket.normal}) {
    _b.add(_iniciar);
    _b.add(intensidadBytes(intensidad));
    _b.add(_paginaCodigos850);
    if (oscuro) {
      _b
        ..add(_negritaSi)
        ..add(_dobleGolpeSi);
    }
  }

  static const _iniciar = [0x1B, 0x40];
  static const _paginaCodigos850 = [0x1B, 0x74, 0x02];
  static const _centrado = [0x1B, 0x61, 0x01];
  static const _izquierda = [0x1B, 0x61, 0x00];
  static const _negritaSi = [0x1B, 0x45, 0x01];
  static const _negritaNo = [0x1B, 0x45, 0x00];
  static const _dobleAlto = [0x1D, 0x21, 0x11];
  static const _soloDobleAlto = [0x1D, 0x21, 0x01];
  static const _tripleTamano = [0x1D, 0x21, 0x22];
  static const _dobleGolpeSi = [0x1B, 0x47, 0x01];
  static const _normal = [0x1D, 0x21, 0x00];
  static const _cortar = [0x1D, 0x56, 0x42, 0x03];

  /// Pulso al pin 2 del conector de la gaveta.
  static final abrirGaveta = Uint8List.fromList(const [0x1B, 0x70, 0x00, 0x19, 0xFA]);

  final int ancho;
  final bool oscuro;
  final _b = BytesBuilder(copy: false);

  /// Pide a la impresora que caliente más la cabeza. Cada marca entiende un
  /// comando distinto: se mandan los tres comunes y cada una usa el suyo.
  static List<int> intensidadBytes(IntensidadTicket nivel) => switch (nivel) {
        IntensidadTicket.normal => const [],
        IntensidadTicket.masOscura => const [
            0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0x03, // Epson: densidad +3
            0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 0x05, // Epson: velocidad media
            0x1B, 0x37, 0x0B, 0xA0, 0x04, // ESC 7: 96 puntos, 1.6 ms, pausa 40 µs
            0x12, 0x23, 0x4F, // DC2 #: densidad alta
          ],
        IntensidadTicket.maxima => const [
            0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0x06, // Epson: densidad +6
            0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 0x01, // Epson: velocidad más lenta
            0x1B, 0x37, 0x0B, 0xF0, 0x08, // ESC 7: 96 puntos, 2.4 ms, pausa 80 µs
            0x12, 0x23, 0x5F, // DC2 #: densidad máxima
          ],
      };

  Uint8List bytes() => _b.toBytes();

  void _finNegrita() {
    if (!oscuro) _b.add(_negritaNo);
  }

  void texto(String s) => _b.add(codificarCp850(s));
  void linea([String s = '']) => texto('$s\n');
  void separador() => linea('-' * ancho);

  void centro(String s, {bool negrita = false, bool grande = false}) {
    _b.add(_centrado);
    if (negrita) _b.add(_negritaSi);
    if (grande) _b.add(_dobleAlto);
    linea(s);
    if (grande) _b.add(_normal);
    if (negrita) _finNegrita();
    _b.add(_izquierda);
  }

  /// Texto largo partido en líneas del ancho del papel, sin cortar palabras.
  void parrafo(String t, {bool negrita = false, bool alto = false}) {
    if (negrita) _b.add(_negritaSi);
    if (alto) _b.add(_soloDobleAlto);
    var actual = '';
    for (final palabra in t.split(' ').where((x) => x.isNotEmpty)) {
      final p = palabra.length > ancho ? palabra.substring(0, ancho) : palabra;
      if (actual.isNotEmpty && actual.length + 1 + p.length > ancho) {
        linea(actual);
        actual = '';
      }
      actual = actual.isEmpty ? p : '$actual $p';
    }
    if (actual.isNotEmpty) linea(actual);
    if (alto) _b.add(_normal);
    if (negrita) _finNegrita();
  }

  /// Texto a la izquierda y valor a la derecha en la misma línea.
  void columnas(String izquierda, String derecha, {bool negrita = false, bool alto = false}) {
    final espacio = ancho - derecha.length - 1;
    var izq = izquierda;
    if (izq.length > espacio) izq = izq.substring(0, espacio < 0 ? 0 : espacio);
    if (negrita) _b.add(_negritaSi);
    if (alto) _b.add(_soloDobleAlto);
    linea(izq.padRight(ancho - derecha.length) + derecha);
    if (alto) _b.add(_normal);
    if (negrita) _finNegrita();
  }

  /// El total bien grande y centrado: triple tamaño si cabe, si no doble.
  void totalGrande(String etiqueta, String monto) {
    centro(etiqueta, negrita: true);
    _b
      ..add(_centrado)
      ..add(_negritaSi)
      ..add(monto.length <= ancho ~/ 3 ? _tripleTamano : _dobleAlto);
    linea(monto);
    _b.add(_normal);
    _finNegrita();
    _b.add(_izquierda);
  }

  void logo(Uint8List? puntos, int? anchoLogo) {
    if (puntos == null || puntos.isEmpty || anchoLogo == null || anchoLogo < 8) return;
    _b
      ..add(_centrado)
      ..add(LogoTermico.comando(puntos, anchoLogo))
      ..add(_izquierda);
    linea();
  }

  void fin({required bool gaveta}) {
    texto('\n\n\n');
    _b.add(_cortar);
    if (gaveta) _b.add(abrirGaveta);
  }

  static String _monto(int centavos) => formatoMonto(centavos);

  static String _cant(int milesimas) => formatoCantidad(milesimas);

  void _encabezado(NegocioRow n, {bool conLogo = true}) {
    if (conLogo) logo(n.logoTicket, n.logoAncho);
    centro(n.nombre, negrita: true, grande: true);
    if ((n.direccion ?? '').trim().isNotEmpty) centro(n.direccion!);
    if ((n.telefono ?? '').trim().isNotEmpty) centro('Tel. ${n.telefono}');
    if ((n.rnc ?? '').trim().isNotEmpty) centro('RNC ${n.rnc}');
    separador();
  }

  static TicketEscPos _para(NegocioRow n) =>
      TicketEscPos(ancho: n.anchoTicket, oscuro: n.ticketOscuro, intensidad: n.intensidadTicket);

  static Uint8List venta(NegocioRow n, TicketVenta v, {int? deudaCliente}) {
    final t = _para(n).._encabezado(n);
    t.linea('Ticket #${v.id}');
    t.linea('Fecha: ${formatoFechaHora(v.fecha)}');
    t.linea('Cajero: ${v.cajero}');
    if (v.cliente != null) t.linea('Cliente: ${v.cliente}');
    if (v.esDelivery) t.linea('Delivery${v.repartidor != null ? ' con ${v.repartidor}' : ''}');
    if (v.anulada) t.centro('*** VENTA ANULADA ***', negrita: true);
    t.separador();
    for (final l in v.lineas) {
      t.linea(l.descripcion.length > n.anchoTicket ? l.descripcion.substring(0, n.anchoTicket) : l.descripcion);
      t.columnas('  ${_cant(l.cantidad)} x ${_monto(l.precio)}', _monto(l.total));
    }
    t.separador();
    if (v.descuento > 0) {
      t.columnas('Subtotal', _monto(v.subtotal));
      t.columnas('Descuento', '-${_monto(v.descuento)}');
    }
    t.totalGrande('TOTAL A PAGAR', 'RD\$${_monto(v.total)}');
    t.separador();
    t.columnas('Forma de pago', v.formaPago.etiqueta);
    if (v.formaPago == FormaPago.efectivo) {
      t.columnas('Recibido', _monto(v.recibido));
      t.columnas('Devuelta', _monto(v.devuelta), negrita: true, alto: true);
    }
    if (deudaCliente != null) t.columnas('Balance pendiente', _monto(deudaCliente), negrita: true);
    t.separador();
    t.centro(n.mensajeTicket);
    t.centro('Documento no fiscal');
    t.centro('Hecho con Emma');
    t.fin(gaveta: n.abrirGaveta && v.formaPago == FormaPago.efectivo);
    return t.bytes();
  }

  static Uint8List abono(NegocioRow n, {
    required String cliente,
    required int monto,
    required int balance,
    required DateTime fecha,
    required String cajero,
  }) {
    final t = _para(n).._encabezado(n);
    t.centro('RECIBO DE ABONO', negrita: true);
    t.linea('Fecha: ${formatoFechaHora(fecha)}');
    t.linea('Cliente: $cliente');
    t.linea('Recibido por: $cajero');
    t.separador();
    t.columnas('Abono RD\$', _monto(monto), negrita: true, alto: true);
    t.columnas('Balance pendiente RD\$', _monto(balance), negrita: true);
    t.separador();
    t.centro('Gracias');
    t.fin(gaveta: n.abrirGaveta);
    return t.bytes();
  }

  static Uint8List cierreCaja(NegocioRow n, ResumenTurno r) {
    final t = _para(n).._encabezado(n, conLogo: false);
    t.centro('CUADRE DE CAJA', negrita: true);
    t.linea('Cajero: ${r.cajero}');
    t.linea('Apertura: ${formatoFechaHora(r.turno.apertura)}');
    if (r.turno.cierre != null) t.linea('Cierre:   ${formatoFechaHora(r.turno.cierre!)}');
    t.separador();
    t.columnas('Ventas (${r.cantidadVentas})', _monto(r.totalVentas), negrita: true);
    t.columnas('  Efectivo', _monto(r.ventasEfectivo));
    t.columnas('  Tarjeta', _monto(r.ventasTarjeta));
    t.columnas('  Transferencia', _monto(r.ventasTransferencia));
    t.columnas('  Fiado', _monto(r.ventasFiado));
    if (r.ventasAnuladas > 0) t.columnas('Ventas anuladas', '${r.ventasAnuladas}');
    if (r.cantidadDelivery > 0) {
      t.columnas('Delivery (${r.cantidadDelivery})', _monto(r.ventasDelivery));
      for (final p in r.porRepartidor) {
        t.columnas('  ${p.repartidor} (${p.cantidad})', _monto(p.total));
      }
    }
    t.separador();
    t.columnas('Fondo inicial', _monto(r.turno.fondoInicial));
    t.columnas('+ Ventas en efectivo', _monto(r.ventasEfectivo));
    t.columnas('+ Abonos en efectivo', _monto(r.abonosEfectivo));
    t.columnas('+ Entradas', _monto(r.entradas));
    t.columnas('- Salidas', _monto(r.salidas));
    t.columnas('= Efectivo esperado', _monto(r.efectivoEsperado), negrita: true);
    if (r.turno.efectivoContado != null) {
      t.columnas('Efectivo contado', _monto(r.turno.efectivoContado!), negrita: true);
      final dif = r.turno.diferencia ?? 0;
      t.columnas(dif < 0 ? 'FALTANTE' : dif > 0 ? 'SOBRANTE' : 'Diferencia', _monto(dif.abs()), negrita: true);
    }
    if (r.abonosOtros > 0) t.columnas('Abonos tarjeta/transf.', _monto(r.abonosOtros));
    t.separador();
    t.linea('\n\nFirma: ______________________');
    t.fin(gaveta: false);
    return t.bytes();
  }

  /// Comanda del delivery: lo que hay que llevar, a dónde y cuánto cambio
  /// mandar. El ticket de venta sale cuando el repartidor vuelve y se cobra.
  static Uint8List comanda(NegocioRow n, TicketAbierto p, List<LineaComanda> lineas, int total) {
    final t = _para(n);
    t.centro(n.nombre, negrita: true);
    t.centro('DELIVERY', negrita: true, grande: true);
    t.linea('Salida: ${formatoFechaHora(p.salioEn ?? DateTime.now())}');
    if (p.repartidor != null) t.linea('Repartidor: ${p.repartidor}');
    t.separador();
    if (p.nombreCliente != null) t.columnas('Cliente', p.nombreCliente!, negrita: true);
    if (p.telefono != null) t.columnas('Teléfono', p.telefono!, negrita: true, alto: true);
    t.linea('Dirección:');
    t.parrafo(p.direccion ?? '', negrita: true, alto: true);
    t.separador();
    for (final l in lineas) {
      final desc = '${_cant(l.cantidad)} x ${l.descripcion}';
      final max = n.anchoTicket - 12;
      t.columnas(desc.length > max ? desc.substring(0, max) : desc, _monto(l.total));
    }
    if (p.cargoEnvio > 0) t.columnas('Envío', _monto(p.cargoEnvio));
    t.separador();
    t.totalGrande('COBRAR', 'RD\$${_monto(total)}');
    if (p.pagaCon != null && p.pagaCon! > total) {
      t.columnas('Paga con', _monto(p.pagaCon!));
      t.columnas('LLEVAR CAMBIO', _monto(p.pagaCon! - total), negrita: true, alto: true);
    }
    t.separador();
    t.linea('\nRecibido: ______________________');
    t.fin(gaveta: false);
    return t.bytes();
  }
}
