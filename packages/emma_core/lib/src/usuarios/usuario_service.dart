import 'package:drift/drift.dart';

import '../db/database.dart';
import '../errores.dart';
import '../sesion.dart';

class DatosUsuario {
  const DatosUsuario({this.id, required this.nombre, required this.login, this.rol = Rol.cajero, this.activo = true});

  final int? id;
  final String nombre;
  final String login;
  final Rol rol;
  final bool activo;
}

/// Una línea de la bitácora con el nombre de quien la hizo.
class LineaBitacora {
  const LineaBitacora(this.entrada, this.usuario);

  final EntradaBitacora entrada;
  final String usuario;
}

/// Entrar con usuario y PIN, administrar usuarios y ver la bitácora.
class UsuarioService {
  UsuarioService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  /// Valida usuario y PIN. Devuelve la sesión, o null si no es correcto.
  /// Los intentos fallidos quedan en la bitácora.
  Future<Sesion?> iniciarSesion(String login, String pin) async {
    final l = login.trim().toLowerCase();
    final u = await (db.select(db.usuarios)..where((x) => x.login.equals(l) & x.activo.equals(true))).getSingleOrNull();
    final fecha = _reloj();
    if (u == null || !await db.pinHasher.verificar(pin, u.pinHash)) {
      await db.anotarBitacora(usuarioId: null, accion: 'Intento de entrada fallido', detalle: login.trim(), fecha: fecha);
      return null;
    }
    await db.anotarBitacora(usuarioId: u.id, accion: 'Inicio de sesión', fecha: fecha);
    return Sesion(usuarioId: u.id, nombre: u.nombre, rol: u.rol);
  }

  Future<List<Usuario>> lista() => (db.select(db.usuarios)..orderBy([(u) => OrderingTerm.asc(u.nombre)])).get();

  /// Crea o modifica un usuario. [pinNuevo] vacío deja el PIN como está.
  Future<Usuario> guardar(Sesion sesion, DatosUsuario d, {String? pinNuevo}) async {
    requiereDueno(sesion.esDueno, 'administrar usuarios');
    final nombre = d.nombre.trim();
    final login = d.login.trim().toLowerCase();
    if (nombre.isEmpty || login.isEmpty) throw const DatoInvalido('Escriba el nombre y el usuario.');
    final pin = pinNuevo ?? '';
    if (pin.isNotEmpty) _validarPin(pin);
    final fecha = _reloj();
    // El hash tarda: se calcula antes de abrir la transacción.
    final hash = pin.isEmpty ? null : await db.pinHasher.hash(pin);

    return db.transaction(() async {
      final repetido = await (db.select(db.usuarios)
            ..where((u) => u.login.equals(login) & (d.id == null ? const Constant(true) : u.id.equals(d.id!).not())))
          .getSingleOrNull();
      if (repetido != null) throw DatoInvalido('Ya existe el usuario $login.');

      final int id;
      if (d.id == null) {
        if (hash == null) throw const DatoInvalido('El usuario nuevo necesita un PIN.');
        id = await db.into(db.usuarios).insert(UsuariosCompanion.insert(
              nombre: nombre,
              login: login,
              pinHash: hash,
              rol: d.rol,
              activo: Value(d.activo),
            ));
      } else {
        final antes = await (db.select(db.usuarios)..where((u) => u.id.equals(d.id!))).getSingleOrNull();
        if (antes == null) throw const DatoInvalido('El usuario no existe.');
        final dejaDeSerDueno = antes.rol == Rol.dueno && (d.rol != Rol.dueno || !d.activo);
        if (dejaDeSerDueno) {
          final otros = await (db.select(db.usuarios)
                ..where((u) => u.id.equals(antes.id).not() & u.rol.equalsValue(Rol.dueno) & u.activo.equals(true)))
              .get();
          if (otros.isEmpty) throw const DatoInvalido('Debe quedar al menos un dueño activo.');
        }
        await (db.update(db.usuarios)..where((u) => u.id.equals(antes.id))).write(UsuariosCompanion(
          nombre: Value(nombre),
          login: Value(login),
          rol: Value(d.rol),
          activo: Value(d.activo),
          pinHash: hash == null ? const Value.absent() : Value(hash),
        ));
        id = antes.id;
      }
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: d.id == null ? 'Usuario creado' : 'Usuario modificado',
        detalle: login,
        fecha: fecha,
      );
      return (db.select(db.usuarios)..where((u) => u.id.equals(id))).getSingle();
    });
  }

  Future<void> cambiarMiPin(Sesion sesion, String pinActual, String pinNuevo) async {
    _validarPin(pinNuevo);
    final u = await (db.select(db.usuarios)..where((x) => x.id.equals(sesion.usuarioId))).getSingle();
    if (!await db.pinHasher.verificar(pinActual, u.pinHash)) {
      throw const DatoInvalido('El PIN actual no es correcto.');
    }
    final hash = await db.pinHasher.hash(pinNuevo);
    await (db.update(db.usuarios)..where((x) => x.id.equals(u.id))).write(UsuariosCompanion(pinHash: Value(hash)));
    await db.anotarBitacora(usuarioId: sesion.usuarioId, accion: 'Cambio de PIN', fecha: _reloj());
  }

  /// True si el usuario admin todavía usa el PIN de fábrica 1234.
  Future<bool> usaPinDeFabrica() async {
    final u = await (db.select(db.usuarios)..where((x) => x.login.equals(loginInicial) & x.activo.equals(true)))
        .getSingleOrNull();
    return u != null && await db.pinHasher.verificar(pinInicial, u.pinHash);
  }

  /// Las últimas entradas de la bitácora. Solo el dueño.
  Future<List<LineaBitacora>> bitacora(Sesion sesion, {int cantidad = 300}) async {
    requiereDueno(sesion.esDueno, 'ver la bitácora');
    final q = db.select(db.bitacora).join([
      leftOuterJoin(db.usuarios, db.usuarios.id.equalsExp(db.bitacora.usuarioId)),
    ])
      ..orderBy([OrderingTerm.desc(db.bitacora.id)])
      ..limit(cantidad);
    final filas = await q.get();
    return [
      for (final f in filas) LineaBitacora(f.readTable(db.bitacora), f.readTableOrNull(db.usuarios)?.nombre ?? ''),
    ];
  }

  static void _validarPin(String pin) {
    if (pin.length < 4) throw const DatoInvalido('El PIN debe tener al menos 4 caracteres.');
  }
}
