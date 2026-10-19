import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/plataforma/impresora.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base en memoria con dos productos y un contenedor de Riverpod sobre ella,
/// con la sesión del dueño ya abierta. El contenedor se descarta solo al final
/// de la prueba.
class Banco {
  Banco._(this.db, this.dueno, this.c);

  final EmmaDatabase db;
  final Sesion dueno;
  final ProviderContainer c;

  /// RD$ 95.00 la unidad.
  static const refresco = '7460001';

  /// RD$ 45.00 la libra.
  static const arroz = '200';

  static Future<Banco> crear({bool comoCajero = false}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = EmmaDatabase(NativeDatabase.memory(), pinHasher: PinHasher(vueltas: 1000));
    final u = await (db.select(db.usuarios)..where((u) => u.login.equals(loginInicial))).getSingle();
    final dueno = Sesion(usuarioId: u.id, nombre: u.nombre, rol: u.rol);
    await db.into(db.productos).insert(ProductosCompanion.insert(
          codigo: const Value(refresco),
          nombre: 'Refresco Country Club 2 L',
          precio: 9500,
          costo: const Value(7000),
          existencia: const Value(24000),
          esRapido: const Value(true),
        ));
    await db.into(db.productos).insert(ProductosCompanion.insert(
          codigo: const Value(arroz),
          nombre: 'Arroz Selecto',
          precio: 4500,
          costo: const Value(3500),
          existencia: const Value(50000),
          unidad: const Value(UnidadVenta.libra),
        ));
    final c = ProviderContainer.test(overrides: [
      baseDeDatosProvider.overrideWithValue(db),
      carpetaDatosProvider.overrideWithValue(Directory.systemTemp),
      impresoraProvider.overrideWithValue(ImpresoraDePrueba()),
    ]);
    var sesion = dueno;
    if (comoCajero) {
      final id = await db.into(db.usuarios).insert(UsuariosCompanion.insert(
            nombre: 'María',
            login: 'maria',
            pinHash: await db.pinHasher.hash('4321'),
            rol: Rol.cajero,
          ));
      sesion = Sesion(usuarioId: id, nombre: 'María', rol: Rol.cajero);
    }
    c.read(sesionProvider.notifier).entrar(sesion);
    return Banco._(db, dueno, c);
  }

  Future<void> abrirCaja() => CajaService(db).abrir(dueno, 100000);

  Future<Producto> producto(String codigo) async =>
      (await (db.select(db.productos)..where((p) => p.codigo.equals(codigo))).getSingle());

  Future<int> contar(String tabla) async {
    final f = await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle();
    return f.read<int>('n');
  }
}

/// Impresora que no toca el sistema: guarda lo que se le manda.
class ImpresoraDePrueba implements Impresora {
  final enviados = <(String, Uint8List)>[];

  @override
  Future<List<String>> instaladas() async => const ['Térmica de prueba'];

  @override
  Future<void> enviarRaw(String impresora, Uint8List datos) async => enviados.add((impresora, datos));
}
