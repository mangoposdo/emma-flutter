import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/cuidados.dart';
import '../../app/imprenta.dart';
import '../../app/providers.dart';
import '../../app/version.dart';

/// La primera opción de la impresora.
const noImprimir = '(no imprimir)';

String textoPapel(int ancho) => ancho <= 32 ? '58 mm (32 letras)' : '80 mm (48 letras)';

String textoIntensidad(IntensidadTicket i) => switch (i) {
      IntensidadTicket.normal => 'Normal',
      IntensidadTicket.masOscura => 'Más oscura',
      IntensidadTicket.maxima => 'Máxima',
    };

/// "Juan  ·  809-555-1234", como en la lista de la 0.7.
String textoRepartidor(Repartidor r) => r.telefono != null ? '${r.nombre}  ·  ${r.telefono}' : r.nombre;

enum Tono { info, aviso, error }

/// Lo que se le dice al usuario al terminar una acción.
class Mensaje {
  const Mensaje(this.texto, [this.tono = Tono.info]);

  final String texto;
  final Tono tono;
}

/// Lo que está escrito en la pantalla, guardado o no.
class Borrador {
  const Borrador({
    this.nombre = '',
    this.rnc = '',
    this.direccion = '',
    this.telefono = '',
    this.mensaje = '',
    this.envio = '',
    this.impresora = '',
    this.anchoTicket = 48,
    this.abrirGaveta = true,
    this.ticketOscuro = true,
    this.intensidad = IntensidadTicket.normal,
    this.carpetaExterna = '',
  });

  factory Borrador.de(NegocioRow n) => Borrador(
        nombre: n.nombre,
        rnc: n.rnc ?? '',
        direccion: n.direccion ?? '',
        telefono: n.telefono ?? '',
        mensaje: n.mensajeTicket,
        envio: _textoEnvio(n.cargoDelivery),
        impresora: n.impresora ?? '',
        anchoTicket: n.anchoTicket <= 32 ? 32 : 48,
        abrirGaveta: n.abrirGaveta,
        ticketOscuro: n.ticketOscuro,
        intensidad: n.intensidadTicket,
        carpetaExterna: n.carpetaRespaldoExterna ?? '',
      );

  final String nombre;
  final String rnc;
  final String direccion;
  final String telefono;
  final String mensaje;

  /// Envío de delivery como está escrito ("50", "75.5").
  final String envio;

  /// Vacío = no imprimir.
  final String impresora;
  final int anchoTicket;
  final bool abrirGaveta;
  final bool ticketOscuro;
  final IntensidadTicket intensidad;
  final String carpetaExterna;

  /// "0.##" de la 0.7: 50 = "50", 75.50 = "75.5".
  static String _textoEnvio(int c) {
    if (c % 100 == 0) return '${c ~/ 100}';
    final d = (c % 100).toString().padLeft(2, '0');
    return '${c ~/ 100}.${d.endsWith('0') ? d[0] : d}';
  }

  static String? _nulo(String s) => s.trim().isEmpty ? null : s.trim();

  /// Para el servicio. El envío mal escrito (o negativo) queda en 0, como en la 0.7.
  DatosNegocio get datos => DatosNegocio(
        nombre: nombre.trim(),
        rnc: _nulo(rnc),
        direccion: _nulo(direccion),
        telefono: _nulo(telefono),
        mensajeTicket: mensaje.trim(),
        cargoDelivery: parsearMonto(envio) ?? 0,
        impresora: _nulo(impresora),
        anchoTicket: anchoTicket,
        abrirGaveta: abrirGaveta,
        ticketOscuro: ticketOscuro,
        intensidadTicket: intensidad,
        carpetaRespaldoExterna: _nulo(carpetaExterna),
      );

  Borrador copyWith({
    String? nombre,
    String? rnc,
    String? direccion,
    String? telefono,
    String? mensaje,
    String? envio,
    String? impresora,
    int? anchoTicket,
    bool? abrirGaveta,
    bool? ticketOscuro,
    IntensidadTicket? intensidad,
    String? carpetaExterna,
  }) =>
      Borrador(
        nombre: nombre ?? this.nombre,
        rnc: rnc ?? this.rnc,
        direccion: direccion ?? this.direccion,
        telefono: telefono ?? this.telefono,
        mensaje: mensaje ?? this.mensaje,
        envio: envio ?? this.envio,
        impresora: impresora ?? this.impresora,
        anchoTicket: anchoTicket ?? this.anchoTicket,
        abrirGaveta: abrirGaveta ?? this.abrirGaveta,
        ticketOscuro: ticketOscuro ?? this.ticketOscuro,
        intensidad: intensidad ?? this.intensidad,
        carpetaExterna: carpetaExterna ?? this.carpetaExterna,
      );
}

/// El ticket de "Imprimir prueba": las mismas líneas que la 0.7.
TicketVenta ticketDePrueba(DateTime fecha, String cajero) => TicketVenta(
      id: 0,
      fecha: fecha,
      cajero: cajero,
      cliente: 'Prueba de impresión',
      formaPago: FormaPago.efectivo,
      lineas: const [
        LineaTicket('Acentos: áéíóú ñ Ñ ¿?', 1000, 100000, 100000),
        LineaTicket('Arroz selecto (libra)', 5000, 4690, 23450),
      ],
      subtotal: 123450,
      total: 123450,
      recibido: 150000,
      devuelta: 26550,
    );

class ConfiguracionState {
  const ConfiguracionState({
    required this.negocio,
    required this.borrador,
    this.impresoras = const [],
    this.repartidores = const [],
    this.repartidorEscogido,
    this.pendientes = 0,
    this.conectando = false,
    this.enviando = false,
    required this.carpetaRespaldos,
    required this.rutaBase,
  });

  /// Lo guardado en la base (logo, nube...).
  final NegocioRow negocio;
  final Borrador borrador;

  /// Las instaladas, y la guardada si ya no está instalada.
  final List<String> impresoras;
  final List<Repartidor> repartidores;
  final int? repartidorEscogido;

  /// Datos esperando para subir a la nube.
  final int pendientes;
  final bool conectando;
  final bool enviando;
  final String carpetaRespaldos;
  final String rutaBase;

  List<String> get opcionesImpresora => [noImprimir, ...impresoras];
  String get impresoraEscogida => borrador.impresora.trim().isEmpty ? noImprimir : borrador.impresora;

  Repartidor? get repartidor {
    final i = repartidorEscogido;
    return i == null || i < 0 || i >= repartidores.length ? null : repartidores[i];
  }

  bool get hayLogo => (negocio.logoTicket?.isNotEmpty ?? false) && (negocio.logoAncho ?? 0) >= 8;

  bool get conectada => negocio.nubeCajaId != null;

  String get textoNube => '✔ Conectada a ${negocio.nubeNegocio ?? ''} como ${negocio.nubeCaja ?? ''}.';

  String get detalleNube {
    final u = negocio.nubeUltimoEnvio;
    final envio = u != null ? 'Último envío: ${formatoFechaHora(u)}. ' : 'Todavía no ha enviado. ';
    final falta = pendientes == 0 ? 'No hay nada pendiente.' : '$pendientes datos esperando para subir.';
    return '$envio$falta Las ventas suben solas cada minuto cuando hay internet.';
  }

  String get textoRespaldos => 'Los respaldos automáticos se guardan en $carpetaRespaldos. Se hace uno al abrir el '
      'programa, cada 2 horas y al cerrar la caja; se guardan los últimos ${RespaldoService.copiasRecientes} '
      'y uno por día del último mes.';

  String get textoVersion => 'Emma versión $versionEmma · Datos en $rutaBase';

  /// El negocio con lo que está en la pantalla, aunque no se haya guardado.
  NegocioRow get negocioDePantalla {
    final d = borrador.datos;
    return negocio.copyWith(
      nombre: d.nombre,
      rnc: Value(d.rnc),
      direccion: Value(d.direccion),
      telefono: Value(d.telefono),
      mensajeTicket: d.mensajeTicket,
      cargoDelivery: d.cargoDelivery,
      impresora: Value(d.impresora),
      anchoTicket: d.anchoTicket,
      abrirGaveta: d.abrirGaveta,
      ticketOscuro: d.ticketOscuro,
      intensidadTicket: d.intensidadTicket,
      carpetaRespaldoExterna: Value(d.carpetaRespaldoExterna),
    );
  }

  ConfiguracionState copyWith({
    NegocioRow? negocio,
    Borrador? borrador,
    List<Repartidor>? repartidores,
    int? repartidorEscogido,
    bool sinEscoger = false,
    int? pendientes,
    bool? conectando,
    bool? enviando,
  }) =>
      ConfiguracionState(
        negocio: negocio ?? this.negocio,
        borrador: borrador ?? this.borrador,
        impresoras: impresoras,
        repartidores: repartidores ?? this.repartidores,
        repartidorEscogido: sinEscoger ? null : (repartidorEscogido ?? this.repartidorEscogido),
        pendientes: pendientes ?? this.pendientes,
        conectando: conectando ?? this.conectando,
        enviando: enviando ?? this.enviando,
        carpetaRespaldos: carpetaRespaldos,
        rutaBase: rutaBase,
      );
}

final configuracionViewModelProvider =
    AsyncNotifierProvider.autoDispose<ConfiguracionViewModel, ConfiguracionState>(ConfiguracionViewModel.new);

/// Configuración de la 0.7. Solo el dueño.
class ConfiguracionViewModel extends AsyncNotifier<ConfiguracionState> {
  @override
  Future<ConfiguracionState> build() async {
    final n = await ref.read(negocioServiceProvider).negocio();
    List<String> instaladas;
    try {
      instaladas = await ref.read(impresoraProvider).instaladas();
    } on Exception {
      instaladas = const [];
    }
    final guardada = (n.impresora ?? '').trim();
    return ConfiguracionState(
      negocio: n,
      borrador: Borrador.de(n),
      impresoras: [...instaladas, if (guardada.isNotEmpty && !instaladas.contains(guardada)) guardada],
      repartidores: await ref.read(deliveryServiceProvider).listaRepartidores(),
      pendientes: await ref.read(sincronizacionServiceProvider).pendientes(),
      carpetaRespaldos: ref.read(respaldoServiceProvider).carpeta.path,
      rutaBase: p.join(ref.read(carpetaDatosProvider).path, nombreArchivoBase),
    );
  }

  ConfiguracionState get _s => state.value ?? (throw const EmmaError('Espere a que cargue la configuración.'));

  void _poner(ConfiguracionState Function(ConfiguracionState s) cambio) {
    final s = state.value;
    if (ref.mounted && s != null) state = AsyncData(cambio(s));
  }

  /// La pantalla se queda viva mientras termina lo que se empezó.
  Future<T> _sinSoltar<T>(Future<T> Function() accion) async {
    final enlace = ref.keepAlive();
    try {
      return await accion();
    } finally {
      enlace.close();
    }
  }

  void cambiar(Borrador Function(Borrador b) cambio) => _poner((s) => s.copyWith(borrador: cambio(s.borrador)));

  void escogerImpresora(String opcion) => cambiar((b) => b.copyWith(impresora: opcion == noImprimir ? '' : opcion));

  Future<void> _guardar() async {
    final n = await ref.read(negocioServiceProvider).guardar(ref.sesion, _s.borrador.datos);
    ref.invalidate(negocioProvider);
    _poner((s) => s.copyWith(negocio: n));
  }

  Future<Mensaje> guardar() async {
    await _guardar();
    return const Mensaje('Configuración guardada.');
  }

  Future<Mensaje> imprimirPrueba() async {
    final s = _s;
    final impresora = s.borrador.impresora.trim();
    if (impresora.isEmpty) return const Mensaje('Escoja una impresora.');
    final cajero = ref.read(sesionProvider)?.nombre ?? 'Cajero';
    final datos = TicketEscPos.venta(s.negocioDePantalla, ticketDePrueba(ref.read(baseDeDatosProvider).reloj(), cajero));
    final error = await ref.read(imprentaProvider).enviar(impresora, datos);
    return error == null
        ? const Mensaje('Se envió la prueba. Si no salió bien, revise el driver y el tamaño de papel.')
        : Mensaje(error, Tono.error);
  }

  // ---------- Logo ----------

  Future<void> _recargarNegocio() async {
    final n = await ref.read(negocioServiceProvider).negocio();
    ref.invalidate(negocioProvider);
    _poner((s) => s.copyWith(negocio: n));
  }

  /// Recibe la imagen ya en grises (0 = negro, 255 = blanco), la convierte a
  /// puntos para la impresora y la guarda.
  Future<Mensaje> ponerLogo(Uint8List grises, int ancho, int alto) async {
    final LogoConvertido logo;
    try {
      logo = LogoTermico.convertir(grises, ancho, alto);
    } on ArgumentError {
      throw const EmmaError('No se pudo abrir esa imagen. Escoja un PNG o JPG.');
    }
    await ref.read(negocioServiceProvider).guardarLogo(ref.sesion, logo.puntos, logo.ancho);
    await _recargarNegocio();
    return const Mensaje('Logo guardado. Use "Imprimir prueba" para ver cómo sale.');
  }

  Future<void> quitarLogo() async {
    await ref.read(negocioServiceProvider).guardarLogo(ref.sesion, null, 0);
    await _recargarNegocio();
  }

  // ---------- Repartidores ----------

  void escogerRepartidor(int i) => _poner((s) => s.copyWith(repartidorEscogido: i));

  Future<void> _recargarRepartidores() async {
    final lista = await ref.read(deliveryServiceProvider).listaRepartidores();
    _poner((s) => s.copyWith(repartidores: lista, sinEscoger: true));
  }

  /// Agrega ([id] null) o cambia un repartidor.
  Future<void> guardarRepartidor({int? id, required String nombre, String? telefono}) async {
    await ref
        .read(deliveryServiceProvider)
        .guardarRepartidor(ref.sesion, DatosRepartidor(id: id, nombre: nombre, telefono: telefono));
    await _recargarRepartidores();
  }

  /// Lo marca inactivo: sus entregas anteriores se quedan en los reportes.
  Future<void> quitarRepartidor(Repartidor r) async {
    await ref.read(deliveryServiceProvider).guardarRepartidor(
          ref.sesion,
          DatosRepartidor(id: r.id, nombre: r.nombre, telefono: r.telefono, activo: false),
        );
    await _recargarRepartidores();
  }

  // ---------- Nube ----------

  Future<void> _recargarNube() async {
    final n = await ref.read(negocioServiceProvider).negocio();
    final pendientes = await ref.read(sincronizacionServiceProvider).pendientes();
    _poner((s) => s.copyWith(negocio: n, pendientes: pendientes));
  }

  /// Conecta con el código del colmado y sube lo que estaba guardado.
  Future<Mensaje> conectar(String codigo) => _sinSoltar(() async {
        _poner((s) => s.copyWith(conectando: true));
        try {
          final colmado = await ref.read(nubeServiceProvider).conectar(ref.sesion, codigo);
          ref.invalidate(estadoNubeProvider);
          await _recargarNube();
          final r = await ref.read(cuidadosProvider).enviarANube();
          await _recargarNube();
          return Mensaje('Listo. Esta caja quedó conectada a $colmado.'
              '${r != null && r.enviados > 0 ? '\n\nSe subieron ${r.enviados} datos guardados.' : ''}'
              '\n\nYa puede ver las ventas en la web de Emma, en Mi colmado.');
        } finally {
          _poner((s) => s.copyWith(conectando: false));
        }
      });

  /// null si la caja ya no está conectada (no hay nada que decir).
  Future<Mensaje?> enviarAhora() => _sinSoltar(() async {
        _poner((s) => s.copyWith(enviando: true));
        try {
          final conectada = await ref.read(nubeServiceProvider).conectada();
          final r = await ref.read(cuidadosProvider).enviarANube();
          await _recargarNube();
          if (r == null) return conectada ? const Mensaje('Ya se está enviando. Espere unos segundos.') : null;
          if (r.error != null) {
            return Mensaje(
              'No se pudo enviar ahora: ${r.error}\n\nLos datos siguen guardados y se envían solos cuando vuelva el internet.',
              Tono.aviso,
            );
          }
          return Mensaje(r.enviados == 0 ? 'Todo estaba al día.' : 'Se enviaron ${r.enviados} datos.');
        } finally {
          _poner((s) => s.copyWith(enviando: false));
        }
      });

  Future<void> desconectar() async {
    await ref.read(nubeServiceProvider).desconectar(ref.sesion);
    ref.invalidate(estadoNubeProvider);
    await _recargarNube();
  }

  // ---------- Respaldos ----------

  /// Guarda la configuración (por la carpeta externa) y respalda.
  Future<Mensaje> respaldarAhora() => _sinSoltar(() async {
        await _guardar();
        return Mensaje(await ref.read(cuidadosProvider).respaldoCompleto());
      });

  /// Guarda una copia de los datos actuales, cierra la base y pone el
  /// respaldo en su lugar. Después hay que cerrar el programa. Devuelve dónde
  /// quedó la copia de los datos anteriores.
  Future<String> restaurar(String archivo) => _sinSoltar(() async {
        final copia = await ref.read(respaldoServiceProvider).prepararRestauracion(ref.sesion, archivo);
        await ref.read(baseDeDatosProvider).close();
        await RespaldoService.ponerRespaldo(ref.read(carpetaDatosProvider), archivo);
        return copia;
      });

  // ---------- PIN ----------

  Future<void> cambiarPin(String actual, String nuevo, String repetir) async {
    if (nuevo != repetir) throw const DatoInvalido('El PIN nuevo no coincide.');
    await ref.read(usuarioServiceProvider).cambiarMiPin(ref.sesion, actual, nuevo);
  }
}
