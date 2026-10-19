import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import 'recurrencia_view_model.dart';

/// Abre el reporte de recurrencia de compra.
Future<void> verRecurrencia(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RecurrenciaView(),
    );

/// La RecurrenciaWindow de la 0.7: amarillo = no ha vuelto, rojo = perdido.
class RecurrenciaView extends ConsumerWidget {
  const RecurrenciaView({super.key});

  static String _fecha(DateTime? f) => f == null ? '' : formatoFecha(f);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recurrenciaViewModelProvider).value;
    final vm = ref.read(recurrenciaViewModelProvider.notifier);
    final lista = s?.lista ?? const <RecurrenciaCliente>[];

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 1180,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Recurrencia de compra de los clientes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Desplegable<int>(
                        valor: s?.dias ?? 180,
                        opciones: RecurrenciaState.periodos,
                        texto: RecurrenciaState.periodoTexto,
                        ancho: 160,
                        margen: EdgeInsets.zero,
                        onChanged: s == null ? null : vm.cambiarPeriodo,
                      ),
                      Marca(
                        valor: s?.soloFijos ?? true,
                        texto: 'Solo clientes fijos',
                        margen: const EdgeInsets.only(left: 16),
                        onChanged: s == null ? null : vm.cambiarSoloFijos,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 460,
                  child: Tabla<RecurrenciaCliente>(
                    margen: EdgeInsets.zero,
                    tamano: 15,
                    filas: lista,
                    escogida: s?.escogida,
                    alEscoger: vm.escoger,
                    colorFila: (r) => switch (r.estado) {
                      EstadoRecurrencia.atrasado => Estilo.amarillo,
                      EstadoRecurrencia.perdido => Estilo.rosado,
                      _ => null,
                    },
                    columnas: [
                      Columna('Cliente', (r) => r.cliente.nombre),
                      Columna('Teléfono', (r) => r.cliente.telefono ?? '', ancho: 120),
                      Columna('Estado', (r) => r.estadoTexto, ancho: 110),
                      Columna('Viene', (r) => r.frecuenciaTexto, ancho: 130),
                      Columna('Sin venir', (r) => r.diasSinVenir == null ? '' : '${r.diasSinVenir} días', ancho: 80, derecha: true),
                      Columna('Última', (r) => _fecha(r.ultima), ancho: 95),
                      Columna('Compras', (r) => '${r.compras}', ancho: 75, derecha: true),
                      Columna('Gastó', (r) => formatoMonto(r.total), ancho: 105, derecha: true),
                      Columna('Promedio', (r) => formatoMonto(r.promedio), ancho: 95, derecha: true),
                      Columna('Lo que más lleva', (r) => r.productoFavorito, ancho: 160),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(s?.resumen ?? '', style: const TextStyle(fontSize: 16, color: Estilo.azul)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    'Amarillo: no ha vuelto (lleva más del doble de lo normal sin venir). Rojo: perdido (más de un mes y '
                    'cuatro veces lo normal). Esos son buenos para una llamada.',
                    style: TextStyle(fontSize: 16, color: Estilo.atenuado),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Boton(
                    'Cerrar',
                    anchoMinimo: 100,
                    margen: const EdgeInsets.only(top: 10),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
