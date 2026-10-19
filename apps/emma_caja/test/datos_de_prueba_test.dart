import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:emma_caja/app/datos_de_prueba.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una base nueva recibe los productos de prueba una sola vez', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = EmmaDatabase(NativeDatabase.memory(), pinHasher: PinHasher(vueltas: 1000));
    addTearDown(db.close);
    await sembrarDatosDePrueba(db);
    final vendibles = await ProductoService(db).listado();
    expect(vendibles, hasLength(15));
    expect((await ProductoService(db).rapidos()).length, greaterThan(0));
    await sembrarDatosDePrueba(db);
    expect(await ProductoService(db).listado(), hasLength(15));
  });
}
