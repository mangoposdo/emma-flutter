import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class EntrarState {
  const EntrarState({this.negocio = '', this.primeraVez = false, this.intentos = 0, this.entrando = false});

  final String negocio;

  /// El admin todavía usa el PIN 1234: se dice en la pantalla.
  final bool primeraVez;
  final int intentos;
  final bool entrando;

  EntrarState copyWith({int? intentos, bool? entrando}) => EntrarState(
        negocio: negocio,
        primeraVez: primeraVez,
        intentos: intentos ?? this.intentos,
        entrando: entrando ?? this.entrando,
      );
}

final entrarViewModelProvider = AsyncNotifierProvider.autoDispose<EntrarViewModel, EntrarState>(EntrarViewModel.new);

class EntrarViewModel extends AsyncNotifier<EntrarState> {
  @override
  Future<EntrarState> build() async {
    // El nombre del negocio y el aviso del PIN son solo para mostrar: si no se
    // pueden leer, se entra igual.
    try {
      return EntrarState(
        negocio: (await ref.read(negocioServiceProvider).negocio()).nombre,
        primeraVez: await ref.read(usuarioServiceProvider).usaPinDeFabrica(),
      );
    } catch (_) {
      return const EntrarState();
    }
  }

  /// Devuelve null si entró, o el mensaje para mostrar.
  Future<String?> entrar(String usuario, String pin) async {
    final s = state.value ?? const EntrarState();
    if (s.entrando) return null;
    state = AsyncData(s.copyWith(entrando: true));
    final sesion = await ref.read(usuarioServiceProvider).iniciarSesion(usuario, pin);
    if (sesion != null) {
      ref.read(sesionProvider.notifier).entrar(sesion);
      return null;
    }
    final intentos = s.intentos + 1;
    if (ref.mounted) state = AsyncData(s.copyWith(intentos: intentos, entrando: false));
    return intentos >= 3 ? 'Usuario o PIN incorrecto. Si olvidó el PIN, pida al dueño que lo cambie.' : 'Usuario o PIN incorrecto.';
  }
}
