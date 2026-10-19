// Tablas locales de Emma. Mismas tablas que la 0.6 (ver PRD, "Modelo de datos local").
//
// Unidades:
//   * Montos (costo, precio, total, límite, etc.): ENTEROS EN CENTAVOS.
//   * Cantidades y existencias: ENTEROS EN MILÉSIMAS (1 unidad = 1000, 0.5 lb = 500).
//   * Fechas: hora local del colmado.
import 'package:drift/drift.dart';

import 'enums.dart';

@DataClassName('NegocioRow')
class Negocios extends Table {
  @override
  String get tableName => 'negocio';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withDefault(const Constant('Mi Colmado'))();
  TextColumn get rnc => text().nullable()();
  TextColumn get direccion => text().nullable()();
  TextColumn get telefono => text().nullable()();
  TextColumn get mensajeTicket => text().withDefault(const Constant('Gracias por su compra'))();
  TextColumn get impresora => text().nullable()();

  /// Letras por línea: 48 en papel de 80 mm, 32 en papel de 58 mm.
  IntColumn get anchoTicket => integer().withDefault(const Constant(48))();
  BoolColumn get abrirGaveta => boolean().withDefault(const Constant(true))();

  /// Todo el ticket en letra resaltada: sale más oscuro en papel térmico.
  BoolColumn get ticketOscuro => boolean().withDefault(const Constant(true))();
  TextColumn get intensidadTicket =>
      textEnum<IntensidadTicket>().withDefault(const Constant('normal'))();
  BlobColumn get logoTicket => blob().nullable()();
  IntColumn get logoAncho => integer().nullable()();
  TextColumn get carpetaRespaldoExterna => text().nullable()();
  TextColumn get instalacionId => text()();
  DateTimeColumn get ultimoMantenimiento => dateTime().nullable()();

  /// Envío de delivery por defecto (centavos).
  IntColumn get cargoDelivery => integer().withDefault(const Constant(0))();
  TextColumn get nubeCajaId => text().nullable()();

  /// Se deja vacía: la llave real va en flutter_secure_storage (DPAPI / Keystore).
  /// La columna existe para que la importación desde la 0.6 tenga dónde caer.
  TextColumn get nubeLlave => text().nullable()();
  TextColumn get nubeNegocio => text().nullable()();
  TextColumn get nubeCaja => text().nullable()();
  DateTimeColumn get nubeUltimoEnvio => dateTime().nullable()();
}

@DataClassName('Usuario')
class Usuarios extends Table {
  @override
  String get tableName => 'usuarios';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get login => text().unique()();
  TextColumn get pinHash => text()();
  TextColumn get rol => textEnum<Rol>()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
}

@DataClassName('Categoria')
class Categorias extends Table {
  @override
  String get tableName => 'categorias';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().unique()();
}

@DataClassName('Producto')
@TableIndex(name: 'ix_productos_nombre', columns: {#nombre})
class Productos extends Table {
  @override
  String get tableName => 'productos';

  IntColumn get id => integer().autoIncrement()();

  /// Código de barras. Puede faltar (pan, plátano); si está, no se repite.
  TextColumn get codigo => text().nullable().unique()();
  TextColumn get nombre => text()();
  IntColumn get categoriaId => integer().nullable().references(Categorias, #id)();
  IntColumn get costo => integer().withDefault(const Constant(0))();
  IntColumn get precio => integer()();
  IntColumn get existencia => integer().withDefault(const Constant(0))();
  IntColumn get existenciaMinima => integer().withDefault(const Constant(0))();
  TextColumn get unidad => textEnum<UnidadVenta>().withDefault(const Constant('unidad'))();
  BoolColumn get esRapido => boolean().withDefault(const Constant(false))();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// En centésimas de por ciento (1800 = 18 %). La 0.6 la guarda pero ningún
  /// flujo del PRD la usa todavía (el ticket es "Documento no fiscal").
  IntColumn get tasaItbis => integer().withDefault(const Constant(0))();
}

@DataClassName('Cliente')
@TableIndex(name: 'ix_clientes_telefono', columns: {#telefono})
class Clientes extends Table {
  @override
  String get tableName => 'clientes';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get telefono => text().nullable()();
  TextColumn get direccion => text().nullable()();
  TextColumn get cedula => text().nullable()();

  /// Centavos. 0 = sin límite.
  IntColumn get limiteCredito => integer().withDefault(const Constant(0))();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  BoolColumn get esFijo => boolean().withDefault(const Constant(false))();
  TextColumn get referencia => text().nullable()();
  TextColumn get sector => text().nullable()();
  TextColumn get correo => text().nullable()();

  /// "dd/MM".
  TextColumn get cumpleanos => text().nullable()();
  TextColumn get notas => text().nullable()();
  DateTimeColumn get creado => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Repartidor')
class Repartidores extends Table {
  @override
  String get tableName => 'repartidores';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get telefono => text().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get creado => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TurnoCaja')
class TurnosCaja extends Table {
  @override
  String get tableName => 'turnos_caja';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get apertura => dateTime()();
  IntColumn get fondoInicial => integer()();
  DateTimeColumn get cierre => dateTime().nullable()();
  IntColumn get efectivoEsperado => integer().nullable()();
  IntColumn get efectivoContado => integer().nullable()();
  IntColumn get diferencia => integer().nullable()();

  /// JSON: {"2000": 1, "1000": 3, ...}
  TextColumn get detalleConteo => text().nullable()();
  TextColumn get notas => text().nullable()();
}

@DataClassName('Venta')
@TableIndex(name: 'ix_ventas_fecha', columns: {#fecha})
@TableIndex(name: 'ix_ventas_turno', columns: {#turnoCajaId})
@TableIndex(name: 'ix_ventas_cliente', columns: {#clienteId})
class Ventas extends Table {
  @override
  String get tableName => 'ventas';

  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get fecha => dateTime()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  IntColumn get turnoCajaId => integer().references(TurnosCaja, #id)();
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  TextColumn get nombreCliente => text().nullable()();
  IntColumn get subtotal => integer()();
  IntColumn get descuento => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  TextColumn get formaPago => textEnum<FormaPago>()();
  IntColumn get montoRecibido => integer().withDefault(const Constant(0))();
  IntColumn get devuelta => integer().withDefault(const Constant(0))();
  BoolColumn get anulada => boolean().withDefault(const Constant(false))();
  DateTimeColumn get fechaAnulacion => dateTime().nullable()();
  @ReferenceName('ventasAnuladas')
  IntColumn get anuladaPorId => integer().nullable().references(Usuarios, #id)();
  TextColumn get motivoAnulacion => text().nullable()();
  BoolColumn get ticketPendiente => boolean().withDefault(const Constant(false))();
  BoolColumn get esDelivery => boolean().withDefault(const Constant(false))();
  TextColumn get repartidor => text().nullable()();
  TextColumn get direccionEntrega => text().nullable()();
  TextColumn get deliveryId => text().nullable()();
}

@DataClassName('VentaLinea')
@TableIndex(name: 'ix_venta_lineas_venta', columns: {#ventaId})
@TableIndex(name: 'ix_venta_lineas_producto', columns: {#productoId})
class VentaLineas extends Table {
  @override
  String get tableName => 'venta_lineas';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get ventaId => integer().references(Ventas, #id)();
  IntColumn get productoId => integer().references(Productos, #id)();
  TextColumn get descripcion => text()();

  /// Milésimas.
  IntColumn get cantidad => integer()();
  IntColumn get precioUnitario => integer()();
  IntColumn get costoUnitario => integer()();
  IntColumn get total => integer()();
}

@DataClassName('TicketAbierto')
class TicketsAbiertos extends Table {
  @override
  String get tableName => 'tickets_abiertos';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get numero => integer()();
  TextColumn get nombreCliente => text().nullable()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get creado => dateTime()();
  DateTimeColumn get actualizado => dateTime()();

  /// JSON con las líneas del pedido.
  TextColumn get lineas => text().withDefault(const Constant('[]'))();
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  BoolColumn get esDelivery => boolean().withDefault(const Constant(false))();
  TextColumn get telefono => text().nullable()();
  TextColumn get direccion => text().nullable()();
  IntColumn get pagaCon => integer().nullable()();
  IntColumn get cargoEnvio => integer().withDefault(const Constant(0))();
  TextColumn get repartidor => text().nullable()();
  TextColumn get estadoDelivery => textEnum<EstadoDelivery>().nullable()();
  DateTimeColumn get salioEn => dateTime().nullable()();
  TextColumn get deliveryId => text().nullable()();
}

@DataClassName('MovimientoInventario')
@TableIndex(name: 'ix_mov_inv_producto', columns: {#productoId, #fecha})
class MovimientosInventario extends Table {
  @override
  String get tableName => 'movimientos_inventario';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get productoId => integer().references(Productos, #id)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get tipo => textEnum<TipoMovInventario>()();

  /// Milésimas, con signo: la venta resta (negativo), la anulación suma.
  IntColumn get cantidad => integer()();
  IntColumn get existenciaResultante => integer()();
  TextColumn get referencia => text().nullable()();
  IntColumn get usuarioId => integer().nullable().references(Usuarios, #id)();
}

@DataClassName('MovimientoFiado')
@TableIndex(name: 'ix_mov_fiado_cliente', columns: {#clienteId, #fecha})
class MovimientosFiado extends Table {
  @override
  String get tableName => 'movimientos_fiado';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get clienteId => integer().references(Clientes, #id)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get tipo => textEnum<TipoMovFiado>()();

  /// Centavos, siempre positivo. El tipo dice si suma o resta a la deuda.
  IntColumn get monto => integer()();
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();
  IntColumn get turnoCajaId => integer().nullable().references(TurnosCaja, #id)();
  TextColumn get formaPagoAbono => textEnum<FormaPago>().nullable()();
  IntColumn get usuarioId => integer().nullable().references(Usuarios, #id)();
  TextColumn get nota => text().nullable()();
}

@DataClassName('MovimientoCaja')
class MovimientosCaja extends Table {
  @override
  String get tableName => 'movimientos_caja';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get turnoCajaId => integer().references(TurnosCaja, #id)();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get tipo => textEnum<TipoMovCaja>()();
  IntColumn get monto => integer()();
  TextColumn get concepto => text()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
}

@DataClassName('EntradaBitacora')
class Bitacora extends Table {
  @override
  String get tableName => 'bitacora';

  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get fecha => dateTime()();
  IntColumn get usuarioId => integer().nullable().references(Usuarios, #id)();
  TextColumn get accion => text()();
  TextColumn get detalle => text().nullable()();
}

@DataClassName('EventoSalida')
@TableIndex(name: 'ix_eventos_pendientes', columns: {#enviadoEn, #fecha})
class EventosSalida extends Table {
  @override
  String get tableName => 'eventos_salida';

  /// uuid v4. El servidor ignora ids repetidos.
  TextColumn get id => text()();
  DateTimeColumn get fecha => dateTime()();
  TextColumn get tipo => text()();

  /// JSON como texto, campos en PascalCase.
  TextColumn get datos => text()();
  DateTimeColumn get enviadoEn => dateTime().nullable()();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
  TextColumn get ultimoError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A quien se le compra la mercancía (distribuidora, almacén, el camión de la cerveza...).
@DataClassName('Suplidor')
@TableIndex(name: 'ix_suplidores_nombre', columns: {#nombre})
class Suplidores extends Table {
  @override
  String get tableName => 'suplidores';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get telefono => text().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
}

/// Mercancía que entra al colmado. Sube la existencia y deja el costo nuevo.
@DataClassName('Compra')
@TableIndex(name: 'ix_compras_fecha', columns: {#fecha})
class Compras extends Table {
  @override
  String get tableName => 'compras';

  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get fecha => dateTime()();
  IntColumn get suplidorId => integer().nullable().references(Suplidores, #id)();

  /// Número de la factura del suplidor, si tiene.
  TextColumn get factura => text().nullable()();
  TextColumn get pago => textEnum<PagoCompra>()();
  IntColumn get total => integer()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  TextColumn get nota => text().nullable()();
}

@DataClassName('CompraLinea')
@TableIndex(name: 'ix_compra_lineas_compra', columns: {#compraId})
class CompraLineas extends Table {
  @override
  String get tableName => 'compra_lineas';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get compraId => integer().references(Compras, #id)();
  IntColumn get productoId => integer().references(Productos, #id)();
  TextColumn get descripcion => text()();

  /// Milésimas.
  IntColumn get cantidad => integer()();

  /// Centavos por unidad o por libra.
  IntColumn get costo => integer()();
  IntColumn get total => integer()();
}

/// Cómo le dice un suplidor a un producto en su factura ("ARROZ SEL 25LB" =
/// Arroz Selecto 25 lb). Se aprende cuando el dueño empareja una factura leída.
@DataClassName('AliasProducto')
@TableIndex(name: 'ix_alias_productos', columns: {#suplidorId, #texto})
class AliasProductos extends Table {
  @override
  String get tableName => 'alias_productos';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get suplidorId => integer().nullable().references(Suplidores, #id)();

  /// Texto de la factura ya normalizado (minúsculas, sin acentos ni signos).
  TextColumn get texto => text()();
  IntColumn get productoId => integer().references(Productos, #id)();
}
