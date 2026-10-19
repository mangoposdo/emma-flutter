import 'dart:io';

import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../comun/avisos.dart';
import '../../comun/botones.dart';
import '../../comun/estilo.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../plataforma/archivos.dart';
import 'configuracion_view_model.dart';
import 'leer_imagen.dart';
import 'vista_logo.dart';

/// Configuración de la 0.7: datos del negocio, impresora, ticket, repartidores,
/// nube, respaldos y el PIN.
class ConfiguracionView extends ConsumerStatefulWidget {
  const ConfiguracionView({super.key});

  @override
  ConsumerState<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends ConsumerState<ConfiguracionView> {
  final _nombre = TextEditingController();
  final _rnc = TextEditingController();
  final _direccion = TextEditingController();
  final _telefono = TextEditingController();
  final _mensaje = TextEditingController();
  final _envio = TextEditingController();
  final _carpetaExterna = TextEditingController();
  final _codigo = TextEditingController();
  var _lleno = false;

  ConfiguracionViewModel get _vm => ref.read(configuracionViewModelProvider.notifier);

  ConfiguracionState? get _s => ref.read(configuracionViewModelProvider).value;

  @override
  void dispose() {
    for (final c in [_nombre, _rnc, _direccion, _telefono, _mensaje, _envio, _carpetaExterna, _codigo]) {
      c.dispose();
    }
    super.dispose();
  }

  void _llenar(Borrador b) {
    _nombre.text = b.nombre;
    _rnc.text = b.rnc;
    _direccion.text = b.direccion;
    _telefono.text = b.telefono;
    _mensaje.text = b.mensaje;
    _envio.text = b.envio;
    _carpetaExterna.text = b.carpetaExterna;
  }

  /// Corre la acción y muestra lo que devuelva. Si una regla del negocio la
  /// detiene, muestra el aviso.
  Future<void> _hacer(Future<Mensaje?> Function() accion, {VoidCallback? siSale}) async {
    final Mensaje? m;
    try {
      m = await accion();
    } on EmmaError catch (e) {
      if (mounted) await avisar(context, e.mensaje);
      return;
    }
    siSale?.call();
    if (m == null || !mounted) return;
    await avisar(context, m.texto, tipo: switch (m.tono) {
      Tono.info => TipoAviso.info,
      Tono.aviso => TipoAviso.aviso,
      Tono.error => TipoAviso.error,
    });
  }

  Future<Mensaje?> Function() _sinMensaje(Future<void> Function() accion) => () async {
        await accion();
        return null;
      };

  Future<void> _escogerLogo() async {
    final ruta = await escogerArchivo(descripcion: 'Imágenes', extensiones: const ['png', 'jpg', 'jpeg', 'bmp', 'gif']);
    if (ruta == null) return;
    await _hacer(() async {
      final imagen = await leerEnGrises(ruta);
      return _vm.ponerLogo(imagen.grises, imagen.ancho, imagen.alto);
    });
  }

  Future<void> _editarRepartidor(Repartidor? r) => Formulario(r == null ? 'Agregar repartidor' : 'Editar repartidor', ancho: 460)
      .texto('nombre', 'Nombre', valor: r?.nombre, requerido: true)
      .texto('telefono', 'Teléfono', valor: r?.telefono)
      .mostrar(
        context,
        alAceptar: (v) => _vm.guardarRepartidor(id: r?.id, nombre: v.txt('nombre'), telefono: v.txtONulo('telefono')),
      );

  Future<void> _quitarRepartidor() async {
    final r = _s?.repartidor;
    if (r == null) {
      await informar(context, 'Escoja el repartidor.');
      return;
    }
    if (!await confirmar(context, '¿Quitar a ${r.nombre} de la lista? Sus entregas anteriores se quedan en los reportes.')) return;
    await _hacer(_sinMensaje(() => _vm.quitarRepartidor(r)));
  }

  Future<void> _desconectar() async {
    if (!await confirmar(
        context, '¿Desconectar esta caja de la nube? Las ventas dejarán de salir en la web hasta que la vuelva a conectar.')) {
      return;
    }
    await _hacer(_sinMensaje(_vm.desconectar));
  }

  Future<void> _escogerCarpetaExterna() async {
    final carpeta = await escogerCarpeta();
    if (carpeta == null) return;
    _carpetaExterna.text = carpeta;
    _vm.cambiar((b) => b.copyWith(carpetaExterna: carpeta));
  }

  Future<void> _restaurar() async {
    final s = _s;
    if (s == null) return;
    final ruta = await escogerArchivo(descripcion: 'Respaldo de Emma', extensiones: const ['db'], carpeta: s.carpetaRespaldos);
    if (ruta == null || !mounted) return;
    if (!await confirmar(
        context,
        'Se reemplazarán TODOS los datos actuales por los del respaldo:\n\n${p.basename(ruta)}'
        '\n\nAntes se guarda una copia de los datos actuales. El programa se cerrará. ¿Continuar?')) {
      return;
    }
    final String copia;
    try {
      copia = await _vm.restaurar(ruta);
    } on EmmaError catch (e) {
      if (mounted) await avisar(context, e.mensaje);
      return;
    }
    if (mounted) await informar(context, 'Respaldo restaurado. Los datos anteriores quedaron en:\n$copia\n\nAbra el programa de nuevo.');
    exit(0);
  }

  Future<void> _cambiarPin() async {
    final v = await Formulario('Cambiar mi PIN', ancho: 440)
        .clave('actual', 'PIN actual')
        .clave('nuevo', 'PIN nuevo')
        .clave('repetir', 'Repetir PIN nuevo')
        .mostrar(context, alAceptar: (v) => _vm.cambiarPin(v.txt('actual'), v.txt('nuevo'), v.txt('repetir')));
    if (v != null && mounted) await informar(context, 'PIN cambiado.');
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(configuracionViewModelProvider);
    final s = estado.value;
    if (s == null) {
      return estado.hasError
          ? TextoGris('No se pudo cargar la configuración: ${estado.error}')
          : const Center(child: CircularProgressIndicator());
    }
    if (!_lleno) {
      _llenar(s.borrador);
      _lleno = true;
    }
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TituloPantalla('Configuración'),
              _datosNegocio(),
              _impresora(s),
              _ticket(s),
              _repartidores(s),
              _nube(s),
              _respaldos(s),
              Tarjeta(
                child: Wrap(
                  children: [
                    Boton('Guardar configuración', tipo: TipoBoton.principal, onPressed: () => _hacer(_vm.guardar)),
                    Boton('Cambiar mi PIN', onPressed: _cambiarPin),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(s.textoVersion, style: const TextStyle(fontSize: 16, color: Estilo.atenuado)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController c, Borrador Function(Borrador b, String t) cambio) => FilaCampo(
        etiqueta: etiqueta,
        anchoEtiqueta: 200,
        child: Casilla(controller: c, onChanged: (t) => _vm.cambiar((b) => cambio(b, t))),
      );

  Widget _datosNegocio() => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Datos del negocio (salen en el ticket)'),
            _campo('Nombre', _nombre, (b, t) => b.copyWith(nombre: t)),
            _campo('RNC', _rnc, (b, t) => b.copyWith(rnc: t)),
            _campo('Dirección', _direccion, (b, t) => b.copyWith(direccion: t)),
            _campo('Teléfono', _telefono, (b, t) => b.copyWith(telefono: t)),
            _campo('Mensaje al final', _mensaje, (b, t) => b.copyWith(mensaje: t)),
            FilaCampo(
              etiqueta: r'Envío de delivery RD$',
              anchoEtiqueta: 200,
              child: Row(
                children: [
                  Casilla(
                    controller: _envio,
                    ancho: 120,
                    derecha: true,
                    onChanged: (t) => _vm.cambiar((b) => b.copyWith(envio: t)),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Lo que se cobra por llevar el pedido (se puede cambiar en cada delivery). 0 = gratis.',
                        style: _gris,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _impresora(ConfiguracionState s) => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Impresora de tickets'),
            Row(
              children: [
                Expanded(
                  child: Desplegable<String>(
                    valor: s.impresoraEscogida,
                    opciones: s.opcionesImpresora,
                    texto: (x) => x,
                    onChanged: _vm.escogerImpresora,
                  ),
                ),
                Boton('Imprimir prueba', onPressed: () => _hacer(_vm.imprimirPrueba)),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Padding(padding: EdgeInsets.all(4), child: Text('Papel', style: _letra)),
                Desplegable<int>(
                  ancho: 240,
                  valor: s.borrador.anchoTicket,
                  opciones: const [48, 32],
                  texto: textoPapel,
                  onChanged: (v) => _vm.cambiar((b) => b.copyWith(anchoTicket: v)),
                ),
                Marca(
                  valor: s.borrador.abrirGaveta,
                  texto: 'Abrir la gaveta al cobrar en efectivo',
                  margen: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onChanged: (v) => _vm.cambiar((b) => b.copyWith(abrirGaveta: v)),
                ),
              ],
            ),
            const TextoGris(
              'Instale la impresora en Windows con el driver del fabricante (o como Generic / Text Only) y escójala aquí. '
              'Deje vacío para no imprimir.',
            ),
          ],
        ),
      );

  Widget _ticket(ConfiguracionState s) => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Cómo sale el ticket'),
            Align(
              alignment: Alignment.centerLeft,
              child: Marca(
                valor: s.borrador.ticketOscuro,
                texto: 'Letra más oscura (resaltada en todo el ticket)',
                onChanged: (v) => _vm.cambiar((b) => b.copyWith(ticketOscuro: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  const Padding(padding: EdgeInsets.only(right: 8), child: Text('Intensidad de impresión', style: _letra)),
                  Desplegable<IntensidadTicket>(
                    ancho: 240,
                    valor: s.borrador.intensidad,
                    opciones: IntensidadTicket.values,
                    texto: textoIntensidad,
                    onChanged: (v) => _vm.cambiar((b) => b.copyWith(intensidad: v)),
                  ),
                ],
              ),
            ),
            const TextoGris(
              'Si sale clarito, suba la intensidad y toque Imprimir prueba. Si salen letras o símbolos raros arriba del '
              'ticket, su impresora no entiende ese ajuste: déjela en Normal. Papel térmico de buena calidad también ayuda.',
              margen: EdgeInsets.fromLTRB(4, 0, 4, 8),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VistaLogo(puntos: s.negocio.logoTicket, ancho: s.negocio.logoAncho),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.all(4), child: Text('Logo del colmado arriba del ticket', style: _letra)),
                        Wrap(
                          children: [
                            Boton('Escoger logo...', onPressed: _escogerLogo),
                            Boton('Quitar logo', onPressed: s.hayLogo ? () => _hacer(_sinMensaje(_vm.quitarLogo)) : null),
                          ],
                        ),
                        const TextoGris(
                          'Una imagen PNG o JPG. Sale en blanco y negro, así como se ve en el cuadro. '
                          'Mejor si el logo es oscuro con fondo blanco o transparente.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _repartidores(ConfiguracionState s) => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Repartidores de delivery'),
            const TextoGris(
              'Los que lleven los pedidos. Salen en la lista al despachar un delivery (F9 en Ventas), '
              'y el cuadre dice cuánto cobró cada uno.',
              margen: EdgeInsets.fromLTRB(4, 0, 4, 8),
            ),
            _ListaRepartidores(
              repartidores: s.repartidores,
              escogido: s.repartidorEscogido,
              alEscoger: _vm.escogerRepartidor,
              alAbrir: (i) => _editarRepartidor(s.repartidores[i]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                children: [
                  Boton('Agregar repartidor', tipo: TipoBoton.principal, onPressed: () => _editarRepartidor(null)),
                  Boton('Editar', onPressed: () {
                    final r = _s?.repartidor;
                    if (r != null) _editarRepartidor(r);
                  }),
                  Boton('Quitar', onPressed: _quitarRepartidor),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _nube(ConfiguracionState s) => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Conectar a la nube (ver las ventas desde el celular)'),
            if (!s.conectada) ...[
              const TextoGris(
                'Escriba el código de activación de su colmado. Lo encuentra en la web de Emma, en Mi colmado (ej. EMMA-7K4P-9QX2).',
                margen: EdgeInsets.fromLTRB(4, 0, 4, 8),
              ),
              Row(
                children: [
                  Expanded(child: Casilla(controller: _codigo, mayusculas: true, tamano: 18)),
                  Boton(
                    'Conectar',
                    tipo: TipoBoton.principal,
                    onPressed: s.conectando ? null : () => _hacer(() => _vm.conectar(_codigo.text), siSale: _codigo.clear),
                  ),
                ],
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(s.textoNube, style: const TextStyle(fontSize: 15, color: Estilo.azul)),
              ),
              TextoGris(s.detalleNube, margen: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
              Wrap(
                children: [
                  Boton('Enviar ahora', onPressed: s.enviando ? null : () => _hacer(_vm.enviarAhora)),
                  Boton('Desconectar', onPressed: _desconectar),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _respaldos(ConfiguracionState s) => Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Encabezado('Respaldos'),
            TextoGris(s.textoRespaldos),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(r'Copia extra en USB o carpeta (ej. E:\RespaldosColmado). Se hace al cerrar caja.', style: _letra),
            ),
            Row(
              children: [
                Expanded(
                  child: Casilla(
                    controller: _carpetaExterna,
                    onChanged: (t) => _vm.cambiar((b) => b.copyWith(carpetaExterna: t)),
                  ),
                ),
                Boton('Escoger carpeta...', onPressed: _escogerCarpetaExterna),
              ],
            ),
            Wrap(
              children: [
                Boton('Respaldar ahora', onPressed: () => _hacer(_vm.respaldarAhora)),
                Boton('Restaurar un respaldo...', onPressed: _restaurar),
                Boton('Abrir carpeta de respaldos', onPressed: () => abrirCarpeta(s.carpetaRespaldos)),
              ],
            ),
          ],
        ),
      );
}

const _letra = TextStyle(fontSize: 16, color: Estilo.azul);
const _gris = TextStyle(fontSize: 16, color: Estilo.atenuado);

/// El título en negrita de cada tarjeta.
class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Estilo.azul)),
      );
}

/// La lista de repartidores de la 0.7 (ListBox de 140 de alto).
class _ListaRepartidores extends StatelessWidget {
  const _ListaRepartidores({required this.repartidores, required this.escogido, required this.alEscoger, required this.alAbrir});

  final List<Repartidor> repartidores;
  final int? escogido;
  final ValueChanged<int> alEscoger;
  final ValueChanged<int> alAbrir;

  @override
  Widget build(BuildContext context) => Container(
        height: 140,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Estilo.borde)),
        child: ListView.builder(
          itemCount: repartidores.length,
          itemBuilder: (context, i) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => alEscoger(i),
            onDoubleTap: () {
              alEscoger(i);
              alAbrir(i);
            },
            child: Container(
              color: i == escogido ? Estilo.seleccionTabla : null,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(textoRepartidor(repartidores[i]), style: const TextStyle(fontSize: 15, color: Colors.black87)),
            ),
          ),
        ),
      );
}
