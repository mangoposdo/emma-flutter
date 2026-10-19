import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'app/carpeta_datos.dart';
import 'app/cuidados.dart';
import 'app/datos_de_prueba.dart';
import 'app/emma_caja_app.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final carpeta = await carpetaDeDatos();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    registrarError(carpeta, d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, pila) {
    registrarError(carpeta, e, pila);
    return true;
  };
  await _arrancar(carpeta);
}

Future<void> _arrancar(Directory carpeta) async {
  await carpeta.create(recursive: true);

  // Si la base está dañada (un apagón con el disco escribiendo), se ofrece el
  // último respaldo sano. La dañada se guarda aparte para soporte.
  final problema = RespaldoService.problemaDeLaBase(File(p.join(carpeta.path, nombreArchivoBase)));
  if (problema != null) {
    registrarError(carpeta, 'Base de datos dañada: $problema', null);
    final respaldo = RespaldoService.ultimoSano(carpeta);
    if (respaldo == null) {
      runApp(PantallaDeArranque(
        titulo: 'La base de datos está dañada',
        mensaje: 'No se encontró un respaldo sano en ${RespaldoService.carpetaLocal(carpeta).path}.\n\n'
            'No cierre ni borre nada y llame a soporte.',
        alSalir: () => exit(1),
      ));
      return;
    }
    final fecha = formatoFechaHora(File(respaldo).lastModifiedSync());
    runApp(PantallaDeArranque(
      titulo: 'La base de datos está dañada',
      mensaje: '¿Poner el último respaldo sano, del $fecha? Se pierde lo que se hizo después de esa hora. '
          'La base dañada se guarda aparte para soporte.',
      accion: 'Poner el respaldo',
      alAccion: () async {
        await RespaldoService.reemplazarDanada(carpeta, respaldo);
        await _arrancar(carpeta);
      },
      alSalir: () => exit(1),
    ));
    return;
  }

  final EmmaDatabase db;
  try {
    db = await abrirBaseDeDatos(carpeta);
  } on EmmaError catch (e) {
    runApp(PantallaDeArranque(titulo: 'No se pudo abrir la caja', mensaje: e.mensaje, alSalir: () => exit(1)));
    return;
  } catch (e, pila) {
    registrarError(carpeta, e, pila);
    runApp(PantallaDeArranque(
      titulo: 'No se pudo abrir la caja',
      mensaje: 'No se pudo abrir la base de datos. ¿Hay otra copia de Emma abierta? Ciérrela; si sigue, llame a soporte.',
      alSalir: () => exit(1),
    ));
    return;
  }

  if (kDebugMode) await sembrarDatosDePrueba(db);

  final contenedor = ProviderContainer(overrides: [
    carpetaDatosProvider.overrideWithValue(carpeta),
    baseDeDatosProvider.overrideWithValue(db),
  ]);
  await contenedor.read(cuidadosProvider).iniciar();
  runApp(UncontrolledProviderScope(container: contenedor, child: const EmmaCajaApp()));
}
