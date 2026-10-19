import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lo escrito en cada casilla del conteo: {denominación en pesos: texto}.
class ConteoState {
  const ConteoState(this.textos, {this.notas = ''});

  final Map<int, String> textos;
  final String notas;

  static List<int> get denominaciones => CajaService.denominaciones;

  /// "Billetes de 2,000", "Monedas de 25".
  static String etiqueta(int d) => '${d >= 50 ? 'Billetes de ' : 'Monedas de '}${formatoMontoEntero(d * 100)}';

  /// Como el int.TryParse de la 0.7 (entero de 32 bits). null si no es un número.
  static int? _numero(String t) {
    final n = int.tryParse(t.trim());
    return n == null || n > 2147483647 || n < -2147483648 ? null : n;
  }

  /// Centavos de esa fila; 0 si está vacía o mal escrita.
  int subtotal(int d) {
    final n = _numero(textos[d] ?? '');
    return n != null && n > 0 ? n * d * 100 : 0;
  }

  /// "4,000.00", o vacío si no hay nada que sumar.
  String subtotalTexto(int d) => subtotal(d) > 0 ? formatoMonto(subtotal(d)) : '';

  /// Centavos.
  int get total => denominaciones.fold(0, (s, d) => s + subtotal(d));

  String get totalTexto => formatoRD(total);

  /// La primera denominación mal escrita, o null si todo está bien.
  int? get malEscrita {
    for (final d in denominaciones) {
      final t = (textos[d] ?? '').trim();
      if (t.isEmpty) continue;
      final n = _numero(t);
      if (n == null || n < 0) return d;
    }
    return null;
  }

  /// {denominación en pesos: cuántos}, sin las casillas vacías.
  Map<int, int> get conteo {
    final r = <int, int>{};
    for (final d in denominaciones) {
      final n = _numero(textos[d] ?? '');
      if (n != null && n >= 0) r[d] = n;
    }
    return r;
  }
}

final conteoViewModelProvider = NotifierProvider.autoDispose<ConteoViewModel, ConteoState>(ConteoViewModel.new);

/// El conteo de billetes y monedas del cuadre. El total se calcula solo.
class ConteoViewModel extends Notifier<ConteoState> {
  @override
  ConteoState build() => ConteoState({for (final d in ConteoState.denominaciones) d: ''});

  void cambiar(int denominacion, String texto) =>
      state = ConteoState({...state.textos, denominacion: texto}, notas: state.notas);

  void cambiarNotas(String texto) => state = ConteoState(state.textos, notas: texto);

  /// null si se puede cerrar; si no, el aviso de la 0.7.
  String? revisar() {
    final d = state.malEscrita;
    return d == null ? null : 'Revise la cantidad de ${formatoMontoEntero(d * 100)}.';
  }

  String get pregunta => 'Se contaron ${state.totalTexto}. ¿Cerrar la caja?';

  /// Lo que se le pasa al cierre.
  ({Map<int, int> conteo, String? notas}) get resultado {
    final n = state.notas.trim();
    return (conteo: state.conteo, notas: n.isEmpty ? null : n);
  }
}
