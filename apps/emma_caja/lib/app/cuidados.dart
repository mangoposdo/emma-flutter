import 'dart:async';
import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'providers.dart';

/// Avisos del arranque que se muestran al entrar (reloj atrasado...).
final avisosDeArranqueProvider = NotifierProvider<AvisosDeArranque, List<String>>(AvisosDeArranque.new);

class AvisosDeArranque extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void agregar(String aviso) => state = [...state, aviso];

  /// Los avisos pendientes; quedan vistos.
  List<String> tomar() {
    final a = state;
    state = const [];
    return a;
  }
}

final cuidadosProvider = Provider((ref) {
  final c = Cuidados(ref);
  ref.onDispose(c.parar);
  return c;
});

/// Respaldo al abrir y cada 2 horas, mantenimiento semanal y envío a la nube
/// cada minuto. Nunca deben impedir vender: si fallan se anota y se sigue.
class Cuidados {
  Cuidados(this._ref);

  final Ref _ref;
  Timer? _respaldo;
  Timer? _nube;
  var _enviando = false;

  Future<void> iniciar() async {
    await _sinFallar(() => _ref.read(respaldoServiceProvider).respaldar());
    _respaldo = Timer.periodic(const Duration(hours: 2), (_) => _sinFallar(() => _ref.read(respaldoServiceProvider).respaldar()));
    await _sinFallar(() => _ref.read(mantenimientoServiceProvider).hacerSiToca());
    await _sinFallar(() async {
      final aviso = await _ref.read(mantenimientoServiceProvider).revisarReloj();
      if (aviso != null) _ref.read(avisosDeArranqueProvider.notifier).agregar(aviso);
    });
    _nube = Timer.periodic(const Duration(minutes: 1), (_) => enviarANube());
    unawaited(enviarANube());
  }

  void parar() {
    _respaldo?.cancel();
    _nube?.cancel();
  }

  /// Sube lo pendiente si la caja está conectada. null si no está conectada o
  /// ya se está enviando.
  Future<ResultadoSincronizacion?> enviarANube() async {
    if (_enviando) return null;
    _enviando = true;
    try {
      if (!await _ref.read(nubeServiceProvider).conectada()) return null;
      final r = await _ref.read(sincronizacionServiceProvider).sincronizar();
      _ref.invalidate(estadoNubeProvider);
      return r;
    } catch (e, pila) {
      registrarError(_ref.read(carpetaDatosProvider), e, pila);
      return null;
    } finally {
      _enviando = false;
    }
  }

  /// Respaldo en la carpeta local y, si está configurada, en la USB o carpeta
  /// externa. Devuelve el texto para mostrar.
  Future<String> respaldoCompleto() async {
    final r = _ref.read(respaldoServiceProvider);
    final mensajes = ['Respaldo guardado en ${await r.respaldar()}'];
    final externa = (await _ref.read(negocioServiceProvider).negocio()).carpetaRespaldoExterna;
    if (externa != null && externa.trim().isNotEmpty) {
      try {
        final raiz = p.rootPrefix(externa);
        if (raiz.isNotEmpty && !Directory(raiz).existsSync()) {
          mensajes.add('No se encontró la unidad $raiz (¿conectó la USB?).');
        } else {
          mensajes.add('Copia externa en ${await r.respaldar(Directory(externa))}');
        }
      } catch (e) {
        mensajes.add('No se pudo copiar a la carpeta externa: $e');
      }
    }
    return mensajes.join('\n');
  }

  Future<void> _sinFallar(Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e, pila) {
      registrarError(_ref.read(carpetaDatosProvider), e, pila);
    }
  }
}

/// Guarda los errores inesperados en errores.log, en la carpeta de datos, para soporte.
void registrarError(Directory carpeta, Object error, StackTrace? pila) {
  debugPrint('Error: $error\n$pila');
  try {
    final f = DateTime.now();
    File(p.join(carpeta.path, 'errores.log')).writeAsStringSync(
      '[${f.toIso8601String()}] $error\n$pila\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } on FileSystemException {
    // Si no se puede escribir el registro, se sigue.
  }
}
