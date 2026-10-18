import 'db/enums.dart';

/// Quién está usando la caja ahora.
class Sesion {
  const Sesion({required this.usuarioId, required this.nombre, required this.rol});

  final int usuarioId;
  final String nombre;
  final Rol rol;

  bool get esDueno => rol == Rol.dueno;
}

/// Hora actual. Se inyecta para poder probar con horas fijas.
typedef Reloj = DateTime Function();

DateTime relojDelSistema() => DateTime.now();
