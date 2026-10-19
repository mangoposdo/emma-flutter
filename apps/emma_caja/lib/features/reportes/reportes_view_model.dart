import 'dart:convert';
import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// La hora para "Hoy", "Esta semana" y "Este mes". Las pruebas ponen una fija.
final relojReportesProvider = Provider<Reloj>((ref) => ref.watch(baseDeDatosProvider).reloj);

/// "Hoy": desde hoy hasta hoy.
(DateTime, DateTime) rangoHoy(DateTime ahora) => (soloDia(ahora), soloDia(ahora));

/// "Esta semana": desde el lunes hasta hoy.
(DateTime, DateTime) rangoSemana(DateTime ahora) {
  final hoy = soloDia(ahora);
  return (DateTime(hoy.year, hoy.month, hoy.day - (hoy.weekday - DateTime.monday)), hoy);
}

/// "Este mes": desde el día 1 hasta hoy.
(DateTime, DateTime) rangoMes(DateTime ahora) => (DateTime(ahora.year, ahora.month), soloDia(ahora));

/// Por ciento redondeado (la mitad sube), como el P0 de la 0.7. [total] mayor que cero.
int porCiento(int parte, int total) {
  final x = parte.abs() * 200 + total;
  final r = x ~/ (total * 2);
  return parte < 0 ? -r : r;
}

/// Una de las cinco tarjetas de arriba.
class TarjetaReporte {
  const TarjetaReporte(this.titulo, this.valor, this.pie);

  final String titulo;
  final String valor;
  final String pie;
}

class ReportesState {
  const ReportesState({
    required this.desde,
    required this.hasta,
    this.tarjetas = const [],
    this.formasPago = '',
    this.dias = const [],
    this.masVendidos = const [],
  });

  /// Los días escogidos. [hasta] incluye todo el día.
  final DateTime desde;
  final DateTime hasta;
  final List<TarjetaReporte> tarjetas;

  /// "Efectivo: RD$ 1,250.00   Tarjeta: RD$ 300.00", para el tooltip de las tarjetas.
  final String formasPago;
  final List<VentaDiaria> dias;
  final List<ProductoVendido> masVendidos;

  /// El nombre que se sugiere al exportar: ventas_2026-10-01_2026-10-18.csv.
  String get nombreArchivo => 'ventas_${_iso(desde)}_${_iso(hasta)}.csv';

  static String _iso(DateTime f) =>
      '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

  ReportesState copyWith({DateTime? desde, DateTime? hasta}) => ReportesState(
        desde: desde ?? this.desde,
        hasta: hasta ?? this.hasta,
        tarjetas: tarjetas,
        formasPago: formasPago,
        dias: dias,
        masVendidos: masVendidos,
      );
}

final reportesViewModelProvider =
    AsyncNotifierProvider.autoDispose<ReportesViewModel, ReportesState>(ReportesViewModel.new);

/// Reportes de la 0.7: al entrar carga "Hoy".
class ReportesViewModel extends AsyncNotifier<ReportesState> {
  @override
  Future<ReportesState> build() {
    final (desde, hasta) = rangoHoy(_ahora());
    return _cargar(desde, hasta);
  }

  DateTime _ahora() => ref.read(relojReportesProvider)();

  Future<void> hoy() => _rango(rangoHoy(_ahora()));
  Future<void> semana() => _rango(rangoSemana(_ahora()));
  Future<void> mes() => _rango(rangoMes(_ahora()));

  void cambiarDesde(DateTime d) {
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(desde: soloDia(d)));
  }

  void cambiarHasta(DateTime d) {
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(hasta: soloDia(d)));
  }

  Future<void> _rango((DateTime, DateTime) r) async {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(desde: r.$1, hasta: r.$2));
    await ver();
  }

  /// Carga el período escogido.
  Future<void> ver() async {
    final s = state.value;
    if (s == null) return;
    final nuevo = await _cargar(s.desde, s.hasta);
    if (ref.mounted) state = AsyncData(nuevo);
  }

  static DateTime _fin(DateTime hasta) => DateTime(hasta.year, hasta.month, hasta.day + 1);

  Future<ReportesState> _cargar(DateTime desde, DateTime hasta) async {
    final fin = _fin(hasta);
    final reportes = ref.read(reporteServiceProvider);
    final r = await reportes.resumen(desde, fin);
    final inv = await reportes.inventarioValorizado();
    final fiado = await ref.read(fiadoServiceProvider).totalEnLaCalle();
    final dias = await reportes.porDia(desde, fin);
    final top = await reportes.masVendidos(desde, fin, top: 30);
    final formas = r.porFormaPago.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
    return ReportesState(
      desde: desde,
      hasta: hasta,
      tarjetas: [
        TarjetaReporte('Vendido', formatoRD(r.total), '${r.cantidadVentas} ventas'),
        TarjetaReporte('Ganancia', formatoRD(r.ganancia), r.total > 0 ? '${porCiento(r.ganancia, r.total)}% del total' : ''),
        TarjetaReporte('Ticket promedio', formatoRD(r.ticketPromedio), ''),
        TarjetaReporte('Fiado en la calle', formatoRD(fiado), 'hoy'),
        TarjetaReporte('Inventario a costo', formatoRD(inv.costo), 'a precio de venta ${formatoRD(inv.venta)}'),
      ],
      formasPago: formas.map((e) => '${e.key.etiqueta}: ${formatoRD(e.value)}').join('   '),
      dias: dias,
      masVendidos: top,
    );
  }

  /// Escribe las ventas del período (las anuladas también) en [ruta] y
  /// devuelve el mensaje para mostrar.
  Future<String> exportar(String ruta) async {
    final s = state.value;
    if (s == null) throw const EmmaError('Espere a que carguen los reportes.');
    final archivo = ruta.toLowerCase().endsWith('.csv') ? ruta : '$ruta.csv';
    final fin = _fin(s.hasta);
    final csv = await ref.read(reporteServiceProvider).exportarVentasCsv(s.desde, fin);
    final cantidad = (await ref.read(ventaServiceProvider).entre(s.desde, fin)).length;
    try {
      await File(archivo).writeAsString(csv, encoding: utf8, flush: true);
    } on FileSystemException catch (e) {
      throw EmmaError('No se pudo guardar el archivo: ${e.message}');
    }
    return 'Se exportaron $cantidad ventas a $archivo';
  }
}
