import 'package:emma_core/emma_core.dart';

/// Un producto en la venta. Cantidad en milésimas, montos en centavos.
class LineaCarrito {
  const LineaCarrito({required this.producto, required this.cantidad, this.precioLibre, this.monto});

  final Producto producto;
  final int cantidad;

  /// Monto de una venta suelta ("Varios") o del envío; null usa el precio del producto.
  final int? precioLibre;

  /// Libra vendida por monto ("$50"): el total exacto.
  final int? monto;

  int get precio => precioLibre ?? producto.precio;
  int get total => monto ?? totalLinea(precio, cantidad);
  bool get esUnidad => producto.unidad == UnidadVenta.unidad;

  /// Va de uno en uno con − y +; lo demás pregunta la cantidad.
  bool get porPasos => esUnidad && precioLibre == null;
  String get cantidadTexto => formatoCantidadUnidad(cantidad, producto.unidad);

  LineaPedido get comoPedido =>
      LineaPedido(productoId: producto.id, cantidad: cantidad, precio: precioLibre, monto: monto);

  LineaCarrito conCantidad(int c) => LineaCarrito(producto: producto, cantidad: c, precioLibre: precioLibre);
}

/// Un botón de la barra de pedidos abiertos.
class PestanaPedido {
  const PestanaPedido({this.id, required this.titulo, this.detalle = '', required this.actual});

  /// null = el pedido nuevo que todavía no se ha guardado.
  final int? id;
  final String titulo;
  final String detalle;
  final bool actual;
}

const _igual = Object();

class VentasState {
  const VentasState({
    this.lineas = const [],
    this.seleccionada,
    this.ticketId,
    this.clienteTexto = '',
    this.clienteId,
    this.clienteNombre,
    this.esDelivery = false,
    this.envio = 0,
    this.descuento = 0,
    this.forma = FormaPago.efectivo,
    this.recibidoTexto = '',
    this.devueltaAnterior,
    this.pendiente,
    this.busqueda = const [],
    this.marcado = -1,
    this.pedidos = const [],
    this.enLaCalle = 0,
    this.ultimaVentaId,
    this.ultimaVentaTexto = '',
    this.ticketsPendientes = 0,
    this.fiadoNombre,
    this.fiadoCredito = '',
  });

  final List<LineaCarrito> lineas;
  final int? seleccionada;

  /// Pedido abierto que se está atendiendo; null mientras es nuevo y no tiene nada.
  final int? ticketId;

  /// Lo que dice la casilla del cliente.
  final String clienteTexto;

  /// Cliente de la lista ligado al pedido; null si solo se escribió un nombre.
  final int? clienteId;
  final String? clienteNombre;
  final bool esDelivery;

  /// Envío del pedido si es delivery (centavos).
  final int envio;
  final int descuento;
  final FormaPago forma;

  /// Con cuánto paga. Vacío = monto exacto.
  final String recibidoTexto;

  /// Devuelta de la venta recién cobrada; se enseña hasta que se empieza otro pedido.
  final int? devueltaAnterior;

  /// Producto por libra que espera las libras o el monto.
  final Producto? pendiente;

  /// La lista que sale debajo de la casilla del código: lo que se va
  /// escribiendo, o lo que encontró Enter.
  final List<Producto> busqueda;

  /// El que escoge Enter; -1 = ninguno (mientras se escribe).
  final int marcado;
  final List<PestanaPedido> pedidos;
  final int enLaCalle;
  final int? ultimaVentaId;
  final String ultimaVentaTexto;
  final int ticketsPendientes;

  /// Panel de fiado: a quién se le fía y su crédito.
  final String? fiadoNombre;
  final String fiadoCredito;

  int get subtotal => lineas.fold(0, (s, l) => s + l.total) + envio;
  int get total => subtotal - descuento < 0 ? 0 : subtotal - descuento;

  /// Centavos, o null si está vacío o no es un monto.
  int? get recibido => recibidoTexto.trim().isEmpty ? null : parsearMonto(recibidoTexto);

  /// "2 productos · 5 artículos": las unidades se cuentan una a una; lo que va por libra cuenta como uno.
  String get articulosTexto {
    final n = lineas.length;
    if (n == 0) return 'Sin productos';
    final articulos = lineas.fold<int>(0, (s, l) => s + (l.esUnidad ? l.cantidad ~/ milesimasPorUnidad : 1));
    return '${n == 1 ? '1 producto' : '$n productos'} · $articulos ${articulos == 1 ? 'artículo' : 'artículos'}'
        '${esDelivery ? ' · envío ${formatoRD(envio)}' : ''}';
  }

  /// Etiqueta, monto y si va en rojo (faltan) de la caja de la devuelta.
  ({String etiqueta, String monto, bool falta}) get devuelta {
    final t = recibidoTexto.trim();
    if (lineas.isEmpty && devueltaAnterior != null) {
      return (etiqueta: 'Devuelta (venta anterior)', monto: formatoRD(devueltaAnterior!), falta: false);
    }
    if (t.isEmpty) return (etiqueta: 'Devuelta', monto: formatoRD(0), falta: false);
    final r = recibido;
    if (r != null && r >= total) return (etiqueta: 'Devuelta', monto: formatoRD(r - total), falta: false);
    return (etiqueta: 'Faltan', monto: r == null ? '-' : formatoRD(total - r), falta: true);
  }

  /// El billete que se tocó queda marcado (0 = Exacto).
  bool billeteMarcado(int pesos) {
    final r = recibido;
    if (r == null) return false;
    return pesos == 0 ? r == total && total > 0 : r == pesos * 100;
  }

  VentasState copyWith({
    List<LineaCarrito>? lineas,
    Object? seleccionada = _igual,
    Object? ticketId = _igual,
    String? clienteTexto,
    Object? clienteId = _igual,
    Object? clienteNombre = _igual,
    bool? esDelivery,
    int? envio,
    int? descuento,
    FormaPago? forma,
    String? recibidoTexto,
    Object? devueltaAnterior = _igual,
    Object? pendiente = _igual,
    List<Producto>? busqueda,
    int? marcado,
    List<PestanaPedido>? pedidos,
    int? enLaCalle,
    Object? ultimaVentaId = _igual,
    String? ultimaVentaTexto,
    int? ticketsPendientes,
    Object? fiadoNombre = _igual,
    String? fiadoCredito,
  }) =>
      VentasState(
        lineas: lineas ?? this.lineas,
        seleccionada: identical(seleccionada, _igual) ? this.seleccionada : seleccionada as int?,
        ticketId: identical(ticketId, _igual) ? this.ticketId : ticketId as int?,
        clienteTexto: clienteTexto ?? this.clienteTexto,
        clienteId: identical(clienteId, _igual) ? this.clienteId : clienteId as int?,
        clienteNombre: identical(clienteNombre, _igual) ? this.clienteNombre : clienteNombre as String?,
        esDelivery: esDelivery ?? this.esDelivery,
        envio: envio ?? this.envio,
        descuento: descuento ?? this.descuento,
        forma: forma ?? this.forma,
        recibidoTexto: recibidoTexto ?? this.recibidoTexto,
        devueltaAnterior: identical(devueltaAnterior, _igual) ? this.devueltaAnterior : devueltaAnterior as int?,
        pendiente: identical(pendiente, _igual) ? this.pendiente : pendiente as Producto?,
        busqueda: busqueda ?? this.busqueda,
        marcado: marcado ?? this.marcado,
        pedidos: pedidos ?? this.pedidos,
        enLaCalle: enLaCalle ?? this.enLaCalle,
        ultimaVentaId: identical(ultimaVentaId, _igual) ? this.ultimaVentaId : ultimaVentaId as int?,
        ultimaVentaTexto: ultimaVentaTexto ?? this.ultimaVentaTexto,
        ticketsPendientes: ticketsPendientes ?? this.ticketsPendientes,
        fiadoNombre: identical(fiadoNombre, _igual) ? this.fiadoNombre : fiadoNombre as String?,
        fiadoCredito: fiadoCredito ?? this.fiadoCredito,
      );
}

/// Qué pasó al pulsar Enter en la casilla del código.
sealed class ResultadoCodigo {
  const ResultadoCodigo();
}

/// Ya quedó en la venta (o se puso la cantidad pendiente de una libra).
class Listo extends ResultadoCodigo {
  const Listo();
}

/// Casilla vacía con productos: pasar a "Recibido" (efectivo) o cobrar.
class IrACobrar extends ResultadoCodigo {
  const IrACobrar();
}

/// Producto por libra: pasar a la casilla de cantidad.
class PedirLibras extends ResultadoCodigo {
  const PedirLibras();
}

/// Varios parecidos: se muestra la lista.
class EscogerDeLista extends ResultadoCodigo {
  const EscogerDeLista();
}

/// No se encontró. Si [ofrecerCrear], el dueño puede crearlo con ese código.
class NoEncontrado extends ResultadoCodigo {
  const NoEncontrado(this.mensaje, {this.codigo, this.ofrecerCrear = false, this.cantidad});

  final String mensaje;
  final String? codigo;
  final bool ofrecerCrear;

  /// Con "3*código", la cantidad que se pidió.
  final int? cantidad;
}

/// Una regla detuvo la acción; se muestra el mensaje.
class Aviso extends ResultadoCodigo {
  const Aviso(this.mensaje);

  final String mensaje;
}
