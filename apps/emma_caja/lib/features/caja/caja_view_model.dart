import 'dart:async';

import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/cuidados.dart';
import '../../app/imprenta.dart';
import '../../app/providers.dart';

/// Una línea del resumen del turno: "+ Entradas  RD$ 500.00".
class FilaResumen {
  const FilaResumen(this.texto, this.monto, {this.negrita = false});

  final String texto;

  /// Centavos.
  final int monto;
  final bool negrita;
}

class CajaState {
  const CajaState({this.resumen, this.ventas = const [], this.historial = const [], this.ventaEscogida, this.cuadreEscogido});

  /// El turno abierto con su cuadre hasta ahora; null con la caja cerrada.
  final ResumenTurno? resumen;
  final List<VentaListada> ventas;

  /// Solo los turnos ya cerrados, del más nuevo al más viejo.
  final List<TurnoConCajero> historial;
  final int? ventaEscogida;
  final int? cuadreEscogido;

  bool get abierta => resumen != null;

  String get textoTurno {
    final r = resumen;
    if (r == null) return '';
    final a = r.turno.apertura;
    return 'Abierta por ${r.cajero} el ${formatoFecha(a)} a las ${formatoHoraPantalla(a)}';
  }

  List<FilaResumen> get filasResumen {
    final r = resumen;
    if (r == null) return const [];
    return [
      FilaResumen('Ventas (${r.cantidadVentas})', r.totalVentas, negrita: true),
      FilaResumen('   Efectivo', r.ventasEfectivo),
      FilaResumen('   Tarjeta', r.ventasTarjeta),
      FilaResumen('   Transferencia', r.ventasTransferencia),
      FilaResumen('   Fiado', r.ventasFiado),
      FilaResumen('Fondo inicial', r.turno.fondoInicial),
      FilaResumen('+ Abonos en efectivo', r.abonosEfectivo),
      FilaResumen('+ Entradas', r.entradas),
      FilaResumen('- Salidas', r.salidas),
      FilaResumen('Debe haber en la gaveta', r.efectivoEsperado, negrita: true),
    ];
  }

  CajaState escoger({int? venta, int? cuadre}) => CajaState(
        resumen: resumen,
        ventas: ventas,
        historial: historial,
        ventaEscogida: venta ?? ventaEscogida,
        cuadreEscogido: cuadre ?? cuadreEscogido,
      );
}

/// Lo que se muestra al hacer doble clic en una venta del turno.
class VentaParaVer {
  const VentaParaVer({required this.id, required this.mensaje, required this.preguntarAnular});

  final int id;

  /// El detalle de la venta con lo que corresponde al final (anulada, llame
  /// al dueño, o la pregunta de si desea anularla).
  final String mensaje;

  /// Solo el dueño, y si la venta no está anulada.
  final bool preguntarAnular;
}

/// El resultado del cierre: el mensaje final de la 0.7 y, si la impresora
/// falló, su error (se muestra antes).
class CierreCaja {
  const CierreCaja({required this.mensaje, this.errorImpresion});

  final String mensaje;
  final String? errorImpresion;
}

final cajaViewModelProvider = AsyncNotifierProvider.autoDispose<CajaViewModel, CajaState>(CajaViewModel.new);

/// Abrir la caja, entradas y salidas, el cuadre, anular ventas del turno y
/// reimprimir cuadres viejos.
class CajaViewModel extends AsyncNotifier<CajaState> {
  @override
  Future<CajaState> build() => _cargar();

  Future<CajaState> _cargar() async {
    final caja = ref.read(cajaServiceProvider);
    final ventas = ref.read(ventaServiceProvider);
    final turno = await caja.turnoAbierto();
    final historial = (await caja.historial()).where((t) => t.turno.cierre != null).toList();
    if (turno == null) return CajaState(historial: historial);
    return CajaState(
      resumen: await caja.resumen(turno.id),
      ventas: await ventas.delTurno(turno.id),
      historial: historial,
    );
  }

  Future<void> recargar() async {
    final s = await _cargar();
    if (ref.mounted) state = AsyncData(s);
  }

  /// Después de cada cambio: el menú dice "Caja abierta desde..." y lo de la nube.
  Future<void> _cambio() async {
    if (!ref.mounted) return;
    refrescarEstado(ref);
    await recargar();
  }

  void escogerVenta(int i) {
    final s = state.value;
    if (s != null) state = AsyncData(s.escoger(venta: i));
  }

  void escogerCuadre(int i) {
    final s = state.value;
    if (s != null) state = AsyncData(s.escoger(cuadre: i));
  }

  /// Abre la caja con el fondo escrito (puede ser 0).
  Future<void> abrir(String fondo) async {
    final f = parsearMonto(fondo);
    if (f == null) throw const DatoInvalido('Escriba el fondo inicial (puede ser 0).');
    await ref.read(cajaServiceProvider).abrir(ref.sesion, f);
    await _cambio();
  }

  /// Entrada o salida de efectivo. [monto] en centavos.
  Future<void> movimiento(TipoMovCaja tipo, int monto, String concepto) async {
    await ref.read(cajaServiceProvider).registrarMovimiento(ref.sesion, tipo, monto, concepto);
    await _cambio();
  }

  /// La pregunta de la 0.7 si hay delivery sin cobrar en la calle, o null.
  Future<String?> preguntaAntesDeCerrar() async {
    final calle = await ref.read(deliveryServiceProvider).enLaCalle();
    if (calle.isEmpty) return null;
    final total = calle.fold<int>(0, (s, d) => s + d.total);
    return 'Hay ${calle.length} delivery en la calle por ${formatoRD(total)} que todavía no se han cobrado.\n\n'
        'Si cierra ahora, se cobrarán en el próximo turno. ¿Cerrar la caja de todos modos?';
  }

  /// Cierra el turno con el conteo {denominación en pesos: cuántos}, imprime
  /// el cuadre, lo manda a la nube sin esperar y hace el respaldo completo.
  Future<CierreCaja> cerrar(Map<int, int> conteo, String? notas) async {
    final caja = ref.read(cajaServiceProvider);
    final imprenta = ref.read(imprentaProvider);
    final cuidados = ref.read(cuidadosProvider);
    final carpeta = ref.read(carpetaDatosProvider);

    final r = await caja.cerrar(ref.sesion, conteo, notas: notas);
    final dif = r.turno.diferencia ?? 0;
    final errorImpresion = await imprenta.imprimirCierre(r.turno.id);
    unawaited(cuidados.enviarANube()); // el cuadre sale en el portal del dueño enseguida

    String respaldo;
    try {
      respaldo = await cuidados.respaldoCompleto();
    } catch (e, pila) {
      registrarError(carpeta, e, pila);
      respaldo = 'No se pudo hacer el respaldo: $e';
    }
    await _cambio();

    final cuadre = dif == 0
        ? 'La caja cuadra.'
        : dif < 0
            ? 'FALTANTE: ${formatoRD(-dif)}'
            : 'SOBRANTE: ${formatoRD(dif)}';
    return CierreCaja(
      mensaje: 'Caja cerrada.\n\nDebía haber: ${formatoRD(r.efectivoEsperado)}\n'
          'Se contó: ${formatoRD(r.turno.efectivoContado ?? 0)}\n$cuadre\n\n$respaldo',
      errorImpresion: errorImpresion,
    );
  }

  /// El detalle de la venta [indice] del turno.
  Future<VentaParaVer?> verVenta(int indice) async {
    final s = state.value;
    if (s == null || indice < 0 || indice >= s.ventas.length) return null;
    final esDueno = ref.sesion.esDueno;
    final d = await ref.read(ventaServiceProvider).porId(s.ventas[indice].venta.id);
    if (d == null) return null;
    final v = d.venta;
    final detalle = d.lineas.map((l) => '${formatoCantidad(l.cantidad)} x ${l.descripcion}  ${formatoRD(l.total)}').join('\n');
    final texto = 'Venta #${v.id}  ${formatoHora(v.fecha)}  ${v.formaPago.etiqueta}\n\n$detalle\n\nTotal: ${formatoRD(v.total)}';
    if (v.anulada) {
      return VentaParaVer(id: v.id, mensaje: '$texto\n\nANULADA: ${v.motivoAnulacion ?? ''}', preguntarAnular: false);
    }
    if (!esDueno) {
      return VentaParaVer(id: v.id, mensaje: '$texto\n\nPara anular una venta llame al dueño.', preguntarAnular: false);
    }
    return VentaParaVer(
      id: v.id,
      mensaje: '$texto\n\n¿Desea ANULAR esta venta? Los productos vuelven al inventario.',
      preguntarAnular: true,
    );
  }

  /// Solo el dueño (el servicio lo revisa).
  Future<void> anular(int ventaId, String motivo) async {
    await ref.read(ventaServiceProvider).anular(ref.sesion, ventaId, motivo);
    await _cambio();
  }

  /// Reimprime el cuadre [indice] del historial. null si salió; si no, lo que
  /// hay que decir ([esError] falso para "No hay impresora configurada.").
  Future<({String texto, bool esError})?> reimprimir(int indice) async {
    final s = state.value;
    if (s == null || indice < 0 || indice >= s.historial.length) return null;
    final imprenta = ref.read(imprentaProvider);
    if (!await imprenta.hayImpresora()) return (texto: 'No hay impresora configurada.', esError: false);
    final error = await imprenta.imprimirCierre(s.historial[indice].turno.id);
    return error == null ? null : (texto: error, esError: true);
  }
}
