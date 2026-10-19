import 'package:drift/drift.dart';

import '../db/database.dart';
import '../dinero.dart';
import '../errores.dart';
import '../nube/eventos.dart';
import '../sesion.dart';

/// Lo que se escribe en el formulario de un cliente. [id] null = nuevo.
class DatosCliente {
  const DatosCliente({
    this.id,
    required this.nombre,
    this.telefono,
    this.direccion,
    this.sector,
    this.referencia,
    this.correo,
    this.cumpleanos,
    this.cedula,
    this.notas,
    this.limiteCredito = 0,
    this.esFijo = true,
    this.activo = true,
  });

  final int? id;
  final String nombre;
  final String? telefono;
  final String? direccion;
  final String? sector;
  final String? referencia;
  final String? correo;

  /// "dd/MM".
  final String? cumpleanos;
  final String? cedula;
  final String? notas;

  /// Centavos. 0 = sin límite.
  final int limiteCredito;
  final bool esFijo;
  final bool activo;

  factory DatosCliente.de(Cliente c) => DatosCliente(
        id: c.id,
        nombre: c.nombre,
        telefono: c.telefono,
        direccion: c.direccion,
        sector: c.sector,
        referencia: c.referencia,
        correo: c.correo,
        cumpleanos: c.cumpleanos,
        cedula: c.cedula,
        notas: c.notas,
        limiteCredito: c.limiteCredito,
        esFijo: c.esFijo,
        activo: c.activo,
      );
}

/// Un cliente que debe.
class DeudaCliente {
  const DeudaCliente({required this.cliente, required this.debe, this.ultimoAbono, this.ultimoCargo});

  final Cliente cliente;

  /// Centavos.
  final int debe;
  final DateTime? ultimoAbono;
  final DateTime? ultimoCargo;

  /// Días desde el último abono (o desde el último fiado si nunca ha abonado).
  int? diasSinPagar(DateTime hoy) {
    final f = ultimoAbono ?? ultimoCargo;
    if (f == null || debe <= 0) return null;
    return DateTime(hoy.year, hoy.month, hoy.day).difference(DateTime(f.year, f.month, f.day)).inDays;
  }
}

class LineaEstadoCuenta {
  const LineaEstadoCuenta({
    required this.fecha,
    required this.concepto,
    required this.cargo,
    required this.abono,
    required this.balance,
  });

  final DateTime fecha;
  final String concepto;

  /// Centavos.
  final int cargo;
  final int abono;
  final int balance;
}

/// Clientes, fiado y abonos.
class FiadoService {
  FiadoService(this.db, {Reloj? reloj}) : _reloj = reloj ?? db.reloj;

  final EmmaDatabase db;
  final Reloj _reloj;

  /// Lo que debe el cliente, en centavos.
  Future<int> balance(int clienteId) => db.deudaCliente(clienteId);

  Future<Cliente?> porId(int id) => (db.select(db.clientes)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Por nombre o teléfono; los fijos primero.
  Future<List<Cliente>> clientes({String texto = '', bool incluirInactivos = false}) {
    final t = texto.trim().replaceAll(RegExp('[%_]'), '');
    final q = db.select(db.clientes);
    q.where((c) {
      Expression<bool> f = incluirInactivos ? const Constant(true) : c.activo.equals(true);
      if (t.isNotEmpty) f = f & (c.nombre.like('%$t%') | c.telefono.like('%$t%'));
      return f;
    });
    q.orderBy([(c) => OrderingTerm.desc(c.esFijo), (c) => OrderingTerm.asc(c.nombre)]);
    return q.get();
  }

  /// Crea o modifica un cliente. Dar o cambiar el límite de crédito es solo del dueño.
  Future<Cliente> guardarCliente(Sesion sesion, DatosCliente d) async {
    final nombre = d.nombre.trim();
    if (nombre.isEmpty) throw const DatoInvalido('El cliente necesita un nombre.');
    if (d.limiteCredito < 0) throw const DatoInvalido('El límite no puede ser negativo.');
    final cumple = _limpio(d.cumpleanos);
    if (cumple != null && !_cumpleValido(cumple)) {
      throw const DatoInvalido('Cumpleaños: escriba día/mes, por ejemplo 15/08.');
    }
    final fecha = _reloj();

    return db.transaction(() async {
      final datos = ClientesCompanion(
        nombre: Value(nombre),
        telefono: Value(_limpio(d.telefono)),
        direccion: Value(_limpio(d.direccion)),
        sector: Value(_limpio(d.sector)),
        referencia: Value(_limpio(d.referencia)),
        correo: Value(_limpio(d.correo)),
        cumpleanos: Value(cumple == null ? null : _normalizarCumple(cumple)),
        cedula: Value(_limpio(d.cedula)),
        notas: Value(_limpio(d.notas)),
        limiteCredito: Value(d.limiteCredito),
        esFijo: Value(d.esFijo),
        activo: Value(d.activo),
      );
      if (d.id == null) {
        if (d.limiteCredito > 0) requiereDueno(sesion.esDueno, 'dar límite de crédito');
        final id = await db.into(db.clientes).insert(datos.copyWith(creado: Value(fecha)));
        return (await porId(id))!;
      }
      final antes = await porId(d.id!);
      if (antes == null) throw const DatoInvalido('El cliente no existe.');
      if (antes.limiteCredito != d.limiteCredito) {
        requiereDueno(sesion.esDueno, 'cambiar el límite de crédito');
        await db.anotarBitacora(
          usuarioId: sesion.usuarioId,
          accion: 'Cambio de límite',
          detalle: '${antes.nombre}: ${formatoRD(antes.limiteCredito)} -> ${formatoRD(d.limiteCredito)}',
          fecha: fecha,
        );
      }
      await (db.update(db.clientes)..where((c) => c.id.equals(d.id!))).write(datos);
      return (await porId(d.id!))!;
    });
  }

  /// Pago del cliente. Necesita la caja abierta porque el dinero entra a la caja.
  Future<MovimientoFiado> abonar(
    Sesion sesion,
    int clienteId,
    int monto, {
    FormaPago forma = FormaPago.efectivo,
    String? nota,
  }) async {
    if (monto <= 0) throw const DatoInvalido('El abono debe ser mayor que cero.');
    if (forma == FormaPago.fiado) throw const DatoInvalido('Un abono no se puede pagar con fiado.');
    final fecha = _reloj();
    return db.transaction(() async {
      final turno = await db.turnoAbierto();
      if (turno == null) throw const CajaCerrada('La caja está cerrada. Abra la caja para continuar.');
      final cliente = await porId(clienteId);
      if (cliente == null) throw const DatoInvalido('El cliente no existe.');
      final deuda = await db.deudaCliente(clienteId);
      if (monto > deuda) throw DatoInvalido('${cliente.nombre} solo debe ${formatoRD(deuda)}.');
      final id = await db.into(db.movimientosFiado).insert(MovimientosFiadoCompanion.insert(
            clienteId: clienteId,
            fecha: fecha,
            tipo: TipoMovFiado.abono,
            monto: monto,
            turnoCajaId: Value(turno.id),
            formaPagoAbono: Value(forma),
            usuarioId: Value(sesion.usuarioId),
            nota: Value(_limpio(nota)),
          ));
      await db.encolarEvento(TipoEvento.fiadoAbono, {
        'ClienteId': clienteId,
        'Cliente': cliente.nombre,
        'Monto': montoJson(monto),
        'Forma': forma.etiqueta,
        'Fecha': fechaLocalIso(fecha),
      }, fecha);
      return (db.select(db.movimientosFiado)..where((m) => m.id.equals(id))).getSingle();
    });
  }

  Future<List<LineaEstadoCuenta>> estadoCuenta(int clienteId) async {
    final movs = await (db.select(db.movimientosFiado)
          ..where((f) => f.clienteId.equals(clienteId))
          ..orderBy([(f) => OrderingTerm.asc(f.id)]))
        .get();
    var balance = 0;
    final res = <LineaEstadoCuenta>[];
    for (final m in movs) {
      final suma = m.tipo == TipoMovFiado.cargo;
      balance += suma ? m.monto : -m.monto;
      final nota = _limpio(m.nota);
      final concepto = switch (m.tipo) {
            TipoMovFiado.cargo => 'Compra #${m.ventaId}',
            TipoMovFiado.abono => 'Abono${m.formaPagoAbono != null && m.formaPagoAbono != FormaPago.efectivo ? ' (${m.formaPagoAbono!.etiqueta})' : ''}',
            TipoMovFiado.anulacionCargo => 'Anulación compra #${m.ventaId}',
          } +
          (nota == null || m.tipo == TipoMovFiado.anulacionCargo ? '' : ' - $nota');
      res.add(LineaEstadoCuenta(
        fecha: m.fecha,
        concepto: concepto,
        cargo: suma ? m.monto : 0,
        abono: suma ? 0 : m.monto,
        balance: balance,
      ));
    }
    return res;
  }

  /// Todos los clientes que deben, de mayor a menor deuda.
  Future<List<DeudaCliente>> deudores() async {
    final movs = await db.select(db.movimientosFiado).get();
    final clientes = {for (final c in await db.select(db.clientes).get()) c.id: c};
    final porCliente = <int, List<MovimientoFiado>>{};
    for (final m in movs) {
      porCliente.putIfAbsent(m.clienteId, () => []).add(m);
    }
    final res = <DeudaCliente>[];
    for (final e in porCliente.entries) {
      final debe = e.value.fold<int>(0, (s, m) => s + (m.tipo == TipoMovFiado.cargo ? m.monto : -m.monto));
      if (debe <= 0) continue;
      DateTime? ultima(TipoMovFiado t) => e.value
          .where((m) => m.tipo == t)
          .map((m) => m.fecha)
          .fold<DateTime?>(null, (a, f) => a == null || f.isAfter(a) ? f : a);
      res.add(DeudaCliente(
        cliente: clientes[e.key]!,
        debe: debe,
        ultimoAbono: ultima(TipoMovFiado.abono),
        ultimoCargo: ultima(TipoMovFiado.cargo),
      ));
    }
    res.sort((a, b) => b.debe.compareTo(a.debe));
    return res;
  }

  Future<int> totalEnLaCalle() async => (await deudores()).fold<int>(0, (s, d) => s + d.debe);

  static bool _cumpleValido(String t) {
    final partes = t.split(RegExp(r'[/\-. ]'));
    if (partes.length < 2) return false;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    if (dia == null || mes == null || mes < 1 || mes > 12 || dia < 1) return false;
    const diasMes = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return dia <= diasMes[mes - 1];
  }

  static String _normalizarCumple(String t) {
    final partes = t.split(RegExp(r'[/\-. ]'));
    return '${partes[0].padLeft(2, '0')}/${partes[1].padLeft(2, '0')}';
  }

  static String? _limpio(String? t) {
    final x = t?.trim();
    return (x == null || x.isEmpty) ? null : x;
  }
}
