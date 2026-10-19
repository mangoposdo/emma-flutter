import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class UsuariosState {
  const UsuariosState({this.usuarios = const [], this.bitacora = const [], this.escogido});

  final List<Usuario> usuarios;
  final List<LineaBitacora> bitacora;

  /// Fila escogida en la tabla de usuarios.
  final int? escogido;

  Usuario? get usuarioEscogido {
    final i = escogido;
    return i == null || i < 0 || i >= usuarios.length ? null : usuarios[i];
  }

  UsuariosState escoger(int? i) => UsuariosState(usuarios: usuarios, bitacora: bitacora, escogido: i);
}

/// Como sale el rol en la tabla.
String textoRol(Rol r) => r == Rol.dueno ? 'Dueño' : 'Cajero';

/// Como sale el rol en el formulario.
String textoRolFormulario(Rol r) => r == Rol.dueno ? 'Dueño (todo)' : 'Cajero (vende, cobra, cuadra)';

final usuariosViewModelProvider =
    AsyncNotifierProvider.autoDispose<UsuariosViewModel, UsuariosState>(UsuariosViewModel.new);

/// Usuarios y bitácora de la 0.7. Solo el dueño.
class UsuariosViewModel extends AsyncNotifier<UsuariosState> {
  @override
  Future<UsuariosState> build() => _cargar();

  Future<UsuariosState> _cargar() async {
    final u = ref.read(usuarioServiceProvider);
    return UsuariosState(usuarios: await u.lista(), bitacora: await u.bitacora(ref.sesion));
  }

  void escoger(int i) {
    final s = state.value;
    if (s != null) state = AsyncData(s.escoger(i));
  }

  /// Crea ([id] null) o cambia un usuario. [pin] vacío o null deja el PIN como está.
  Future<void> guardar({
    int? id,
    required String nombre,
    required String login,
    required Rol rol,
    required bool activo,
    String? pin,
  }) async {
    await ref.read(usuarioServiceProvider).guardar(
          ref.sesion,
          DatosUsuario(id: id, nombre: nombre, login: login, rol: rol, activo: activo),
          pinNuevo: pin,
        );
    final nuevo = await _cargar();
    if (ref.mounted) state = AsyncData(nuevo);
  }
}
