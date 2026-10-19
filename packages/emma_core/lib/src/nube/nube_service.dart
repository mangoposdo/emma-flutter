import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../compras/factura_leida.dart';
import '../db/database.dart';
import '../errores.dart';
import '../sesion.dart';
import 'eventos.dart';

/// Envía eventos a la nube. Debe lanzar si no se pudo (sin internet, servidor caído...).
abstract interface class EnviadorNube {
  Future<void> enviar(String instalacionId, List<EventoSalida> eventos);
}

class ResultadoSincronizacion {
  const ResultadoSincronizacion(this.enviados, this.pendientes, this.error);

  final int enviados;
  final int pendientes;
  final String? error;
}

/// Vacía la cola de envío cuando hay internet. Cada evento tiene un id único,
/// así que el servidor ignora los repetidos si un lote se envía dos veces.
class SincronizacionService {
  SincronizacionService(this.db, this.enviador, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  static const tamanoLote = 100;

  final EmmaDatabase db;
  final EnviadorNube enviador;
  final Reloj _reloj;

  Future<int> pendientes() async {
    final c = db.eventosSalida.id.count();
    final q = db.selectOnly(db.eventosSalida)
      ..addColumns([c])
      ..where(db.eventosSalida.enviadoEn.isNull());
    return (await q.getSingle()).read(c) ?? 0;
  }

  Future<ResultadoSincronizacion> sincronizar() async {
    var enviados = 0;
    final instalacion = (await db.negocio()).instalacionId;
    while (true) {
      final lote = await (db.select(db.eventosSalida)
            ..where((e) => e.enviadoEn.isNull())
            ..orderBy([(e) => OrderingTerm.asc(e.fecha)])
            ..limit(tamanoLote))
          .get();
      if (lote.isEmpty) break;
      try {
        await enviador.enviar(instalacion, lote);
      } catch (e) {
        final mensaje = e is EmmaError ? e.mensaje : e.toString();
        await db.batch((b) {
          for (final ev in lote) {
            b.update(
              db.eventosSalida,
              EventosSalidaCompanion(intentos: Value(ev.intentos + 1), ultimoError: Value(mensaje)),
              where: (t) => t.id.equals(ev.id),
            );
          }
        });
        return ResultadoSincronizacion(enviados, await pendientes(), mensaje);
      }
      final ahora = _reloj();
      await (db.update(db.eventosSalida)..where((e) => e.id.isIn(lote.map((x) => x.id))))
          .write(EventosSalidaCompanion(enviadoEn: Value(ahora)));
      enviados += lote.length;
    }
    return ResultadoSincronizacion(enviados, await pendientes(), null);
  }
}

/// Conecta esta caja con la nube de Emma usando el código de activación del
/// colmado (sale en la web, en Mi colmado) y le pasa las ventas al portal del
/// dueño. Mismo contrato que la 0.7.
class NubeService implements EnviadorNube {
  NubeService(this.db, {required this.version, http.Client? cliente, String? direccion, Reloj? reloj})
      : _http = cliente ?? http.Client(),
        direccion = (direccion ?? direccionPorDefecto).replaceAll(RegExp(r'/+$'), ''),
        _reloj = reloj ?? db.reloj;

  /// Se puede cambiar con la variable de entorno EMMA_NUBE (para pruebas).
  static String get direccionPorDefecto {
    final d = Platform.environment['EMMA_NUBE'];
    return d != null && d.isNotEmpty ? d : 'https://emma-web-5016.azurewebsites.net';
  }

  final EmmaDatabase db;
  final String version;
  final String direccion;
  final http.Client _http;
  final Reloj _reloj;

  static const _espera = Duration(seconds: 30);

  Future<bool> conectada() async => (await db.negocio()).nubeCajaId != null;

  /// Conecta la caja con el código del colmado. Devuelve el nombre del colmado en la nube.
  Future<String> conectar(Sesion sesion, String codigo, {String? nombrePc}) async {
    requiereDueno(sesion.esDueno, 'conectar la caja a la nube');
    final c = codigo.trim();
    if (c.isEmpty) throw const DatoInvalido('Escriba el código de activación del colmado.');
    final n = await db.negocio();

    final http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse('$direccion/api/caja/activar'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'codigo': c,
              'instalacionId': n.instalacionId,
              'nombrePc': nombrePc ?? Platform.localHostname,
              'version': version,
            }),
          )
          .timeout(_espera);
    } on Exception {
      throw const EmmaError('No se pudo llegar a la nube. Revise que la computadora tenga internet y pruebe otra vez.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw EmmaError(_mensajeDeError(r));

    final datos = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();
    String campo(String nombre) {
      final v = datos[nombre] ?? datos[nombre[0].toUpperCase() + nombre.substring(1)];
      return v?.toString() ?? '';
    }

    final negocio = campo('negocio');
    final caja = campo('caja');
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id))).write(NegociosCompanion(
      nubeCajaId: Value(campo('cajaId')),
      nubeLlave: Value(campo('llave')),
      nubeNegocio: Value(negocio),
      nubeCaja: Value(caja),
    ));
    await db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Conectada a la nube', detalle: '$negocio ($caja)', fecha: _reloj());
    return negocio;
  }

  /// Deja de enviar. Los datos nuevos se siguen guardando en la cola.
  Future<void> desconectar(Sesion sesion) async {
    requiereDueno(sesion.esDueno, 'desconectar la caja de la nube');
    final n = await db.negocio();
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id)))
        .write(const NegociosCompanion(nubeCajaId: Value(null), nubeLlave: Value(null)));
    await db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Desconectada de la nube', detalle: n.nubeNegocio, fecha: _reloj());
  }

  @override
  Future<void> enviar(String instalacionId, List<EventoSalida> eventos) async {
    final n = await db.negocio();
    final caja = n.nubeCajaId;
    final llave = n.nubeLlave;
    if (caja == null || llave == null) throw const EmmaError('Esta caja no está conectada a la nube.');

    final r = await _http
        .post(
          Uri.parse('$direccion/api/caja/eventos'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Emma $caja.$llave',
            'X-Emma-Version': version,
          },
          body: jsonEncode({
            'eventos': [
              for (final e in eventos) {'id': e.id, 'fecha': fechaLocalIso(e.fecha), 'tipo': e.tipo, 'datos': e.datos},
            ],
          }),
        )
        .timeout(_espera);
    if (r.statusCode == 401) {
      throw const EmmaError('La nube no reconoce esta caja. Conéctela otra vez con el código del colmado.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw EmmaError(_mensajeDeError(r));
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id)))
        .write(NegociosCompanion(nubeUltimoEnvio: Value(_reloj())));
  }

  /// El tipo que se manda según la extensión del archivo.
  static String tipoFactura(String archivo) => switch (archivo.toLowerCase().split('.').last) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  /// Manda la foto (o PDF) de una factura de suplidor a la nube y devuelve lo
  /// que dice. No toca el inventario: la compra se llena en pantalla para que
  /// el dueño la revise y la guarde. Leer puede tardar más de un minuto.
  Future<FacturaLeida> leerFactura(Sesion sesion, Uint8List archivo, String tipo) async {
    requiereDueno(sesion.esDueno, 'leer facturas');
    final n = await db.negocio();
    final caja = n.nubeCajaId;
    final llave = n.nubeLlave;
    if (caja == null || llave == null) {
      throw const DatoInvalido(
          'Para leer facturas, la caja tiene que estar conectada a la nube (Configuración > Conectar a la nube).');
    }
    final http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse('$direccion/api/caja/leer-factura'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Emma $caja.$llave',
              'X-Emma-Version': version,
            },
            body: jsonEncode({'archivo': base64Encode(archivo), 'tipo': tipo}),
          )
          .timeout(const Duration(seconds: 170));
    } on Exception {
      throw const EmmaError('No se pudo llegar a la nube. Revise que la computadora tenga internet y pruebe otra vez.');
    }
    if (r.statusCode == 401) {
      throw const EmmaError('La nube no reconoce esta caja. Conéctela otra vez con el código del colmado.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw EmmaError(_mensajeDeError(r));
    return FacturaLeida.fromJson((jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>());
  }

  static String _mensajeDeError(http.Response r) {
    try {
      final p = jsonDecode(utf8.decode(r.bodyBytes));
      if (p is Map) {
        final detalle = p['detail'] ?? p['Detail'];
        if (detalle is String && detalle.trim().isNotEmpty) return detalle;
      }
    } on FormatException {
      // Respuesta sin JSON.
    }
    return r.statusCode == 429
        ? 'Demasiados intentos. Espere un minuto y pruebe otra vez.'
        : 'La nube respondió con un error (${r.statusCode}). Pruebe más tarde.';
  }
}
