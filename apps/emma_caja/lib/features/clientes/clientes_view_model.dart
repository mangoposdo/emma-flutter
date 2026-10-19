import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/imprenta.dart';
import '../../app/providers.dart';

/// Una fila de la tabla de clientes (FilaCliente de la 0.7).
class FilaCliente {
  const FilaCliente({required this.cliente, this.debe = 0, this.ultimoAbono, this.diasSinPagar, this.ultimaCompra});

  final Cliente cliente;

  /// Centavos.
  final int debe;
  final DateTime? ultimoAbono;
  final int? diasSinPagar;
  final DateTime? ultimaCompra;

  String get nombre => '${cliente.esFijo ? '★ ' : ''}${cliente.nombre}';
  String get limiteTexto => cliente.limiteCredito > 0 ? formatoMonto(cliente.limiteCredito) : 'Sin límite';
}

class ClientesState {
  const ClientesState({
    this.texto = '',
    this.soloFijos = false,
    this.soloDeben = false,
    this.filas = const [],
    this.escogida,
    this.totalEnLaCalle = 0,
    this.cuantosDeben = 0,
  });

  final String texto;
  final bool soloFijos;
  final bool soloDeben;
  final List<FilaCliente> filas;
  final int? escogida;

  /// Centavos, de todos los que deben (sin mirar la búsqueda).
  final int totalEnLaCalle;
  final int cuantosDeben;

  FilaCliente? get seleccionada {
    final i = escogida;
    return i == null || i < 0 || i >= filas.length ? null : filas[i];
  }

  String get resumen => 'Total fiado en la calle: ${formatoRD(totalEnLaCalle)}  ·  $cuantosDeben clientes deben';

  ClientesState copyWith({String? texto, bool? soloFijos, bool? soloDeben}) => ClientesState(
        texto: texto ?? this.texto,
        soloFijos: soloFijos ?? this.soloFijos,
        soloDeben: soloDeben ?? this.soloDeben,
        filas: filas,
        escogida: escogida,
        totalEnLaCalle: totalEnLaCalle,
        cuantosDeben: cuantosDeben,
      );

  ClientesState conEscogida(int? i) => ClientesState(
        texto: texto,
        soloFijos: soloFijos,
        soloDeben: soloDeben,
        filas: filas,
        escogida: i,
        totalEnLaCalle: totalEnLaCalle,
        cuantosDeben: cuantosDeben,
      );
}

final clientesViewModelProvider =
    AsyncNotifierProvider.autoDispose<ClientesViewModel, ClientesState>(ClientesViewModel.new);

class ClientesViewModel extends AsyncNotifier<ClientesState> {
  // Lo que no cambia al buscar: se lee al entrar y después de editar o abonar.
  Map<int, DeudaCliente> _deudas = const {};
  Map<int, DateTime?> _compras = const {};
  var _consulta = 0;

  @override
  Future<ClientesState> build() async {
    await _cargarCuentas();
    return _armar(const ClientesState());
  }

  Future<void> _cargarCuentas() async {
    final fiado = ref.read(fiadoServiceProvider);
    final reportes = ref.read(reporteServiceProvider);
    final deudores = await fiado.deudores();
    final recurrencia = await reportes.recurrencia(dias: 365);
    _deudas = {for (final d in deudores) d.cliente.id: d};
    _compras = {for (final r in recurrencia) r.cliente.id: r.ultima};
  }

  /// La lista con la búsqueda y los filtros de [s], ordenada como la 0.7:
  /// primero el que más debe, después los fijos, después por nombre.
  Future<ClientesState> _armar(ClientesState s) async {
    final fiado = ref.read(fiadoServiceProvider);
    final hoy = ref.read(baseDeDatosProvider).reloj();
    final clientes = await fiado.clientes(texto: s.texto);
    final filas = <(int, FilaCliente)>[];
    for (final c in clientes) {
      if (s.soloFijos && !c.esFijo) continue;
      final d = _deudas[c.id];
      final f = FilaCliente(
        cliente: c,
        debe: d?.debe ?? 0,
        ultimoAbono: d?.ultimoAbono,
        diasSinPagar: d?.diasSinPagar(hoy),
        ultimaCompra: _compras[c.id],
      );
      if (s.soloDeben && f.debe <= 0) continue;
      filas.add((filas.length, f));
    }
    filas.sort((a, b) {
      final (ia, fa) = a;
      final (ib, fb) = b;
      var r = fb.debe.compareTo(fa.debe);
      if (r == 0) r = (fb.cliente.esFijo ? 1 : 0).compareTo(fa.cliente.esFijo ? 1 : 0);
      if (r == 0) r = _claveNombre(fa.cliente.nombre).compareTo(_claveNombre(fb.cliente.nombre));
      return r != 0 ? r : ia.compareTo(ib);
    });
    final lista = [for (final (_, f) in filas) f];
    final antes = s.seleccionada?.cliente.id;
    final escogida = antes == null ? -1 : lista.indexWhere((f) => f.cliente.id == antes);
    return ClientesState(
      texto: s.texto,
      soloFijos: s.soloFijos,
      soloDeben: s.soloDeben,
      filas: lista,
      escogida: escogida < 0 ? null : escogida,
      totalEnLaCalle: _deudas.values.fold(0, (t, d) => t + d.debe),
      cuantosDeben: _deudas.length,
    );
  }

  /// Orden de nombres como en Windows en español: sin mirar mayúsculas ni
  /// tildes, y la ñ después de la n.
  static String _claveNombre(String nombre) {
    const sin = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    final b = StringBuffer();
    for (final ch in nombre.toLowerCase().split('')) {
      b.write(ch == 'ñ' ? 'n~' : sin[ch] ?? ch);
    }
    return b.toString();
  }

  Future<void> _filtrar(ClientesState Function(ClientesState s) cambio) async {
    // Si escriben antes de que termine la primera carga, se espera.
    final s = state.value ?? await future;
    if (!ref.mounted) return;
    final nuevo = cambio(state.value ?? s);
    state = AsyncData(nuevo);
    final n = ++_consulta;
    final listo = await _armar(nuevo);
    if (!ref.mounted || n != _consulta) return;
    state = AsyncData(listo);
  }

  Future<void> buscar(String texto) => _filtrar((s) => s.copyWith(texto: texto));

  Future<void> cambiarSoloFijos(bool valor) => _filtrar((s) => s.copyWith(soloFijos: valor));

  Future<void> cambiarSoloDeben(bool valor) => _filtrar((s) => s.copyWith(soloDeben: valor));

  void escoger(int i) {
    final s = state.value;
    if (s != null) state = AsyncData(s.conEscogida(i));
  }

  /// Vuelve a leer deudas y compras (después de editar o abonar).
  Future<void> recargar() async {
    await _cargarCuentas();
    if (!ref.mounted) return;
    final s = state.value;
    if (s == null) return;
    final n = ++_consulta;
    final listo = await _armar(s);
    if (!ref.mounted || n != _consulta) return;
    state = AsyncData(listo);
  }

  /// Lo que debe ahora, en centavos.
  Future<int> debe(Cliente c) => ref.read(fiadoServiceProvider).balance(c.id);

  /// Recibe el abono e imprime el recibo. Devuelve null, o el error de la
  /// impresora para mostrar (el abono ya quedó guardado).
  Future<String?> abonar(Cliente c, int monto, FormaPago forma, String? nota) async {
    final fiado = ref.read(fiadoServiceProvider);
    final imprenta = ref.read(imprentaProvider);
    final m = await fiado.abonar(ref.sesion, c.id, monto, forma: forma, nota: nota);
    final balance = await fiado.balance(c.id);
    final error = await imprenta.imprimirAbono(cliente: c.nombre, monto: m.monto, balance: balance, fecha: m.fecha);
    if (ref.mounted) {
      refrescarEstado(ref);
      await recargar();
    }
    return error;
  }

  Future<List<LineaEstadoCuenta>> estadoCuenta(Cliente c) => ref.read(fiadoServiceProvider).estadoCuenta(c.id);
}
