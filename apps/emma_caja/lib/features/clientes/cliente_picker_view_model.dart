import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class ClientePickerState {
  const ClientePickerState({this.clientes = const [], this.escogido});

  final List<Cliente> clientes;
  final int? escogido;

  Cliente? get seleccionado {
    final i = escogido;
    return i == null || i < 0 || i >= clientes.length ? null : clientes[i];
  }

  /// "★ Nombre" para los fijos.
  static String titulo(Cliente c) => '${c.esFijo ? '★ ' : ''}${c.nombre}';

  /// "teléfono  ·  dirección  ·  sector", sin los que faltan.
  static String detalle(Cliente c) =>
      [c.telefono, c.direccion, c.sector].where((x) => x != null && x.trim().isNotEmpty).join('  ·  ');
}

/// El argumento es el texto con que se abre la ventana.
final clientePickerViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<ClientePickerViewModel, ClientePickerState, String>(ClientePickerViewModel.new);

class ClientePickerViewModel extends AsyncNotifier<ClientePickerState> {
  ClientePickerViewModel(this.textoInicial);

  final String textoInicial;
  var _consulta = 0;

  @override
  Future<ClientePickerState> build() => _buscar(textoInicial);

  /// Si el texto es el teléfono de un cliente sale solo ese; si no, por nombre
  /// o teléfono (los fijos primero). El primero queda escogido.
  Future<ClientePickerState> _buscar(String texto) async {
    final delivery = ref.read(deliveryServiceProvider);
    final fiado = ref.read(fiadoServiceProvider);
    final t = texto.trim();
    final porTelefono = await delivery.clientePorTelefono(t);
    final lista = porTelefono != null ? [porTelefono] : (await fiado.clientes(texto: t)).take(100).toList();
    return ClientePickerState(clientes: lista, escogido: lista.isEmpty ? null : 0);
  }

  Future<void> buscar(String texto) async {
    final n = ++_consulta;
    final s = await _buscar(texto);
    if (!ref.mounted || n != _consulta) return;
    state = AsyncData(s);
  }

  void escoger(int i) {
    final s = state.value;
    if (s == null || s.clientes.isEmpty) return;
    state = AsyncData(ClientePickerState(clientes: s.clientes, escogido: i.clamp(0, s.clientes.length - 1)));
  }

  /// Los datos para "Nuevo cliente": lo escrito va de nombre, o de teléfono si
  /// tiene 7 números o más. Sale marcado como fijo.
  DatosCliente datosNuevo(String texto) {
    final t = texto.trim();
    if (DeliveryService.soloNumeros(t).length >= 7) return DatosCliente(nombre: '', telefono: t, esFijo: true);
    return DatosCliente(nombre: t, esFijo: true);
  }
}
