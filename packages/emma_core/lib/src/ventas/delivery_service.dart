import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../nube/eventos.dart';
import '../sesion.dart';
import 'ticket_service.dart';
import 'venta_service.dart';

/// Lo que se escribe al marcar un pedido como delivery. Montos en centavos.
class DatosDelivery {
  const DatosDelivery({
    this.nombre,
    this.telefono,
    required this.direccion,
    this.pagaCon,
    this.cargoEnvio = 0,
    this.repartidor,
    this.clienteId,
  });

  final String? nombre;
  final String? telefono;
  final String direccion;
  final int? pagaCon;
  final int cargoEnvio;
  final String? repartidor;

  /// Cliente de la lista; si es null y hay teléfono, se busca o se crea como fijo.
  final int? clienteId;
}

class DatosRepartidor {
  const DatosRepartidor({this.id, required this.nombre, this.telefono, this.activo = true});

  final int? id;
  final String nombre;
  final String? telefono;
  final bool activo;
}

/// Un delivery que va en la calle, con su total ya calculado.
class DeliveryEnCamino {
  const DeliveryEnCamino({required this.pedido, required this.total, required this.minutos});

  final TicketAbierto pedido;

  /// Centavos.
  final int total;
  final int minutos;

  /// El cambio que lleva el repartidor.
  int? get cambio => pedido.pagaCon != null && pedido.pagaCon! > total ? pedido.pagaCon! - total : null;
}

/// Una línea de la comanda que lleva el repartidor.
class LineaComanda {
  const LineaComanda(this.descripcion, this.cantidad, this.total);

  final String descripcion;

  /// Milésimas.
  final int cantidad;

  /// Centavos.
  final int total;
}

/// Delivery: el pedido se arma como cualquier otro, se le ponen los datos de
/// entrega y sale con el repartidor. Sigue abierto mientras va en camino;
/// cuando el repartidor vuelve con el dinero se cobra y pasa a ser venta.
class DeliveryService {
  DeliveryService(this.db, {Reloj? reloj})
      : _reloj = reloj ?? db.reloj,
        _tickets = TicketService(db, reloj: reloj);

  final EmmaDatabase db;
  final Reloj _reloj;
  final TicketService _tickets;

  /// Solo los números, para buscar "809-555-1234" igual que "8095551234".
  static String soloNumeros(String? telefono) => (telefono ?? '').replaceAll(RegExp(r'\D'), '');

  /// El cliente con ese teléfono, si ya está en la lista.
  Future<Cliente?> clientePorTelefono(String? telefono) async {
    final buscado = soloNumeros(telefono);
    if (buscado.length < 7) return null;
    final candidatos = await (db.select(db.clientes)..where((c) => c.activo.equals(true) & c.telefono.isNotNull())).get();
    final iguales = candidatos.where((c) {
      final t = soloNumeros(c.telefono);
      return t.length >= 7 && (t.endsWith(buscado) || buscado.endsWith(t));
    }).toList()
      ..sort((a, b) => (b.esFijo ? 1 : 0).compareTo(a.esFijo ? 1 : 0));
    return iguales.isEmpty ? null : iguales.first;
  }

  /// Los repartidores registrados (en Configuración), activos primero.
  Future<List<Repartidor>> listaRepartidores({bool incluirInactivos = false}) => (db.select(db.repartidores)
        ..where((r) => incluirInactivos ? const Constant(true) : r.activo.equals(true))
        ..orderBy([(r) => OrderingTerm.desc(r.activo), (r) => OrderingTerm.asc(r.nombre)]))
      .get();

  Future<Repartidor> guardarRepartidor(Sesion sesion, DatosRepartidor d) async {
    final nombre = _limpio(d.nombre);
    if (nombre == null) throw const DatoInvalido('Escriba el nombre del repartidor.');
    final fecha = _reloj();
    return db.transaction(() async {
      final todos = await db.select(db.repartidores).get();
      final repetido = todos.any((r) => r.id != d.id && r.activo && r.nombre.toLowerCase() == nombre.toLowerCase());
      if (repetido && d.activo) throw DatoInvalido('Ya hay un repartidor llamado $nombre.');
      final datos = RepartidoresCompanion(nombre: Value(nombre), telefono: Value(_limpio(d.telefono)), activo: Value(d.activo));
      final int id;
      if (d.id == null) {
        id = await db.into(db.repartidores).insert(datos.copyWith(creado: Value(fecha)));
      } else {
        final cambiados = await (db.update(db.repartidores)..where((r) => r.id.equals(d.id!))).write(datos);
        if (cambiados == 0) throw const DatoInvalido('Ese repartidor ya no existe.');
        id = d.id!;
      }
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: d.id == null ? 'Repartidor agregado' : 'Repartidor cambiado',
        detalle: nombre + (d.activo ? '' : ' (quitado)'),
        fecha: fecha,
      );
      return (db.select(db.repartidores)..where((r) => r.id.equals(id))).getSingle();
    });
  }

  /// Nombres para escoger al despachar: primero los registrados, después los
  /// que se escribieron a mano antes (sin los que se quitaron de la lista).
  Future<List<String>> repartidores() async {
    final todos = await db.select(db.repartidores).get();
    final registrados = (todos.where((r) => r.activo).map((r) => r.nombre).toList())..sort();
    final quitados = todos.where((r) => !r.activo).map((r) => r.nombre.toLowerCase()).toSet();
    final deVentas = await (db.select(db.ventas)
          ..where((v) => v.repartidor.isNotNull())
          ..orderBy([(v) => OrderingTerm.desc(v.id)])
          ..limit(300))
        .get();
    final enCalle = await (db.select(db.ticketsAbiertos)..where((t) => t.repartidor.isNotNull())).get();
    final usados = [...enCalle.map((t) => t.repartidor!), ...deVentas.map((v) => v.repartidor!)]
        .where((n) => !quitados.contains(n.toLowerCase()));
    final vistos = <String>{};
    return [
      for (final n in [...registrados, ...usados])
        if (vistos.add(n.toLowerCase())) n,
    ];
  }

  /// Pone los datos de entrega al pedido. Si el teléfono no está en la lista
  /// de clientes, lo guarda como cliente fijo para que la próxima vez salga la
  /// dirección sola.
  Future<TicketAbierto> preparar(Sesion sesion, int ticketId, DatosDelivery d) async {
    final direccion = _limpio(d.direccion);
    if (direccion == null) throw const DatoInvalido('Escriba la dirección o referencia de la entrega.');
    if (d.cargoEnvio < 0) throw const DatoInvalido('El cargo de envío no puede ser negativo.');
    final ahora = _reloj();
    // Se busca antes de la transacción: es solo lectura.
    final porTelefono = d.clienteId == null ? await clientePorTelefono(d.telefono) : null;
    return db.transaction(() async {
      final t = await _tickets.porId(ticketId);
      if (t == null) throw const DatoInvalido('El pedido ya no existe.');
      if (t.estadoDelivery == EstadoDelivery.enCamino) throw const DatoInvalido('Ese delivery ya va en camino.');

      Cliente? cliente = d.clienteId == null
          ? porTelefono
          : await (db.select(db.clientes)..where((c) => c.id.equals(d.clienteId!))).getSingleOrNull();
      if (cliente == null && soloNumeros(d.telefono).length >= 7 && _limpio(d.nombre) != null) {
        final id = await db.into(db.clientes).insert(ClientesCompanion.insert(
              nombre: d.nombre!.trim(),
              telefono: Value(d.telefono!.trim()),
              direccion: Value(direccion),
              esFijo: const Value(true),
              creado: Value(ahora),
            ));
        cliente = await (db.select(db.clientes)..where((c) => c.id.equals(id))).getSingle();
        await db.anotarBitacora(
            usuarioId: sesion.usuarioId, accion: 'Cliente creado desde delivery', detalle: cliente.nombre, fecha: ahora);
      }
      // Si el cliente no tenía dirección o teléfono, se le guardan.
      if (cliente != null) {
        await (db.update(db.clientes)..where((c) => c.id.equals(cliente!.id))).write(ClientesCompanion(
          direccion: Value(_limpio(cliente.direccion) ?? direccion),
          telefono: Value(_limpio(cliente.telefono) ?? _limpio(d.telefono)),
        ));
      }
      await (db.update(db.ticketsAbiertos)..where((x) => x.id.equals(ticketId))).write(TicketsAbiertosCompanion(
        esDelivery: const Value(true),
        clienteId: Value(cliente?.id),
        nombreCliente: Value(_limpio(d.nombre) ?? cliente?.nombre ?? t.nombreCliente),
        telefono: Value(_limpio(d.telefono) ?? cliente?.telefono),
        direccion: Value(direccion),
        pagaCon: Value(d.pagaCon != null && d.pagaCon! > 0 ? d.pagaCon : null),
        cargoEnvio: Value(d.cargoEnvio),
        repartidor: Value(_limpio(d.repartidor)),
        estadoDelivery: const Value(EstadoDelivery.tomado),
        actualizado: Value(ahora),
      ));
      return (await _tickets.porId(ticketId))!;
    });
  }

  /// Quita el delivery del pedido: vuelve a ser un pedido de mostrador.
  Future<void> quitarDelivery(int ticketId) async {
    final t = await _tickets.porId(ticketId);
    if (t == null) throw const DatoInvalido('El pedido ya no existe.');
    if (t.estadoDelivery == EstadoDelivery.enCamino) throw const DatoInvalido('Ese delivery ya va en camino.');
    await (db.update(db.ticketsAbiertos)..where((x) => x.id.equals(ticketId))).write(const TicketsAbiertosCompanion(
      esDelivery: Value(false),
      cargoEnvio: Value(0),
      pagaCon: Value(null),
      estadoDelivery: Value(null),
    ));
  }

  /// Total del pedido con los precios de hoy, más el envío.
  Future<int> total(TicketAbierto t) => _tickets.total(t);

  /// Las líneas para la comanda (sin el envío, que la comanda pone aparte).
  Future<List<LineaComanda>> lineasComanda(TicketAbierto t) async {
    final ls = TicketService.lineas(t);
    final ids = ls.map((l) => l.productoId).toSet().toList();
    final ps = ids.isEmpty ? <Producto>[] : await (db.select(db.productos)..where((p) => p.id.isIn(ids))).get();
    final productos = {for (final p in ps) p.id: p};
    return [
      for (final l in ls)
        if (productos[l.productoId] case final p?) LineaComanda(p.nombre, l.cantidad, l.totalCon(p)),
    ];
  }

  /// El pedido sale con el repartidor: deja de verse en el mostrador y pasa a
  /// "En la calle".
  Future<TicketAbierto> despachar(Sesion sesion, int ticketId, {String? repartidor}) async {
    final ahora = _reloj();
    final t = await db.transaction(() async {
      final t = await _tickets.porId(ticketId);
      if (t == null) throw const DatoInvalido('El pedido ya no existe.');
      if (!t.esDelivery) throw const DatoInvalido('Primero ponga los datos del delivery.');
      if (t.estadoDelivery == EstadoDelivery.enCamino) throw const DatoInvalido('Ese delivery ya va en camino.');
      if (TicketService.lineas(t).isEmpty) throw const DatoInvalido('El pedido no tiene productos.');
      final rep = _limpio(repartidor) ?? t.repartidor;
      final deliveryId = t.deliveryId ?? db.nuevoUuid();
      await (db.update(db.ticketsAbiertos)..where((x) => x.id.equals(ticketId))).write(TicketsAbiertosCompanion(
        repartidor: Value(rep),
        estadoDelivery: const Value(EstadoDelivery.enCamino),
        salioEn: Value(ahora),
        deliveryId: Value(deliveryId),
      ));
      final listo = (await _tickets.porId(ticketId))!;
      final total = await _tickets.total(listo);
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Delivery despachado',
        detalle: '${TicketService.titulo(listo)} con ${rep ?? 'sin repartidor'}: ${formatoRD(total)}',
        fecha: ahora,
      );
      await db.encolarEvento(TipoEvento.deliverySalio, {
        'DeliveryId': deliveryId,
        'Cliente': listo.nombreCliente,
        'Telefono': listo.telefono,
        'Direccion': listo.direccion,
        'Repartidor': rep,
        'Total': montoJson(total),
        'Fecha': fechaLocalIso(ahora),
      }, ahora);
      return listo;
    });
    return t;
  }

  Future<List<DeliveryEnCamino>> enLaCalle() async {
    final pedidos = await (db.select(db.ticketsAbiertos)
          ..where((t) => t.estadoDelivery.equalsValue(EstadoDelivery.enCamino))
          ..orderBy([(t) => OrderingTerm.asc(t.salioEn)]))
        .get();
    final ahora = _reloj();
    return [
      for (final p in pedidos)
        DeliveryEnCamino(
          pedido: p,
          total: await _tickets.total(p),
          minutos: p.salioEn == null ? 0 : ahora.difference(p.salioEn!).inMinutes.clamp(0, 1 << 30),
        ),
    ];
  }

  /// El repartidor volvió sin entregar: el pedido regresa al mostrador.
  Future<void> devolver(Sesion sesion, int ticketId, String? motivo) async {
    final ahora = _reloj();
    await db.transaction(() async {
      final t = await _tickets.porId(ticketId);
      if (t == null) throw const DatoInvalido('El pedido ya no existe.');
      if (t.estadoDelivery != EstadoDelivery.enCamino) throw const DatoInvalido('Ese pedido no está en la calle.');
      await (db.update(db.ticketsAbiertos)..where((x) => x.id.equals(ticketId))).write(const TicketsAbiertosCompanion(
        estadoDelivery: Value(EstadoDelivery.tomado),
        salioEn: Value(null),
      ));
      await db.anotarBitacora(
        usuarioId: sesion.usuarioId,
        accion: 'Delivery devuelto',
        detalle: '${TicketService.titulo(t)}: ${_limpio(motivo) ?? ''}',
        fecha: ahora,
      );
      await db.encolarEvento(TipoEvento.deliveryDevuelto, {
        'DeliveryId': t.deliveryId,
        'Motivo': _limpio(motivo),
        'Fecha': fechaLocalIso(ahora),
      }, ahora);
    });
  }

  /// La solicitud para cobrar el delivery: productos, envío y datos de entrega.
  /// [recibido] null = monto exacto.
  Future<SolicitudCobro> solicitudDeCobro(
    int ticketId, {
    required FormaPago forma,
    int? recibido,
    int descuento = 0,
    int? clienteFiado,
  }) async {
    final t = await _tickets.porId(ticketId);
    if (t == null) throw const DatoInvalido('El pedido ya no existe.');
    final ls = TicketService.lineas(t);
    final ids = ls.map((l) => l.productoId).toSet().toList();
    final ps = ids.isEmpty ? <Producto>[] : await (db.select(db.productos)..where((p) => p.id.isIn(ids))).get();
    final productos = {for (final p in ps) p.id: p};
    final lineas = [
      for (final l in ls)
        if (productos[l.productoId] case final p?) l.aCobro(p),
    ];
    if (t.cargoEnvio > 0) {
      final envio = await db.productoEnvio();
      lineas.add(LineaCobro.servicio(productoId: envio.id, descripcion: envio.nombre, monto: t.cargoEnvio));
    }
    return SolicitudCobro(
      lineas: lineas,
      formaPago: forma,
      montoRecibido: recibido,
      descuento: descuento,
      clienteId: clienteFiado ?? t.clienteId,
      nombreCliente: t.nombreCliente,
      ticketAbiertoId: t.id,
      esDelivery: t.esDelivery,
      repartidor: t.repartidor,
      direccionEntrega: t.direccion,
      deliveryId: t.deliveryId,
    );
  }

  static String? _limpio(String? s) {
    final x = s?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
