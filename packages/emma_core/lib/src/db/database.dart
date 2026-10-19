import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../nube/eventos.dart';
import '../seguridad/pin_hasher.dart';
import '../sesion.dart';
import 'enums.dart';
import 'tablas.dart';

export 'enums.dart';
export 'tablas.dart';

part 'database.g.dart';

/// Código reservado del producto interno para la venta suelta ("Varios").
/// No lleva inventario.
const codigoVarios = '__VARIOS__';

/// Código reservado del cargo por llevar un delivery. No lleva inventario.
const codigoEnvio = '__ENVIO__';

/// Productos de servicio: se cobra el monto que se escriba y no llevan inventario.
bool esServicio(Producto p) => p.codigo == codigoVarios || p.codigo == codigoEnvio;

/// Usuario y PIN del primer arranque (el PRD obliga a cambiarlo al entrar).
const loginInicial = 'admin';
const pinInicial = '1234';

@DriftDatabase(tables: [
  Negocios,
  Usuarios,
  Categorias,
  Productos,
  Clientes,
  Repartidores,
  TurnosCaja,
  Ventas,
  VentaLineas,
  TicketsAbiertos,
  MovimientosInventario,
  MovimientosFiado,
  MovimientosCaja,
  Bitacora,
  EventosSalida,
  Suplidores,
  Compras,
  CompraLineas,
  AliasProductos,
])
class EmmaDatabase extends _$EmmaDatabase {
  EmmaDatabase(super.e, {PinHasher? pinHasher, String Function()? nuevoUuid, Reloj? reloj})
      : pinHasher = pinHasher ?? PinHasher(),
        nuevoUuid = nuevoUuid ?? const Uuid().v4,
        reloj = reloj ?? relojDelSistema;

  final PinHasher pinHasher;
  final String Function() nuevoUuid;
  final Reloj reloj;

  /// Subir este número y agregar el paso en [onUpgrade] para cada cambio de esquema.
  static const versionEsquema = 1;

  @override
  int get schemaVersion => versionEsquema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _sembrarPrimerArranque();
        },
        onUpgrade: (m, desde, hasta) async {
          // Sin pasos todavía: la versión 1 es la migración inicial.
          // Cada versión nueva agrega su `if (desde < N) { ... }`.
        },
        beforeOpen: (detalles) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _sembrarPrimerArranque() async {
    await into(negocios).insert(NegociosCompanion.insert(instalacionId: nuevoUuid()));
    await into(usuarios).insert(UsuariosCompanion.insert(
      nombre: 'Dueño',
      login: loginInicial,
      pinHash: await pinHasher.hash(pinInicial),
      rol: Rol.dueno,
    ));
    await into(productos).insert(ProductosCompanion.insert(
      codigo: const Value(codigoVarios),
      nombre: 'Varios',
      precio: 0,
    ));
    await into(productos).insert(ProductosCompanion.insert(
      codigo: const Value(codigoEnvio),
      nombre: 'Envío a domicilio',
      precio: 0,
    ));
  }

  // ---------------------------------------------------------------------------
  // Consultas comunes que usan varios servicios.

  Future<NegocioRow> negocio() => (select(negocios)..limit(1)).getSingle();

  Future<Producto> productoVarios() =>
      (select(productos)..where((p) => p.codigo.equals(codigoVarios))).getSingle();

  Future<Producto> productoEnvio() =>
      (select(productos)..where((p) => p.codigo.equals(codigoEnvio))).getSingle();

  Future<TurnoCaja?> turnoAbierto() => (select(turnosCaja)
        ..where((t) => t.cierre.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.apertura)])
        ..limit(1))
      .getSingleOrNull();

  /// Lo que debe el cliente, en centavos: cargos menos abonos y anulaciones.
  Future<int> deudaCliente(int clienteId) async {
    final fila = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE -monto END), 0) AS deuda '
      'FROM movimientos_fiado WHERE cliente_id = ?',
      variables: [Variable.withString(TipoMovFiado.cargo.name), Variable.withInt(clienteId)],
      readsFrom: {movimientosFiado},
    ).getSingle();
    return fila.read<int>('deuda');
  }

  /// Escribe un evento en la cola de salida. Llamar DENTRO de la transacción
  /// de la operación que lo genera (PRD: el evento va en la misma transacción).
  Future<String> encolarEvento(String tipo, Map<String, Object?> datos, DateTime fecha) async {
    final id = nuevoUuid();
    await into(eventosSalida).insert(EventosSalidaCompanion.insert(
      id: id,
      fecha: fecha,
      tipo: tipo,
      datos: jsonEncode(datos),
    ));
    return id;
  }

  Future<void> anotarBitacora({
    required int? usuarioId,
    required String accion,
    String? detalle,
    required DateTime fecha,
  }) =>
      into(bitacora).insert(BitacoraCompanion.insert(
        fecha: fecha,
        accion: accion,
        usuarioId: Value(usuarioId),
        detalle: Value(detalle),
      ));

  /// Para quien necesite el formato de fecha de los eventos.
  static String fechaEvento(DateTime f) => fechaLocalIso(f);
}
