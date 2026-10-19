import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import 'cliente_formulario.dart';
import 'clientes_view_model.dart';
import 'recurrencia_view.dart';

/// "Clientes y fiado" de la 0.7: la lista con lo que debe cada uno, abonos,
/// estado de cuenta y recurrencia de compra.
class ClientesView extends ConsumerStatefulWidget {
  const ClientesView({super.key});

  @override
  ConsumerState<ClientesView> createState() => _ClientesViewState();
}

class _ClientesViewState extends ConsumerState<ClientesView> {
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  ClientesViewModel get _vm => ref.read(clientesViewModelProvider.notifier);
  Cliente? get _seleccionado => ref.read(clientesViewModelProvider).value?.seleccionada?.cliente;

  static String _fecha(DateTime? f) => f == null ? '' : formatoFecha(f);

  Future<void> _nuevo() async {
    if (await editarCliente(context, ref, const DatosCliente(nombre: '')) != null) await _vm.recargar();
  }

  Future<void> _editar() async {
    final c = _seleccionado;
    if (c == null) return;
    if (await editarCliente(context, ref, DatosCliente.de(c)) != null) await _vm.recargar();
  }

  Future<void> _abonar() async {
    final c = _seleccionado;
    if (c == null) {
      await informar(context, 'Seleccione el cliente.');
      return;
    }
    final debe = await _vm.debe(c);
    if (!mounted) return;
    if (debe <= 0) {
      await informar(context, '${c.nombre} no debe nada.');
      return;
    }
    String? errorImpresion;
    final v = await Formulario('Abono de ${c.nombre}', ancho: 480)
        .monto('monto', 'Monto RD\$', minimo: 1)
        .opciones('forma', 'Forma de pago', const [FormaPago.efectivo, FormaPago.tarjeta, FormaPago.transferencia],
            FormaPago.efectivo, (f) => f.etiqueta)
        .texto('nota', 'Nota')
        .nota('Debe ${formatoRD(debe)}.')
        .mostrar(context, alAceptar: (v) async {
      errorImpresion = await _vm.abonar(c, v.monto('monto'), v.opcion<FormaPago>('forma'), v.txtONulo('nota'));
    });
    if (v != null && errorImpresion != null && mounted) await avisar(context, errorImpresion!);
  }

  Future<void> _estadoCuenta() async {
    final c = _seleccionado;
    if (c == null) return;
    final lineas = await _vm.estadoCuenta(c);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EstadoCuenta(nombre: c.nombre, lineas: lineas),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(clientesViewModelProvider).value;
    final vm = _vm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloPantalla('Clientes y fiado'),
        Row(
          children: [
            Expanded(
              child: Casilla(
                controller: _buscar,
                autofocus: true,
                mensaje: 'Buscar por nombre o teléfono',
                onChanged: vm.buscar,
              ),
            ),
            Marca(
              valor: s?.soloFijos ?? false,
              texto: 'Solo clientes fijos',
              margen: const EdgeInsets.only(left: 12),
              onChanged: s == null ? null : vm.cambiarSoloFijos,
            ),
            Marca(
              valor: s?.soloDeben ?? false,
              texto: 'Solo los que deben',
              margen: const EdgeInsets.only(left: 12),
              onChanged: s == null ? null : vm.cambiarSoloDeben,
            ),
          ],
        ),
        Expanded(
          child: Tabla<FilaCliente>(
            filas: s?.filas ?? const [],
            escogida: s?.escogida,
            alEscoger: vm.escoger,
            alAbrir: (_) => _estadoCuenta(),
            columnas: [
              Columna('Nombre', (f) => f.nombre),
              Columna('Teléfono', (f) => f.cliente.telefono ?? '', ancho: 130),
              Columna('Sector', (f) => f.cliente.sector ?? '', ancho: 120),
              Columna('Última compra', (f) => _fecha(f.ultimaCompra), ancho: 120),
              Columna('Debe', (f) => formatoMonto(f.debe), ancho: 130, derecha: true),
              Columna('Límite', (f) => f.limiteTexto, ancho: 130, derecha: true),
              Columna('Último abono', (f) => _fecha(f.ultimoAbono), ancho: 120),
              Columna('Días sin pagar', (f) => f.diasSinPagar?.toString() ?? '', ancho: 110, derecha: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(s?.resumen ?? '', style: const TextStyle(fontSize: 18, color: Estilo.azul)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            children: [
              Boton('Nuevo cliente', onPressed: _nuevo),
              Boton('Editar', onPressed: _editar),
              Boton('Recibir abono', tipo: TipoBoton.principal, onPressed: _abonar),
              Boton('Estado de cuenta', onPressed: _estadoCuenta),
              Tooltip(
                message: 'Cada cuánto viene cada cliente y quién dejó de venir',
                child: Boton('Recurrencia de compra', onPressed: () => verRecurrencia(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La ventana "Estado de cuenta" de la 0.7: los movimientos del fiado, el
/// último a la vista, y lo que debe.
class _EstadoCuenta extends StatefulWidget {
  const _EstadoCuenta({required this.nombre, required this.lineas});

  final String nombre;
  final List<LineaEstadoCuenta> lineas;

  @override
  State<_EstadoCuenta> createState() => _EstadoCuentaState();
}

class _EstadoCuentaState extends State<_EstadoCuenta> {
  int? _escogida;

  // "#,##0.00;;''": el cero sale vacío.
  static String _oVacio(int centavos) => centavos == 0 ? '' : formatoMonto(centavos);

  @override
  Widget build(BuildContext context) {
    final debe = widget.lineas.isEmpty ? 0 : widget.lineas.last.balance;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        backgroundColor: Estilo.fondo,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        child: SizedBox(
          width: 820,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                        child: Text('Estado de cuenta: ${widget.nombre}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Estilo.azul)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close, color: Estilo.gris),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(
                  height: 460,
                  child: Tabla<LineaEstadoCuenta>(
                    filas: widget.lineas,
                    escogida: _escogida,
                    alEscoger: (i) => setState(() => _escogida = i),
                    irAlFinal: true,
                    columnas: [
                      Columna('Fecha', (l) => formatoFechaHora(l.fecha), ancho: 190),
                      Columna('Concepto', (l) => l.concepto),
                      Columna('Fiado', (l) => _oVacio(l.cargo), ancho: 110),
                      Columna('Abono', (l) => _oVacio(l.abono), ancho: 110),
                      Columna('Balance', (l) => formatoMonto(l.balance), ancho: 120),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Debe: ${formatoRD(debe)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Estilo.azul)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
