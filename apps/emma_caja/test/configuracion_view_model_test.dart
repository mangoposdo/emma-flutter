import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/features/configuracion/configuracion_view_model.dart';
import 'package:emma_caja/features/configuracion/logo_en_grises.dart';
import 'package:emma_caja/plataforma/impresora.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'ayudantes.dart';

/// Guarda lo que se manda a imprimir, o falla con [falla].
class _ImpresoraFalsa implements Impresora {
  _ImpresoraFalsa(this.nombres);

  final List<String> nombres;
  String? falla;
  final enviados = <(String, Uint8List)>[];

  @override
  Future<List<String>> instaladas() async => nombres;

  @override
  Future<void> enviarRaw(String impresora, Uint8List datos) async {
    if (falla != null) throw ErrorImpresora(falla!);
    enviados.add((impresora, datos));
  }
}

/// La nube sin internet de verdad: conecta con un código fijo y recibe los
/// eventos (o falla con [errorEnvio]). `http` no es dependencia directa de la
/// app, así que en vez de un MockClient se reemplaza la parte que habla con la red.
class _NubeFalsa extends NubeService {
  _NubeFalsa(super.db) : super(version: 'prueba');

  String? errorEnvio;
  var recibidos = 0;

  Future<void> _escribir(NegociosCompanion datos) async {
    final n = await db.negocio();
    await (db.update(db.negocios)..where((x) => x.id.equals(n.id))).write(datos);
  }

  @override
  Future<String> conectar(Sesion sesion, String codigo, {String? nombrePc}) async {
    if (codigo.trim() != 'EMMA-7K4P-9QX2') throw const EmmaError('Ese código no existe.');
    await _escribir(const NegociosCompanion(
      nubeCajaId: Value('caja-1'),
      nubeLlave: Value('llave'),
      nubeNegocio: Value('Colmado La Bendición'),
      nubeCaja: Value('Caja 1'),
    ));
    return 'Colmado La Bendición';
  }

  @override
  Future<void> enviar(String instalacionId, List<EventoSalida> eventos) async {
    if (errorEnvio != null) throw EmmaError(errorEnvio!);
    recibidos += eventos.length;
    await _escribir(NegociosCompanion(nubeUltimoEnvio: Value(DateTime(2026, 10, 18, 9, 15))));
  }
}

class _Prueba {
  _Prueba(this.b, this.c, this.impresora, this.nube, this.carpeta);

  final Banco b;
  final ProviderContainer c;
  final _ImpresoraFalsa impresora;
  final _NubeFalsa nube;
  final Directory carpeta;

  ConfiguracionViewModel get vm => c.read(configuracionViewModelProvider.notifier);
  ConfiguracionState get s => c.read(configuracionViewModelProvider).value!;
  EmmaDatabase get db => b.db;

  static Future<_Prueba> crear({Future<void> Function(EmmaDatabase db)? antes}) async {
    final b = await Banco.crear();
    if (antes != null) await antes(b.db);
    final carpeta = await Directory.systemTemp.createTemp('emma_config_');
    addTearDown(() => carpeta.delete(recursive: true));
    final impresora = _ImpresoraFalsa(['Termica 80', 'Termica 58']);
    final nube = _NubeFalsa(b.db);
    final c = ProviderContainer.test(overrides: [
      baseDeDatosProvider.overrideWithValue(b.db),
      carpetaDatosProvider.overrideWithValue(carpeta),
      impresoraProvider.overrideWithValue(impresora),
      nubeServiceProvider.overrideWithValue(nube),
    ]);
    c.read(sesionProvider.notifier).entrar(b.dueno);
    c.listen(configuracionViewModelProvider, (_, __) {});
    await c.read(configuracionViewModelProvider.future);
    return _Prueba(b, c, impresora, nube, carpeta);
  }
}

Matcher _mensaje(String texto) => isA<EmmaError>().having((e) => e.mensaje, 'mensaje', texto);

bool _contiene(List<int> datos, String texto) {
  final buscado = codificarCp850(texto);
  for (var i = 0; i + buscado.length <= datos.length; i++) {
    var igual = true;
    for (var j = 0; j < buscado.length && igual; j++) {
      igual = datos[i + j] == buscado[j];
    }
    if (igual) return true;
  }
  return false;
}

Future<void> _ponerNegocio(EmmaDatabase db, NegociosCompanion datos) async {
  final n = await db.negocio();
  await (db.update(db.negocios)..where((x) => x.id.equals(n.id))).write(datos);
}

void main() {
  test('carga lo guardado en la pantalla', () async {
    final t = await _Prueba.crear(
      antes: (db) => _ponerNegocio(db, const NegociosCompanion(impresora: Value('Vieja USB'), cargoDelivery: Value(7550))),
    );
    final s = t.s;
    expect(s.borrador.nombre, 'Mi Colmado');
    expect(s.borrador.mensaje, 'Gracias por su compra');
    expect(s.borrador.envio, '75.5');
    expect(s.impresoraEscogida, 'Vieja USB');
    // La guardada sale aunque ya no esté instalada.
    expect(s.opcionesImpresora, ['(no imprimir)', 'Termica 80', 'Termica 58', 'Vieja USB']);
    expect((s.borrador.anchoTicket, s.borrador.abrirGaveta, s.borrador.ticketOscuro), (48, true, true));
    expect(s.hayLogo, isFalse);
    expect(s.conectada, isFalse);
    final respaldos = p.join(t.carpeta.path, 'Respaldos');
    expect(s.carpetaRespaldos, respaldos);
    expect(
      s.textoRespaldos,
      'Los respaldos automáticos se guardan en $respaldos. Se hace uno al abrir el programa, cada 2 horas y al '
      'cerrar la caja; se guardan los últimos 20 y uno por día del último mes.',
    );
    expect(s.textoVersion, 'Emma versión 1.0.0 · Datos en ${p.join(t.carpeta.path, 'emma.db')}');
  });

  test('el envío se muestra como "0.##"', () async {
    final t = await _Prueba.crear();
    String envio(int c) => Borrador.de(t.s.negocio.copyWith(cargoDelivery: c)).envio;
    expect([envio(0), envio(5000), envio(7550), envio(7505)], ['0', '50', '75.5', '75.05']);
  });

  test('guardar la configuración guarda lo de la pantalla y refresca el menú', () async {
    final t = await _Prueba.crear();
    expect((await t.c.read(negocioProvider.future)).nombre, 'Mi Colmado');

    t.vm.cambiar((b) => b.copyWith(
          nombre: '  Colmado La Bendición ',
          rnc: '  ',
          direccion: 'Calle 5, Los Mina',
          telefono: '809-555-1234',
          mensaje: ' Vuelva pronto ',
          envio: '75.50',
          anchoTicket: 32,
          abrirGaveta: false,
          ticketOscuro: false,
          intensidad: IntensidadTicket.maxima,
          carpetaExterna: '/Volumes/USB/Respaldos',
        ));
    t.vm.escogerImpresora('Termica 58');
    final m = await t.vm.guardar();
    expect((m.texto, m.tono), ('Configuración guardada.', Tono.info));

    final n = await t.db.negocio();
    expect(n.nombre, 'Colmado La Bendición');
    expect(n.rnc, isNull);
    expect((n.direccion, n.telefono, n.mensajeTicket), ('Calle 5, Los Mina', '809-555-1234', 'Vuelva pronto'));
    expect((n.cargoDelivery, n.impresora, n.anchoTicket), (7550, 'Termica 58', 32));
    expect((n.abrirGaveta, n.ticketOscuro, n.intensidadTicket), (false, false, IntensidadTicket.maxima));
    expect(n.carpetaRespaldoExterna, '/Volumes/USB/Respaldos');
    expect((await t.c.read(negocioProvider.future)).nombre, 'Colmado La Bendición');
    expect(t.s.negocio.nombre, 'Colmado La Bendición');

    // "(no imprimir)" guarda la impresora vacía; un envío mal escrito queda en 0.
    t.vm.escogerImpresora(noImprimir);
    t.vm.cambiar((b) => b.copyWith(envio: 'abc'));
    expect(t.s.impresoraEscogida, noImprimir);
    await t.vm.guardar();
    final otra = await t.db.negocio();
    expect((otra.impresora, otra.cargoDelivery), (null, 0));
  });

  test('sin nombre no se guarda', () async {
    final t = await _Prueba.crear();
    t.vm.cambiar((b) => b.copyWith(nombre: '   '));
    await expectLater(t.vm.guardar(), throwsA(_mensaje('Escriba el nombre del negocio.')));
    expect((await t.db.negocio()).nombre, 'Mi Colmado');
  });

  test('imprimir prueba usa la impresora y los datos de la pantalla sin guardarlos', () async {
    final t = await _Prueba.crear();
    t.vm.escogerImpresora(noImprimir);
    expect((await t.vm.imprimirPrueba()).texto, 'Escoja una impresora.');
    expect(t.impresora.enviados, isEmpty);

    t.vm.escogerImpresora('Termica 80');
    t.vm.cambiar((b) => b.copyWith(nombre: 'Colmado Prueba', telefono: '809-000-0000'));
    final m = await t.vm.imprimirPrueba();
    expect((m.texto, m.tono), ('Se envió la prueba. Si no salió bien, revise el driver y el tamaño de papel.', Tono.info));
    final (impresora, datos) = t.impresora.enviados.single;
    expect(impresora, 'Termica 80');
    for (final texto in [
      'Colmado Prueba',
      'Tel. 809-000-0000',
      'Cajero: Dueño',
      'Cliente: Prueba de impresión',
      'Acentos: áéíóú ñ Ñ ¿?',
      'Arroz selecto (libra)',
      '  5 x 46.90',
      '234.50',
      'RD\$1,234.50',
      '265.50',
    ]) {
      expect(_contiene(datos, texto), isTrue, reason: texto);
    }
    expect((await t.db.negocio()).nombre, 'Mi Colmado');

    t.impresora.falla = 'La impresora no aceptó el trabajo.';
    final error = await t.vm.imprimirPrueba();
    expect(error.tono, Tono.error);
    expect(error.texto, startsWith('No se pudo imprimir en "Termica 80".'));
    expect(error.texto, contains('La impresora no aceptó el trabajo.'));
  });

  group('logo', () {
    test('a grises sobre fondo blanco con la fórmula de la 0.7', () {
      final rgba = Uint8List.fromList([
        0, 0, 0, 255, // negro
        255, 255, 255, 255, // blanco
        0, 0, 0, 0, // transparente: blanco
        0, 0, 0, 128, // negro a medias
        255, 0, 0, 255, // rojo
        10, 200, 30, 255, // verde
      ]);
      expect(grisesSobreBlanco(rgba), [0, 255, 255, 127, 76, 123]);
    });

    test('se dibuja desde los puntos: bit 1 = negro, 8 por byte, fila por fila', () {
      final puntos = Uint8List.fromList([0x80, 0x01, 0x00, 0xFF]);
      expect(altoDelLogo(puntos, 16), 2);
      final rgba = rgbaDelLogo(puntos, 16);
      int pixel(int x, int y) => rgba[(y * 16 + x) * 4];
      expect([pixel(0, 0), pixel(1, 0), pixel(14, 0), pixel(15, 0)], [0, 255, 255, 0]);
      expect([pixel(0, 1), pixel(7, 1), pixel(8, 1), pixel(15, 1)], [255, 255, 0, 0]);
      expect(rgba[3], 255);
    });

    test('poner y quitar el logo', () async {
      final t = await _Prueba.crear();
      // 40 x 20: la mitad izquierda negra, la derecha blanca.
      final grises = Uint8List.fromList([
        for (var y = 0; y < 20; y++)
          for (var x = 0; x < 40; x++) x < 20 ? 0 : 255,
      ]);
      final m = await t.vm.ponerLogo(grises, 40, 20);
      expect(m.texto, 'Logo guardado. Use "Imprimir prueba" para ver cómo sale.');
      final n = await t.db.negocio();
      expect(n.logoAncho, 40);
      expect(n.logoTicket, hasLength(5 * 20));
      expect(n.logoTicket!.first, 0xFF);
      expect(t.s.hayLogo, isTrue);
      expect(t.s.negocio.logoAncho, 40);

      await t.vm.quitarLogo();
      final sin = await t.db.negocio();
      expect((sin.logoTicket, sin.logoAncho), (null, null));
      expect(t.s.hayLogo, isFalse);

      await expectLater(t.vm.ponerLogo(Uint8List(0), 0, 0), throwsA(isA<EmmaError>()));
    });
  });

  test('repartidores: agregar, editar y quitar', () async {
    final t = await _Prueba.crear();
    await t.vm.guardarRepartidor(nombre: 'Juan', telefono: '809-555-1234');
    await t.vm.guardarRepartidor(nombre: 'Pedro');
    expect([for (final r in t.s.repartidores) textoRepartidor(r)], ['Juan  ·  809-555-1234', 'Pedro']);

    t.vm.escogerRepartidor(0);
    final juan = t.s.repartidor!;
    expect(juan.nombre, 'Juan');
    await t.vm.guardarRepartidor(id: juan.id, nombre: 'Juan Pérez', telefono: juan.telefono);
    expect(t.s.repartidorEscogido, isNull);
    expect([for (final r in t.s.repartidores) r.nombre], ['Juan Pérez', 'Pedro']);

    await expectLater(t.vm.guardarRepartidor(nombre: 'pedro'), throwsA(_mensaje('Ya hay un repartidor llamado pedro.')));

    await t.vm.quitarRepartidor(t.s.repartidores.last);
    expect([for (final r in t.s.repartidores) r.nombre], ['Juan Pérez']);
    final todos = await t.db.select(t.db.repartidores).get();
    expect(todos.firstWhere((r) => r.nombre == 'Pedro').activo, isFalse);
  });

  group('nube', () {
    Future<void> eventos(EmmaDatabase db, int n) async {
      for (var i = 0; i < n; i++) {
        await db.encolarEvento('prueba', {'n': i}, DateTime(2026, 10, 18, 8, i));
      }
    }

    test('conectar sube lo guardado y muestra el estado', () async {
      final t = await _Prueba.crear();
      await eventos(t.db, 3);
      final pendientes = await t.c.read(sincronizacionServiceProvider).pendientes();
      expect(await t.vm.enviarAhora(), isNull);

      await expectLater(t.vm.conectar('MAL'), throwsA(_mensaje('Ese código no existe.')));
      expect(t.s.conectando, isFalse);

      final m = await t.vm.conectar('EMMA-7K4P-9QX2');
      expect(
        m.texto,
        'Listo. Esta caja quedó conectada a Colmado La Bendición.\n\nSe subieron $pendientes datos guardados.'
        '\n\nYa puede ver las ventas en la web de Emma, en Mi colmado.',
      );
      expect(t.nube.recibidos, pendientes);
      expect(t.s.conectada, isTrue);
      expect(t.s.conectando, isFalse);
      expect(t.s.textoNube, '✔ Conectada a Colmado La Bendición como Caja 1.');
      expect(
        t.s.detalleNube,
        'Último envío: 18/10/2026 09:15 AM. No hay nada pendiente. Las ventas suben solas cada minuto cuando hay internet.',
      );
      expect(await t.c.read(estadoNubeProvider.future), 'Nube al día');
    });

    test('enviar ahora: al día, enviados y sin internet', () async {
      final t = await _Prueba.crear();
      await t.vm.conectar('EMMA-7K4P-9QX2');

      expect((await t.vm.enviarAhora())!.texto, 'Todo estaba al día.');
      await eventos(t.db, 2);
      expect((await t.vm.enviarAhora())!.texto, 'Se enviaron 2 datos.');

      t.nube.errorEnvio = 'Sin internet.';
      await eventos(t.db, 1);
      final m = (await t.vm.enviarAhora())!;
      expect(m.tono, Tono.aviso);
      expect(
        m.texto,
        'No se pudo enviar ahora: Sin internet.\n\nLos datos siguen guardados y se envían solos cuando vuelva el internet.',
      );
      expect(t.s.pendientes, 1);
      expect(t.s.detalleNube, contains('1 datos esperando para subir.'));
      expect(t.s.enviando, isFalse);
    });

    test('desconectar', () async {
      final t = await _Prueba.crear();
      await t.vm.conectar('EMMA-7K4P-9QX2');
      await t.vm.desconectar();
      expect(t.s.conectada, isFalse);
      expect(await t.c.read(estadoNubeProvider.future), '');
      expect(await t.vm.enviarAhora(), isNull);
    });

    test('sin envíos todavía', () async {
      final t = await _Prueba.crear(
        antes: (db) => _ponerNegocio(db, const NegociosCompanion(
          nubeCajaId: Value('caja-1'),
          nubeNegocio: Value('Colmado X'),
          nubeCaja: Value('Caja 2'),
        )),
      );
      await eventos(t.db, 4);
      t.c.invalidate(configuracionViewModelProvider);
      await t.c.read(configuracionViewModelProvider.future);
      expect(t.s.textoNube, '✔ Conectada a Colmado X como Caja 2.');
      expect(t.s.detalleNube, startsWith('Todavía no ha enviado. '));
      expect(t.s.detalleNube, contains('datos esperando para subir.'));
    });
  });

  test('cambiar mi PIN', () async {
    final t = await _Prueba.crear();
    await expectLater(t.vm.cambiarPin('1234', '5678', '5679'), throwsA(_mensaje('El PIN nuevo no coincide.')));
    await expectLater(t.vm.cambiarPin('0000', '5678', '5678'), throwsA(_mensaje('El PIN actual no es correcto.')));
    await t.vm.cambiarPin('1234', '5678', '5678');
    final usuarios = t.c.read(usuarioServiceProvider);
    expect(await usuarios.iniciarSesion('admin', '5678'), isNotNull);
    expect(await usuarios.iniciarSesion('admin', '1234'), isNull);
  });

  test('respaldar ahora guarda la configuración y copia también a la carpeta externa', () async {
    final t = await _Prueba.crear();
    final externa = Directory(p.join(t.carpeta.path, 'USB'));
    t.vm.cambiar((b) => b.copyWith(carpetaExterna: externa.path));
    final m = await t.vm.respaldarAhora();
    expect((await t.db.negocio()).carpetaRespaldoExterna, externa.path);
    final lineas = m.texto.split('\n');
    expect(lineas, hasLength(2));
    expect(lineas[0], startsWith('Respaldo guardado en ${t.s.carpetaRespaldos}'));
    expect(lineas[1], startsWith('Copia externa en ${externa.path}'));
    expect(RespaldoService.listar(externa), hasLength(1));
  });

  test('restaurar valida el archivo, guarda una copia y pone el respaldo', () async {
    final t = await _Prueba.crear();
    final falso = File(p.join(t.carpeta.path, 'otra_cosa.db'))..writeAsStringSync('no soy una base');
    await expectLater(t.vm.restaurar(falso.path), throwsA(_mensaje('Ese archivo no es un respaldo de este sistema.')));

    final respaldo = await t.c.read(respaldoServiceProvider).respaldar();
    final copia = await t.vm.restaurar(respaldo);
    expect(p.dirname(copia), p.join(t.s.carpetaRespaldos, 'AntesDeRestaurar'));
    expect(File(copia).existsSync(), isTrue);
    final base = File(p.join(t.carpeta.path, nombreArchivoBase));
    expect(base.existsSync(), isTrue);
    expect(base.lengthSync(), File(respaldo).lengthSync());
    // La base quedó cerrada: el programa tiene que abrirse de nuevo.
    await expectLater(t.db.negocio(), throwsA(anything));
  });
}
