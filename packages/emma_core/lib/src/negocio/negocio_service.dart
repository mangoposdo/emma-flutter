import 'package:drift/drift.dart';

import '../db/database.dart';
import '../errores.dart';
import '../sesion.dart';

/// Lo que se cambia en Configuración. Montos en centavos.
class DatosNegocio {
  const DatosNegocio({
    required this.nombre,
    this.rnc,
    this.direccion,
    this.telefono,
    this.mensajeTicket = 'Gracias por su compra',
    this.cargoDelivery = 0,
    this.impresora,
    this.anchoTicket = 48,
    this.abrirGaveta = true,
    this.ticketOscuro = true,
    this.intensidadTicket = IntensidadTicket.normal,
    this.carpetaRespaldoExterna,
  });

  final String nombre;
  final String? rnc;
  final String? direccion;
  final String? telefono;
  final String mensajeTicket;
  final int cargoDelivery;

  /// null = no imprimir.
  final String? impresora;

  /// Letras: 48 (80 mm) o 32 (58 mm).
  final int anchoTicket;
  final bool abrirGaveta;
  final bool ticketOscuro;
  final IntensidadTicket intensidadTicket;
  final String? carpetaRespaldoExterna;

  factory DatosNegocio.de(NegocioRow n) => DatosNegocio(
        nombre: n.nombre,
        rnc: n.rnc,
        direccion: n.direccion,
        telefono: n.telefono,
        mensajeTicket: n.mensajeTicket,
        cargoDelivery: n.cargoDelivery,
        impresora: n.impresora,
        anchoTicket: n.anchoTicket,
        abrirGaveta: n.abrirGaveta,
        ticketOscuro: n.ticketOscuro,
        intensidadTicket: n.intensidadTicket,
        carpetaRespaldoExterna: n.carpetaRespaldoExterna,
      );
}

/// Los datos del negocio que salen en el ticket y la configuración de la caja.
class NegocioService {
  NegocioService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  Future<NegocioRow> negocio() => db.negocio();

  /// Solo el dueño. Los datos de la nube y del mantenimiento no se tocan aquí.
  Future<NegocioRow> guardar(Sesion sesion, DatosNegocio d) async {
    requiereDueno(sesion.esDueno, 'cambiar la configuración');
    final nombre = d.nombre.trim();
    if (nombre.isEmpty) throw const DatoInvalido('Escriba el nombre del negocio.');
    if (d.cargoDelivery < 0) throw const DatoInvalido('El envío no puede ser negativo.');
    final n = await db.negocio();
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id))).write(NegociosCompanion(
      nombre: Value(nombre),
      rnc: Value(_limpio(d.rnc)),
      direccion: Value(_limpio(d.direccion)),
      telefono: Value(_limpio(d.telefono)),
      mensajeTicket: Value(d.mensajeTicket.trim()),
      cargoDelivery: Value(d.cargoDelivery),
      impresora: Value(_limpio(d.impresora)),
      anchoTicket: Value(d.anchoTicket <= 32 ? 32 : 48),
      abrirGaveta: Value(d.abrirGaveta),
      ticketOscuro: Value(d.ticketOscuro),
      intensidadTicket: Value(d.intensidadTicket),
      carpetaRespaldoExterna: Value(_limpio(d.carpetaRespaldoExterna)),
    ));
    await db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Configuración guardada', fecha: _reloj());
    return db.negocio();
  }

  /// Logo ya convertido para la impresora (ver LogoTermico). null lo quita.
  Future<void> guardarLogo(Sesion sesion, Uint8List? puntos, int ancho) async {
    requiereDueno(sesion.esDueno, 'cambiar la configuración');
    final n = await db.negocio();
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id))).write(NegociosCompanion(
      logoTicket: Value(puntos),
      logoAncho: Value(puntos == null ? null : ancho),
    ));
  }

  /// Bitácora de la gaveta abierta sin venta.
  Future<void> anotarGaveta(Sesion sesion) =>
      db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Gaveta abierta sin venta', fecha: _reloj());

  static String? _limpio(String? s) {
    final x = s?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
