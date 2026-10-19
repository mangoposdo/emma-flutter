import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/imprenta.dart';
import '../../app/providers.dart';
import 'ventas_state.dart';

final ventasViewModelProvider = AsyncNotifierProvider.autoDispose<VentasViewModel, VentasState>(VentasViewModel.new);

/// La venta del mostrador (igual que la 0.7): pedidos abiertos que se guardan
/// solos, escanear, cobrar en el panel de la derecha y delivery.
class VentasViewModel extends AsyncNotifier<VentasState> {
  /// Aviso al cargar el pedido (productos que ya no existen); la vista lo muestra una vez.
  String? avisoAlCargar;

  ProductoService get _productos => ref.read(productoServiceProvider);
  TicketService get _tickets => ref.read(ticketServiceProvider);

  VentasState get _s => state.requireValue;
  void _poner(VentasState s) {
    if (ref.mounted) state = AsyncData(s);
  }

  @override
  Future<VentasState> build() async {
    // Si hay pedidos abiertos (de antes, o de antes de un apagón) se sigue con el último que se tocó.
    final abiertos = await _tickets.abiertos();
    abiertos.sort((a, b) => a.actualizado.compareTo(b.actualizado));
    final (s, aviso) = await _estadoDe(abiertos.isEmpty ? null : abiertos.last, const VentasState());
    avisoAlCargar = aviso;
    return _conPedidos(s.copyWith(
      enLaCalle: (await ref.read(deliveryServiceProvider).enLaCalle()).length,
      ticketsPendientes: (await ref.read(ventaServiceProvider).ventasConTicketPendiente()).length,
    ));
  }

  /// true si la caja está cerrada (la vista avisa al entrar).
  Future<bool> cajaCerrada() async => await ref.read(cajaServiceProvider).turnoAbierto() == null;

  // ---------- Pedidos abiertos ----------

  /// Pone en pantalla un pedido guardado, o una venta nueva vacía si es null.
  Future<(VentasState, String?)> _estadoDe(TicketAbierto? t, VentasState base) async {
    _sugerencia++;
    var s = base.copyWith(
      lineas: const [],
      seleccionada: null,
      ticketId: t?.id,
      clienteTexto: t?.nombreCliente ?? '',
      clienteId: t?.clienteId,
      clienteNombre: t?.clienteId != null ? t!.nombreCliente : null,
      esDelivery: t?.esDelivery ?? false,
      envio: (t?.esDelivery ?? false) ? t!.cargoEnvio : 0,
      descuento: 0,
      forma: FormaPago.efectivo,
      // Un delivery trae lo que dijo el cliente que paga.
      recibidoTexto: t?.pagaCon != null && t!.pagaCon! > 0 ? _textoMonto(t.pagaCon!) : '',
      pendiente: null,
      busqueda: const [],
      marcado: -1,
      fiadoNombre: null,
      fiadoCredito: '',
    );
    String? aviso;
    if (t != null) {
      final ls = TicketService.lineas(t);
      final productos = await _productos.porIds(ls.map((l) => l.productoId));
      var faltan = 0;
      final lineas = <LineaCarrito>[];
      for (final l in ls) {
        final p = productos[l.productoId];
        if (p != null && p.activo) {
          lineas.add(LineaCarrito(producto: p, cantidad: l.cantidad, precioLibre: l.precio, monto: l.monto));
        } else {
          faltan++;
        }
      }
      s = s.copyWith(lineas: lineas);
      if (faltan > 0) {
        aviso =
            '$faltan producto(s) de ${TicketService.titulo(t)} ya no existen o están desactivados y se quitaron del pedido.';
        await _tickets.guardar(ref.sesion,
            id: t.id,
            nombreCliente: t.nombreCliente,
            lineas: [for (final l in lineas) l.comoPedido],
            clienteId: t.clienteId);
      }
    }
    if (s.lineas.isNotEmpty) s = s.copyWith(devueltaAnterior: null);
    return (s, aviso);
  }

  /// Un botón por pedido abierto con su total; mientras el nuevo no se guarda, también sale.
  Future<VentasState> _conPedidos(VentasState s) async {
    final abiertos = await _tickets.abiertos();
    final pestanas = <PestanaPedido>[
      for (final t in abiertos)
        PestanaPedido(
          id: t.id,
          titulo: TicketService.titulo(t),
          detalle: 'RD\$${formatoMontoEntero(await _tickets.total(t))}',
          actual: t.id == s.ticketId,
        ),
      if (s.ticketId == null)
        PestanaPedido(titulo: s.clienteTexto.trim().isEmpty ? 'Mostrador' : s.clienteTexto.trim(), actual: true),
    ];
    return s.copyWith(pedidos: pestanas);
  }

  /// Guarda el pedido después de cada cambio, para que nada se pierda.
  Future<void> _guardar(VentasState s) async {
    if (s.ticketId == null && s.lineas.isEmpty && s.clienteTexto.trim().isEmpty) {
      _poner(await _conPedidos(s));
      return;
    }
    final t = await _tickets.guardar(
      ref.sesion,
      id: s.ticketId,
      nombreCliente: s.clienteTexto,
      lineas: [for (final l in s.lineas) l.comoPedido],
      clienteId: s.clienteId,
    );
    _poner(await _conPedidos(s.copyWith(ticketId: t.id)));
  }

  /// Deja el pedido actual guardado y abre otro vacío (F6).
  Future<void> nuevoPedido() async {
    final s = _s;
    if (s.ticketId == null && s.lineas.isEmpty) {
      _poner(await _conPedidos(s.copyWith(clienteTexto: '', clienteId: null, clienteNombre: null, pendiente: null)));
      return;
    }
    await _guardar(s.copyWith(pendiente: null));
    final (nuevo, _) = await _estadoDe(null, _s);
    _poner(await _conPedidos(nuevo));
  }

  Future<String?> cambiarAPedido(int id) async {
    if (id == _s.ticketId) return null;
    await _guardar(_s.copyWith(pendiente: null));
    final t = await _tickets.porId(id);
    final (s, aviso) = await _estadoDe(t, _s);
    _poner(await _conPedidos(s));
    return aviso;
  }

  /// Esc: cancela el pedido y vacía la lista (la vista confirma si hay productos).
  Future<void> cancelarPedido() async {
    final id = _s.ticketId;
    if (id != null) await _tickets.borrar(id);
    final (s, _) = await _estadoDe(null, _s.copyWith(ticketId: null));
    _poner(await _conPedidos(s));
  }

  /// Vuelve a leer el pedido actual (después del delivery o "En la calle").
  Future<void> recargar({bool pedidoNuevo = false}) async {
    final id = pedidoNuevo ? null : _s.ticketId;
    final t = id == null ? null : await _tickets.porId(id);
    final (s, _) = await _estadoDe(t, _s.copyWith(ticketId: null));
    _poner(await _conPedidos(s.copyWith(enLaCalle: (await ref.read(deliveryServiceProvider).enLaCalle()).length)));
  }

  /// Guarda el pedido actual si tiene algo (antes de "En la calle").
  Future<void> guardarActual() => _guardar(_s.copyWith(pendiente: null));

  /// Guarda el pedido para poder ponerle el delivery (puede tomarse antes de los productos).
  Future<int> pedidoParaDelivery() async {
    final s = _s.copyWith(pendiente: null);
    final t = await _tickets.guardar(
      ref.sesion,
      id: s.ticketId,
      nombreCliente: s.clienteTexto,
      lineas: [for (final l in s.lineas) l.comoPedido],
      clienteId: s.clienteId,
    );
    _poner(await _conPedidos(s.copyWith(ticketId: t.id)));
    return t.id;
  }

  // ---------- Escanear ----------

  /// Lo que se espera después de la última letra antes de buscar: el lector de
  /// código de barras escribe de corrido y termina con Enter, sin lista.
  static const esperaDelLector = Duration(milliseconds: 120);

  /// Cada búsqueda nueva (o Enter, o escoger) deja sin efecto la anterior.
  var _sugerencia = 0;

  /// Lo que se va escribiendo en la casilla del código: desde la primera letra
  /// sale la lista de productos, sin ninguno marcado (Enter sigue buscando por
  /// código primero). "3*arr" busca "arr"; "$50" es venta suelta y no busca.
  Future<void> sugerir(String texto) async {
    final n = ++_sugerencia;
    var t = texto.trim();
    final asterisco = t.indexOf('*');
    if (asterisco > 0) t = t.substring(asterisco + 1).trim();
    if (t.isEmpty || t.startsWith(r'$') || t.startsWith('+')) {
      if (_s.busqueda.isNotEmpty) _poner(_s.copyWith(busqueda: const [], marcado: -1));
      return;
    }
    if (_s.marcado >= 0) _poner(_s.copyWith(marcado: -1));
    await Future<void>.delayed(esperaDelLector);
    if (n != _sugerencia || !ref.mounted) return;
    final encontrados = await _productos.buscar(t, limite: 50);
    if (n != _sugerencia || !ref.mounted) return;
    _poner(_s.copyWith(busqueda: encontrados, marcado: -1));
  }

  /// Enter en la casilla del código.
  Future<ResultadoCodigo> entrarCodigo(String texto) async {
    _sugerencia++;
    var t = texto.trim();
    if (t.isEmpty) {
      if (_s.lineas.isEmpty) return const Listo();
      return const IrACobrar();
    }

    // "$50" o "+50" = venta suelta de 50 pesos, sin producto.
    if (t.startsWith(r'$') || t.startsWith('+')) {
      final monto = parsearMonto(t.substring(1));
      if (monto != null) return _resultado(await agregarSuelto(monto));
    }

    // "3*7501234" = tres unidades de ese código.
    int? cantidad;
    final asterisco = t.indexOf('*');
    if (asterisco > 0) {
      final n = parsearCantidad(t.substring(0, asterisco));
      if (n != null && n > 0) {
        cantidad = n;
        t = t.substring(asterisco + 1).trim();
      }
    }

    final p = await _productos.porCodigo(t);
    if (p != null) return elegir(p, cantidad: cantidad);

    final encontrados = await _productos.buscar(t, limite: 500);
    if (encontrados.length == 1) return elegir(encontrados.single, cantidad: cantidad);
    if (encontrados.isEmpty) {
      final esCodigo = _pareceCodigoDeBarras(t);
      if (esCodigo && ref.sesion.esDueno) {
        return NoEncontrado('El código $t no está registrado.\n\n¿Crear el producto ahora?',
            codigo: t, ofrecerCrear: true, cantidad: cantidad);
      }
      return NoEncontrado(esCodigo
          ? 'El código $t no está registrado. Pídale al dueño que lo cree en Productos.'
          : 'No se encontró "$t".');
    }
    _poner(_s.copyWith(busqueda: encontrados, marcado: 0));
    return const EscogerDeLista();
  }

  static bool _pareceCodigoDeBarras(String t) => t.length >= 6 && RegExp(r'^\d+$').hasMatch(t);

  static ResultadoCodigo _resultado(String? aviso) => aviso == null ? const Listo() : Aviso(aviso);

  /// Escanear agrega 1 al instante (o lo de "3*"); lo que va por libra pide las libras o el monto.
  Future<ResultadoCodigo> elegir(Producto p, {int? cantidad}) async {
    _sugerencia++;
    _poner(_s.copyWith(busqueda: const [], marcado: -1));
    if (cantidad != null || p.unidad == UnidadVenta.unidad) {
      return _resultado(await agregar(p, cantidad ?? milesimasPorUnidad));
    }
    _poner(_s.copyWith(pendiente: p));
    return const PedirLibras();
  }

  /// Flechas en la lista; sin ninguno marcado, la flecha marca el primero.
  void moverMarca(int paso) {
    final s = _s;
    if (s.busqueda.isEmpty) return;
    final i = s.marcado < 0 ? 0 : s.marcado + paso;
    _poner(s.copyWith(marcado: i.clamp(0, s.busqueda.length - 1)));
  }

  void cerrarBusqueda() {
    _sugerencia++;
    _poner(_s.copyWith(busqueda: const [], marcado: -1));
  }

  void limpiarPendiente() => _poner(_s.copyWith(pendiente: null));

  /// Enter en la casilla de la cantidad (libras o "$50" de un producto por libra).
  Future<String?> entrarCantidad(String texto) async {
    final p = _s.pendiente;
    if (p == null) return null;
    final leida = leerCantidad(p, texto);
    if (leida.error != null) return leida.error;
    _poner(_s.copyWith(pendiente: null));
    return leida.monto != null ? agregarPorMonto(p, leida.monto!) : agregar(p, leida.cantidad!);
  }

  /// Lee lo que se escribió en la cantidad. En libra acepta "$50" (50 pesos de ese producto).
  static ({int? cantidad, int? monto, String? error}) leerCantidad(Producto p, String texto) {
    final t = texto.trim();
    final porMonto = t.startsWith(r'$') || t.toUpperCase().startsWith('RD');
    if (porMonto && p.unidad == UnidadVenta.libra) {
      final m = parsearMonto(t);
      if (m == null || m <= 0) return (cantidad: null, monto: null, error: 'Escriba una cantidad mayor que cero.');
      if (p.precio <= 0) return (cantidad: null, monto: null, error: 'El producto no tiene precio.');
      if (cantidadPorMonto(m, p.precio) <= 0) {
        return (cantidad: null, monto: null, error: 'Ese monto no alcanza para pesar.');
      }
      return (cantidad: null, monto: m, error: null);
    }
    final c = parsearCantidad(t);
    if (c == null || c <= 0) return (cantidad: null, monto: null, error: 'Escriba una cantidad mayor que cero.');
    if (p.unidad == UnidadVenta.unidad && c % milesimasPorUnidad != 0) {
      return (cantidad: null, monto: null, error: '${p.nombre} se vende por unidad; escriba un número entero.');
    }
    return (cantidad: c, monto: null, error: null);
  }

  Future<String?> agregar(Producto p, int cantidad) async {
    if (p.unidad == UnidadVenta.unidad && cantidad % milesimasPorUnidad != 0) return '${p.nombre} se vende por unidad.';
    final s = _s;
    final lineas = [...s.lineas];
    final i = p.unidad == UnidadVenta.unidad
        ? lineas.indexWhere((l) => l.producto.id == p.id && l.precioLibre == null && l.monto == null)
        : -1;
    if (i >= 0) {
      lineas[i] = lineas[i].conCantidad(lineas[i].cantidad + cantidad);
    } else {
      lineas.add(LineaCarrito(producto: p, cantidad: cantidad));
    }
    await _cambiar(s.copyWith(lineas: lineas, seleccionada: i >= 0 ? i : lineas.length - 1));
    return null;
  }

  Future<String?> agregarPorMonto(Producto p, int monto) async {
    final s = _s;
    final lineas = [...s.lineas, LineaCarrito(producto: p, cantidad: cantidadPorMonto(monto, p.precio), monto: monto)];
    await _cambiar(s.copyWith(lineas: lineas, seleccionada: lineas.length - 1));
    return null;
  }

  /// Venta suelta: un monto cobrado sin escoger producto (sale como "Varios").
  Future<String?> agregarSuelto(int monto) async {
    if (monto <= 0) return 'Escriba un monto mayor que cero.';
    final varios = await ref.read(baseDeDatosProvider).productoVarios();
    final s = _s;
    final lineas = [...s.lineas, LineaCarrito(producto: varios, cantidad: milesimasPorUnidad, precioLibre: monto)];
    await _cambiar(s.copyWith(lineas: lineas, seleccionada: lineas.length - 1));
    return null;
  }

  /// Después de cambiar la lista: el descuento no puede pasar el total, se
  /// borra la devuelta de la venta anterior y se guarda el pedido.
  Future<void> _cambiar(VentasState s) async {
    var n = s;
    if (n.descuento > n.subtotal) n = n.copyWith(descuento: 0);
    if (n.lineas.isNotEmpty) n = n.copyWith(devueltaAnterior: null);
    _poner(n);
    await _guardar(n);
    if (n.forma == FormaPago.fiado) await _pintarFiado();
  }

  void seleccionar(int i) => _poner(_s.copyWith(seleccionada: i));

  /// La línea para F4: la escogida o la última.
  int? lineaParaCantidad() {
    final s = _s;
    if (s.lineas.isEmpty) return null;
    return s.seleccionada ?? s.lineas.length - 1;
  }

  /// Botones − y + de una línea que va de uno en uno; en cero se quita.
  Future<void> paso(int i, int paso) async {
    final s = _s;
    final l = s.lineas[i];
    final lineas = [...s.lineas];
    final nueva = l.cantidad + paso * milesimasPorUnidad;
    if (nueva <= 0) {
      lineas.removeAt(i);
      await _cambiar(s.copyWith(lineas: lineas, seleccionada: lineas.isEmpty ? null : i.clamp(0, lineas.length - 1)));
    } else {
      lineas[i] = l.conCantidad(nueva);
      await _cambiar(s.copyWith(lineas: lineas, seleccionada: i));
    }
  }

  /// Cambia la cantidad de una línea (F4). Por libra acepta "$50".
  Future<String?> cambiarCantidad(int i, String texto) async {
    final s = _s;
    final l = s.lineas[i];
    if (l.precioLibre != null) {
      final m = parsearMonto(texto);
      if (m == null || m <= 0) return 'Escriba un monto mayor que cero.';
      final lineas = [...s.lineas]..[i] = LineaCarrito(producto: l.producto, cantidad: l.cantidad, precioLibre: m);
      await _cambiar(s.copyWith(lineas: lineas, seleccionada: i));
      return null;
    }
    final leida = leerCantidad(l.producto, texto);
    if (leida.error != null) return leida.error;
    final lineas = [...s.lineas]..[i] = leida.monto != null
        ? LineaCarrito(
            producto: l.producto, cantidad: cantidadPorMonto(leida.monto!, l.producto.precio), monto: leida.monto)
        : LineaCarrito(producto: l.producto, cantidad: leida.cantidad!);
    await _cambiar(s.copyWith(lineas: lineas, seleccionada: i));
    return null;
  }

  /// Quita la línea [i], o la escogida, o la última (Supr).
  Future<void> quitar([int? i]) async {
    final s = _s;
    if (s.lineas.isEmpty) return;
    final cual = i ?? s.seleccionada ?? s.lineas.length - 1;
    final lineas = [...s.lineas]..removeAt(cual);
    await _cambiar(s.copyWith(lineas: lineas, seleccionada: lineas.isEmpty ? null : cual.clamp(0, lineas.length - 1)));
  }

  // ---------- Cliente ----------

  void escribirCliente(String texto) => _poner(_s.copyWith(clienteTexto: texto));

  /// Enter en la casilla del cliente: si el nombre o teléfono es de un cliente
  /// de la lista, se liga. Devuelve los parecidos si hay que escoger entre varios.
  Future<List<Cliente>> entrarCliente() async {
    final texto = _s.clienteTexto.trim();
    if (texto.isEmpty || texto == _s.clienteNombre) return const [];
    final porTelefono = await ref.read(deliveryServiceProvider).clientePorTelefono(texto);
    final parecidos = porTelefono != null ? [porTelefono] : await ref.read(fiadoServiceProvider).clientes(texto: texto);
    final exacto =
        parecidos.where((c) => c == porTelefono || c.nombre.toLowerCase() == texto.toLowerCase()).firstOrNull;
    if (exacto != null || parecidos.length == 1) {
      await ligarCliente(exacto ?? parecidos.single);
      return const [];
    }
    return parecidos;
  }

  /// Al salir de la casilla del cliente: si cambió el texto se suelta el
  /// cliente ligado, y se guarda el pedido.
  Future<void> clienteSalio() async {
    var s = _s;
    final texto = s.clienteTexto.trim();
    if (s.clienteId != null && texto != s.clienteNombre) s = s.copyWith(clienteId: null, clienteNombre: null);
    final guardado = s.ticketId == null ? null : await _tickets.porId(s.ticketId!);
    if ((guardado?.nombreCliente ?? '') != texto || guardado?.clienteId != s.clienteId) await _guardar(s);
  }

  Future<void> ligarCliente(Cliente c) async {
    final s = _s.copyWith(clienteId: c.id, clienteNombre: c.nombre, clienteTexto: c.nombre);
    _poner(s);
    await _guardar(s);
    if (s.forma == FormaPago.fiado) await _pintarFiado();
  }

  // ---------- Cobro ----------

  Future<void> elegirForma(FormaPago f) async {
    _poner(_s.copyWith(forma: f));
    if (f == FormaPago.fiado) await _pintarFiado();
  }

  void escribirRecibido(String texto) => _poner(_s.copyWith(recibidoTexto: texto));

  /// Exacto (0), 500, 1,000 o 2,000 pesos. Devuelve el texto que queda en "Recibido".
  String billete(int pesos) {
    final s = _s;
    final texto = pesos == 0 ? _textoMonto(s.total) : '$pesos';
    _poner(s.copyWith(recibidoTexto: texto));
    return texto;
  }

  Future<void> _pintarFiado() async {
    final s = _s;
    final c = s.clienteId == null ? null : await ref.read(fiadoServiceProvider).porId(s.clienteId!);
    if (c == null) {
      _poner(_s.copyWith(fiadoNombre: null, fiadoCredito: ''));
      return;
    }
    final debe = await ref.read(fiadoServiceProvider).balance(c.id);
    _poner(_s.copyWith(
      fiadoNombre: c.nombre,
      fiadoCredito: 'Debe ${formatoRD(debe)}. '
          '${c.limiteCredito > 0 ? 'Límite ${formatoRD(c.limiteCredito)}. ' : 'Sin límite de crédito. '}'
          'Con esta compra debería ${formatoRD(debe + _s.total)}.',
    ));
  }

  /// Descuento en pesos; 0 lo quita.
  String? fijarDescuento(int monto) {
    final s = _s;
    if (monto > s.subtotal) return 'El descuento no puede ser mayor que el total.';
    _poner(s.copyWith(descuento: monto));
    return null;
  }

  /// Para fiar hay que escoger el cliente antes de cobrar.
  bool get faltaClienteFiado => _s.forma == FormaPago.fiado && _s.clienteId == null;

  /// Cobra con lo que está marcado a la derecha. Devuelve el id de la venta, o
  /// el mensaje si una regla lo detuvo (el pedido sigue abierto).
  Future<({int? ventaId, String? aviso})> cobrar() async {
    var s = _s.copyWith(pendiente: null);
    if (s.lineas.isEmpty) return (ventaId: null, aviso: null);
    final total = s.total;
    int? recibido; // null = monto exacto
    if (s.forma == FormaPago.efectivo && s.recibidoTexto.trim().isNotEmpty) {
      recibido = s.recibido;
      if (recibido == null || recibido < total) return (ventaId: null, aviso: 'Con lo que paga no alcanza.');
    }
    if (s.forma == FormaPago.fiado && s.clienteId == null) {
      return (ventaId: null, aviso: 'Escoja el cliente al que se le fía.');
    }

    // Un delivery que se cobra antes de salir se cobra con su envío.
    final delivery = s.esDelivery && s.ticketId != null ? await _tickets.porId(s.ticketId!) : null;
    await _guardar(s);
    s = _s;
    final clienteFiado = s.forma == FormaPago.fiado ? s.clienteId : null;
    try {
      final SolicitudCobro solicitud;
      if (delivery != null) {
        solicitud = await ref.read(deliveryServiceProvider).solicitudDeCobro(delivery.id,
            forma: s.forma, recibido: recibido, descuento: s.descuento, clienteFiado: clienteFiado);
      } else {
        solicitud = SolicitudCobro(
          lineas: [
            for (final l in s.lineas)
              l.precioLibre != null
                  ? LineaCobro.servicio(
                      productoId: l.producto.id, descripcion: l.producto.nombre, monto: l.precioLibre!)
                  : l.comoPedido.aCobro(l.producto),
          ],
          formaPago: s.forma,
          descuento: s.descuento,
          montoRecibido: recibido,
          clienteId: s.clienteId,
          nombreCliente: s.clienteTexto,
          ticketAbiertoId: s.ticketId,
        );
      }
      final r = await ref.read(ventaServiceProvider).cobrar(ref.sesion, solicitud);
      // El pedido se borró junto con el cobro.
      final (nuevo, _) = await _estadoDe(null, _s.copyWith(ticketId: null));
      _poner(
          await _conPedidos(nuevo.copyWith(devueltaAnterior: r.formaPago == FormaPago.efectivo ? r.devuelta : null)));
      return (ventaId: r.ventaId, aviso: null);
    } on EmmaError catch (e) {
      return (ventaId: null, aviso: e.mensaje);
    }
  }

  /// Ticket, "última venta" y la barra del menú después de cobrar (en el
  /// mostrador o un delivery que volvió). Devuelve el aviso de la impresora.
  Future<String?> despuesDeVenta(int ventaId) async {
    final error = await ref.read(imprentaProvider).imprimirVenta(ventaId);
    final v = await ref.read(ventaServiceProvider).porId(ventaId);
    if (v != null) {
      final nombre = v.venta.nombreCliente;
      _poner(_s.copyWith(
        ultimaVentaId: ventaId,
        ultimaVentaTexto: 'Última venta: #$ventaId · ${formatoRD(v.venta.total)} · ${v.venta.formaPago.etiqueta}'
            '${nombre != null ? ' · $nombre' : ''} ·',
        ticketsPendientes: (await ref.read(ventaServiceProvider).ventasConTicketPendiente()).length,
        enLaCalle: (await ref.read(deliveryServiceProvider).enLaCalle()).length,
      ));
    }
    refrescarEstado(ref);
    return error;
  }

  Future<String?> reimprimir() async {
    final id = _s.ultimaVentaId;
    if (id == null) return null;
    final error = await ref.read(imprentaProvider).imprimirVenta(id);
    await _contarPendientes();
    return error;
  }

  /// El botón amarillo: imprime los tickets que quedaron pendientes.
  Future<String?> imprimirPendientes() async {
    for (final v in await ref.read(ventaServiceProvider).ventasConTicketPendiente()) {
      final error = await ref.read(imprentaProvider).imprimirVenta(v.id);
      if (error != null) {
        await _contarPendientes();
        return error;
      }
    }
    await _contarPendientes();
    return null;
  }

  Future<void> _contarPendientes() async =>
      _poner(_s.copyWith(ticketsPendientes: (await ref.read(ventaServiceProvider).ventasConTicketPendiente()).length));

  Future<String?> abrirGaveta() async {
    final error = await ref.read(imprentaProvider).abrirGaveta();
    await ref.read(negocioServiceProvider).anotarGaveta(ref.sesion);
    return error;
  }

  static String _textoMonto(int c) => c % 100 == 0 ? '${c ~/ 100}' : formatoMonto(c).replaceAll(',', '');
}
