import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:emma_core/emma_core.dart';

/// Hora fija de las pruebas.
final horaPrueba = DateTime(2026, 10, 18, 10, 30, 5);

/// Base en memoria. PBKDF2 con pocas vueltas para que las pruebas corran rápido.
EmmaDatabase baseDePrueba({Reloj? reloj}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var n = 0;
  return EmmaDatabase(
    NativeDatabase.memory(),
    pinHasher: PinHasher(vueltas: 1000),
    nuevoUuid: () => 'uuid-${++n}',
    reloj: reloj ?? () => horaPrueba,
  );
}

Future<Sesion> sesionDueno(EmmaDatabase db) async {
  final u = await (db.select(db.usuarios)..where((u) => u.login.equals(loginInicial))).getSingle();
  return Sesion(usuarioId: u.id, nombre: u.nombre, rol: u.rol);
}

Future<Sesion> crearCajero(EmmaDatabase db, {String nombre = 'María'}) async {
  final id = await db.into(db.usuarios).insert(UsuariosCompanion.insert(
        nombre: nombre,
        login: nombre.toLowerCase(),
        pinHash: await db.pinHasher.hash('4321'),
        rol: Rol.cajero,
      ));
  return Sesion(usuarioId: id, nombre: nombre, rol: Rol.cajero);
}

/// Mientras no exista CajaService (siguiente tarea de la Fase 1), se abre el
/// turno escribiendo la fila directo.
Future<int> abrirTurno(EmmaDatabase db, Sesion s, {int fondo = 100000}) =>
    db.into(db.turnosCaja).insert(TurnosCajaCompanion.insert(
          usuarioId: s.usuarioId,
          apertura: horaPrueba,
          fondoInicial: fondo,
        ));

/// Precios en centavos, existencia en milésimas.
Future<int> crearProducto(
  EmmaDatabase db, {
  required String codigo,
  required String nombre,
  required int precio,
  int costo = 0,
  int existencia = 0,
  UnidadVenta unidad = UnidadVenta.unidad,
}) =>
    db.into(db.productos).insert(ProductosCompanion.insert(
          codigo: codigo,
          nombre: nombre,
          precio: precio,
          costo: Value(costo),
          existencia: Value(existencia),
          unidad: Value(unidad),
        ));

Future<int> crearCliente(EmmaDatabase db, {required String nombre, int limite = 0}) =>
    db.into(db.clientes).insert(ClientesCompanion.insert(
          nombre: nombre,
          limiteCredito: Value(limite),
        ));

Future<Producto> producto(EmmaDatabase db, int id) =>
    (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

Future<int> contar(EmmaDatabase db, String tabla) async {
  final fila = await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle();
  return fila.read<int>('n');
}
