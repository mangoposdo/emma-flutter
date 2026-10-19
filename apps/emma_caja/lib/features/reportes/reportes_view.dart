import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import '../../plataforma/archivos.dart';
import 'reportes_view_model.dart';

/// Reportes de la 0.7: período, cinco tarjetas, ventas por día y los más vendidos.
class ReportesView extends ConsumerStatefulWidget {
  const ReportesView({super.key});

  @override
  ConsumerState<ReportesView> createState() => _ReportesViewState();
}

class _ReportesViewState extends ConsumerState<ReportesView> {
  // La fila escogida de cada tabla; se pierde al cargar otro período.
  (List<VentaDiaria>, int)? _dia;
  (List<ProductoVendido>, int)? _producto;

  ReportesViewModel get _vm => ref.read(reportesViewModelProvider.notifier);

  Future<void> _exportar() async {
    final s = ref.read(reportesViewModelProvider).value;
    if (s == null) return;
    final ruta = await escogerDondeGuardar(nombre: s.nombreArchivo, descripcion: 'Archivo CSV', extensiones: const ['csv']);
    if (ruta == null || !mounted) return;
    try {
      final mensaje = await _vm.exportar(ruta);
      if (mounted) await informar(context, mensaje);
    } on EmmaError catch (e) {
      if (mounted) await avisar(context, e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(reportesViewModelProvider);
    final s = estado.value;
    final listo = s != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloPantalla('Reportes'),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Boton('Hoy', onPressed: listo ? _vm.hoy : null),
            Boton('Esta semana', onPressed: listo ? _vm.semana : null),
            Boton('Este mes', onPressed: listo ? _vm.mes : null),
            const Padding(padding: EdgeInsets.fromLTRB(16, 0, 4, 0), child: Text('Desde', style: _letra)),
            _CampoFecha(valor: s?.desde, alCambiar: _vm.cambiarDesde),
            const Padding(padding: EdgeInsets.fromLTRB(8, 0, 4, 0), child: Text('Hasta', style: _letra)),
            _CampoFecha(valor: s?.hasta, alCambiar: _vm.cambiarHasta),
            Boton('Ver', tipo: TipoBoton.principal, onPressed: listo ? _vm.ver : null),
            Boton('Exportar ventas a Excel', onPressed: listo ? _exportar : null),
          ],
        ),
        if (s == null)
          estado.hasError
              ? TextoGris('No se pudieron cargar los reportes: ${estado.error}')
              : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          _tarjetas(s),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ventasPorDia(s)),
                Expanded(child: _masVendidos(s)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tarjetas(ReportesState s) {
    final fila = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in s.tarjetas)
            Expanded(
              child: Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.titulo, style: const TextStyle(fontSize: 16, color: Estilo.atenuado)),
                    Text(t.valor, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Estilo.azul)),
                    Text(t.pie, style: const TextStyle(fontSize: 13, color: Estilo.atenuado)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return s.formasPago.isEmpty ? fila : Tooltip(message: s.formasPago, child: fila);
  }

  Widget _ventasPorDia(ReportesState s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextoGris('Ventas por día', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
          Expanded(
            child: Tabla<VentaDiaria>(
              filas: s.dias,
              escogida: identical(_dia?.$1, s.dias) ? _dia!.$2 : null,
              alEscoger: (i) => setState(() => _dia = (s.dias, i)),
              columnas: [
                Columna('Día', (d) => formatoDia(d.dia)),
                Columna('Ventas', (d) => '${d.cantidad}', ancho: 80, derecha: true),
                Columna('Total', (d) => formatoMonto(d.total), ancho: 120, derecha: true),
                Columna('Ganancia', (d) => formatoMonto(d.ganancia), ancho: 120, derecha: true),
              ],
            ),
          ),
        ],
      );

  Widget _masVendidos(ReportesState s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextoGris('Productos más vendidos', margen: EdgeInsets.fromLTRB(4, 12, 4, 0)),
          Expanded(
            child: Tabla<ProductoVendido>(
              filas: s.masVendidos,
              escogida: identical(_producto?.$1, s.masVendidos) ? _producto!.$2 : null,
              alEscoger: (i) => setState(() => _producto = (s.masVendidos, i)),
              columnas: [
                Columna('Producto', (p) => p.nombre),
                Columna('Cantidad', (p) => formatoCantidad(p.cantidad), ancho: 90, derecha: true),
                Columna('Total', (p) => formatoMonto(p.total), ancho: 110, derecha: true),
                Columna('Ganancia', (p) => formatoMonto(p.ganancia), ancho: 110, derecha: true),
              ],
            ),
          ),
        ],
      );
}

const _letra = TextStyle(fontSize: 16, color: Estilo.azul);

/// El DatePicker de la 0.7: la fecha y el calendario para escogerla.
class _CampoFecha extends StatelessWidget {
  const _CampoFecha({required this.valor, required this.alCambiar});

  final DateTime? valor;
  final ValueChanged<DateTime> alCambiar;

  Future<void> _escoger(BuildContext context) async {
    final f = await showDatePicker(
      context: context,
      initialDate: valor ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (f != null) alCambiar(f);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 150,
          height: 38,
          child: Material(
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Estilo.borde),
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
            child: InkWell(
              onTap: valor == null ? null : () => _escoger(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(valor == null ? '' : formatoFecha(valor!), style: _letra)),
                    const Icon(Icons.calendar_month_outlined, size: 18, color: Estilo.gris),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
