import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// El último cliente guardado con el formulario (null al abrirlo).
final clienteFormularioViewModelProvider =
    NotifierProvider.autoDispose<ClienteFormularioViewModel, Cliente?>(ClienteFormularioViewModel.new);

class ClienteFormularioViewModel extends Notifier<Cliente?> {
  @override
  Cliente? build() => null;

  /// Crea o modifica el cliente. El servicio revisa el cumpleaños y que solo el
  /// dueño dé o cambie el límite de crédito.
  Future<Cliente> guardar(DatosCliente datos) async {
    final c = await ref.read(fiadoServiceProvider).guardarCliente(ref.sesion, datos);
    if (ref.mounted) state = c;
    return c;
  }
}
