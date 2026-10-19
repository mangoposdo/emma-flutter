import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class RecurrenciaState {
  const RecurrenciaState({this.dias = 180, this.soloFijos = true, this.lista = const [], this.escogida});

  /// Los períodos de la lista desplegable.
  static const periodos = [30, 90, 180, 365];

  final int dias;
  final bool soloFijos;
  final List<RecurrenciaCliente> lista;
  final int? escogida;

  int get compraron => lista.where((r) => r.compras > 0).length;
  int get noHanVuelto => lista.where((r) => r.estado == EstadoRecurrencia.atrasado).length;
  int get perdidos => lista.where((r) => r.estado == EstadoRecurrencia.perdido).length;

  /// Centavos.
  int get total => lista.fold(0, (s, r) => s + r.total);

  String get resumen => '$compraron clientes compraron  ·  $noHanVuelto no han vuelto  ·  $perdidos perdidos  ·  '
      'Entre todos: ${formatoRD(total)}';

  static String periodoTexto(int dias) => 'Últimos $dias días';
}

final recurrenciaViewModelProvider =
    AsyncNotifierProvider.autoDispose<RecurrenciaViewModel, RecurrenciaState>(RecurrenciaViewModel.new);

/// Cada cuánto viene cada cliente, cuánto gasta y quién dejó de venir.
class RecurrenciaViewModel extends AsyncNotifier<RecurrenciaState> {
  var _consulta = 0;

  @override
  Future<RecurrenciaState> build() => _cargar(180, true);

  Future<RecurrenciaState> _cargar(int dias, bool soloFijos) async {
    final lista = await ref.read(reporteServiceProvider).recurrencia(dias: dias, soloFijos: soloFijos);
    return RecurrenciaState(dias: dias, soloFijos: soloFijos, lista: lista);
  }

  Future<void> _cambiar(int dias, bool soloFijos) async {
    final s = state.value;
    if (s != null) state = AsyncData(RecurrenciaState(dias: dias, soloFijos: soloFijos, lista: s.lista));
    final n = ++_consulta;
    final listo = await _cargar(dias, soloFijos);
    if (!ref.mounted || n != _consulta) return;
    state = AsyncData(listo);
  }

  Future<void> cambiarPeriodo(int dias) => _cambiar(dias, state.value?.soloFijos ?? true);

  Future<void> cambiarSoloFijos(bool valor) => _cambiar(state.value?.dias ?? 180, valor);

  void escoger(int i) {
    final s = state.value;
    if (s != null) state = AsyncData(RecurrenciaState(dias: s.dias, soloFijos: s.soloFijos, lista: s.lista, escogida: i));
  }
}
