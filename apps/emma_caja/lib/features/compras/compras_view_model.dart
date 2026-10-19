import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'preparar_factura.dart';

const _igual = Object();

/// Pregunta de sí o no que hace la pantalla.
typedef Preguntar = Future<bool> Function(String pregunta);

/// Pide el precio de venta de una línea (centavos), o null si cancelan.
typedef PedirPrecio = Future<int?> Function(LineaCompraVista linea, String nota);

/// "70", "70.5", "70.25": como se escribe un monto en la casilla.
String montoCorto(int centavos) {
  final signo = centavos < 0 ? '-' : '';
  final c = centavos.abs();
  final d = c % 100;
  if (d == 0) return '$signo${c ~/ 100}';
  return d % 10 == 0 ? '$signo${c ~/ 100}.${d ~/ 10}' : '$signo${c ~/ 100}.${d.toString().padLeft(2, '0')}';
}

int _centesimas(int milesimas) => milesimas < 0 ? -((-milesimas + 5) ~/ 10) : (milesimas + 5) ~/ 10;

/// Existencia con hasta dos decimales ("Hay 1.43"), como la búsqueda de la 0.7.
String cantidadCorta(int milesimas) => montoCorto(_centesimas(milesimas));

/// "ARROZ SELECTO 25LB" → "Arroz Selecto 25Lb", como el ToTitleCase de la 0.7.1.
String enTitulo(String texto) {
  final letra = RegExp(r'\p{L}', unicode: true);
  final dePalabra = RegExp(r"[\p{L}\p{N}\p{M}']", unicode: true);
  final b = StringBuffer();
  var enPalabra = false;
  for (final c in texto.trim().toLowerCase().split('')) {
    if (letra.hasMatch(c)) {
      b.write(enPalabra ? c : c.toUpperCase());
      enPalabra = true;
    } else {
      b.write(c);
      enPalabra = enPalabra && dePalabra.hasMatch(c);
    }
  }
  return b.toString();
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// "#12 · Distribuidora Corripio", en "Últimas compras".
String tituloCompra(CompraDetalle c) => '#${c.compra.id} · ${c.suplidor ?? 'Sin suplidor'}';

/// "17/10 07:42 PM · de la caja · fact. 4411".
String detalleCompra(CompraDetalle c) {
  final f = c.compra.fecha;
  return '${_dos(f.day)}/${_dos(f.month)} ${formatoHora(f)} · ${etiquetaPagoCompra(c.compra.pago)}'
      '${c.compra.factura != null ? ' · fact. ${c.compra.factura}' : ''}';
}

/// Un producto de la compra en pantalla. [producto] es como estaba al escogerlo.
class LineaCompraVista {
  const LineaCompraVista({
    required this.producto,
    required this.cantidad,
    required this.costo,
    this.precioNuevo,
    this.textoFactura,
    this.revisar = false,
  });

  final Producto producto;

  /// Milésimas.
  final int cantidad;

  /// Centavos por unidad o por libra.
  final int costo;

  /// Precio de venta nuevo; null deja el que tiene.
  final int? precioNuevo;

  /// Cómo salía en la factura leída; al guardar, Emma lo recuerda para ese suplidor.
  final String? textoFactura;

  /// Se escogió por parecido del nombre: el dueño debe mirar que sea el producto correcto.
  final bool revisar;

  String get nombre => producto.nombre;

  String get detalle => revisar
      ? 'En la factura: "$textoFactura" · revise que sea este producto (si no, quítelo y escoja otro)'
      : 'Había ${cantidadDe(producto, producto.existencia)} · costo anterior ${formatoMonto(producto.costo)}';

  String get cantidadTexto => cantidadDe(producto, cantidad);

  int get total => totalLinea(costo, cantidad);

  int get precio => precioNuevo ?? producto.precio;

  String get precioTexto => '${formatoMonto(precio)}${precioNuevo != null ? ' (nuevo)' : ''}';

  /// "+26%": lo que deja sobre el precio, redondeado.
  String get ganancia {
    if (precio <= 0) return '';
    final n = (precio - costo) * 100;
    final r = (n.abs() * 2 + precio) ~/ (2 * precio);
    return '${n < 0 && r > 0 ? '-' : '+'}$r%';
  }

  bool get dejaGanancia => precio > costo;

  LineaCompraVista copyWith({int? cantidad, Object? precioNuevo = _igual, String? textoFactura}) => LineaCompraVista(
        producto: producto,
        cantidad: cantidad ?? this.cantidad,
        costo: costo,
        precioNuevo: identical(precioNuevo, _igual) ? this.precioNuevo : precioNuevo as int?,
        textoFactura: textoFactura ?? this.textoFactura,
        revisar: revisar,
      );
}

class ComprasEstado {
  const ComprasEstado({
    this.suplidores = const [],
    this.recientes = const [],
    this.suplidor = '',
    this.factura = '',
    this.pago = PagoCompra.deLaCaja,
    this.lineas = const [],
    this.escogida,
    this.pendiente,
    this.cantidadPendiente = 0,
    this.porLibra = false,
    this.seleccion = 0,
    this.cantidadInicial = '',
    this.costoInicial = '',
    this.busqueda,
    this.textoCodigo,
    this.pedidoCodigo = 0,
    this.aviso = '',
    this.guardando = false,
    this.leyendo = false,
    this.leida,
    this.porEmparejar = const [],
    this.leidasEnTotal = 0,
  });

  /// Los nombres de los suplidores guardados, para las sugerencias.
  final List<String> suplidores;
  final List<CompraDetalle> recientes;
  final String suplidor;
  final String factura;
  final PagoCompra pago;
  final List<LineaCompraVista> lineas;
  final int? escogida;

  /// El producto escogido al que le falta la cantidad y el costo.
  final Producto? pendiente;

  /// Milésimas, ya confirmadas con Enter.
  final int cantidadPendiente;

  /// Si el último producto escogido se vende por libra (los rótulos se quedan así).
  final bool porLibra;

  /// Sube cada vez que se escoge un producto: la pantalla llena la cantidad y el costo.
  final int seleccion;
  final String cantidadInicial;
  final String costoInicial;

  /// Resultados de la búsqueda por nombre; null = cerrada.
  final List<Producto>? busqueda;

  /// Sube cuando la casilla de escanear debe recuperar el foco con todo
  /// marcado; si [textoCodigo] no es null, antes se le pone ese texto.
  final int pedidoCodigo;
  final String? textoCodigo;

  /// El aviso verde de la derecha.
  final String aviso;
  final bool guardando;

  /// Leyendo una factura en la nube.
  final bool leyendo;

  /// El renglón de la factura leída al que falta decirle qué producto es.
  final LineaFacturaLeida? leida;
  final List<LineaFacturaLeida> porEmparejar;
  final int leidasEnTotal;

  int get total => lineas.fold(0, (a, l) => a + l.total);

  String get resumen => switch (lineas.length) {
        0 => 'Sin productos',
        1 => '1 producto',
        final n => '$n productos',
      };

  String get seleccionado {
    final p = pendiente;
    if (p == null) return ' ';
    return '${p.nombre}   ·   Hay ${cantidadDe(p, p.existencia)}   ·   Costo anterior ${formatoRD(p.costo)}'
        '   ·   Se vende a ${formatoRD(p.precio)}';
  }

  String get rotuloCantidad => porLibra ? 'LIBRAS' : 'CANTIDAD';
  String get rotuloCosto => porLibra ? 'COSTO LA LIBRA' : 'COSTO C/U';

  String get cuentaEmparejar => 'DE LA FACTURA · ${leidasEnTotal - porEmparejar.length} DE $leidasEnTotal POR ESCOGER';

  String get lineaEmparejar {
    final l = leida;
    if (l == null) return '';
    return '${l.descripcion}   ·   ${formatoMonto(_centesimas(l.cantidad))} × ${formatoRD(l.costo)}';
  }

  ComprasEstado copyWith({
    List<String>? suplidores,
    List<CompraDetalle>? recientes,
    String? suplidor,
    String? factura,
    PagoCompra? pago,
    List<LineaCompraVista>? lineas,
    Object? escogida = _igual,
    Object? pendiente = _igual,
    int? cantidadPendiente,
    bool? porLibra,
    int? seleccion,
    String? cantidadInicial,
    String? costoInicial,
    Object? busqueda = _igual,
    Object? textoCodigo = _igual,
    int? pedidoCodigo,
    String? aviso,
    bool? guardando,
    bool? leyendo,
    Object? leida = _igual,
    List<LineaFacturaLeida>? porEmparejar,
    int? leidasEnTotal,
  }) =>
      ComprasEstado(
        suplidores: suplidores ?? this.suplidores,
        recientes: recientes ?? this.recientes,
        suplidor: suplidor ?? this.suplidor,
        factura: factura ?? this.factura,
        pago: pago ?? this.pago,
        lineas: lineas ?? this.lineas,
        escogida: identical(escogida, _igual) ? this.escogida : escogida as int?,
        pendiente: identical(pendiente, _igual) ? this.pendiente : pendiente as Producto?,
        cantidadPendiente: cantidadPendiente ?? this.cantidadPendiente,
        porLibra: porLibra ?? this.porLibra,
        seleccion: seleccion ?? this.seleccion,
        cantidadInicial: cantidadInicial ?? this.cantidadInicial,
        costoInicial: costoInicial ?? this.costoInicial,
        busqueda: identical(busqueda, _igual) ? this.busqueda : busqueda as List<Producto>?,
        textoCodigo: identical(textoCodigo, _igual) ? this.textoCodigo : textoCodigo as String?,
        pedidoCodigo: pedidoCodigo ?? this.pedidoCodigo,
        aviso: aviso ?? this.aviso,
        guardando: guardando ?? this.guardando,
        leyendo: leyendo ?? this.leyendo,
        leida: identical(leida, _igual) ? this.leida : leida as LineaFacturaLeida?,
        porEmparejar: porEmparejar ?? this.porEmparejar,
        leidasEnTotal: leidasEnTotal ?? this.leidasEnTotal,
      );
}

final comprasViewModelProvider = NotifierProvider.autoDispose<ComprasViewModel, ComprasEstado>(ComprasViewModel.new);

/// Registro de compras con el mismo ritmo que la venta: escanear, Enter,
/// cantidad, Enter, costo, Enter. O leer la factura de una foto y revisarla.
class ComprasViewModel extends Notifier<ComprasEstado> {
  /// Termina cuando están cargados los suplidores y las últimas compras.
  late Future<void> listo;

  CompraService get _compras => ref.read(compraServiceProvider);
  ProductoService get _productos => ref.read(productoServiceProvider);

  @override
  ComprasEstado build() {
    listo = _cargarListas();
    return const ComprasEstado();
  }

  Future<void> _cargarListas() async {
    final compras = _compras;
    final suplidores = await compras.suplidores();
    final recientes = await compras.recientes(cuantas: 50);
    if (!ref.mounted) return;
    state = state.copyWith(suplidores: [for (final s in suplidores) s.nombre], recientes: recientes);
  }

  void _marcarCodigo([String? texto]) =>
      state = state.copyWith(textoCodigo: texto, pedidoCodigo: state.pedidoCodigo + 1);

  // ---------- Escanear, cantidad, costo ----------

  /// Enter en la casilla de escanear. Un código de barras nuevo (6 o más
  /// dígitos) se ofrece crear con [crear]. Devuelve el mensaje para mostrar
  /// si no se encontró nada.
  Future<String?> escanear(String texto, {required Future<Producto?> Function(String codigo) crear}) async {
    final t = texto.trim();
    if (t.isEmpty) return null;
    final productos = _productos;
    final porCodigo = await productos.porCodigo(t);
    if (!ref.mounted) return null;
    if (porCodigo != null) {
      _seleccionar(porCodigo);
      return null;
    }
    final encontrados = await productos.buscar(t, limite: 500);
    if (!ref.mounted) return null;
    if (encontrados.length == 1) {
      _seleccionar(encontrados.first);
    } else if (encontrados.length > 1) {
      state = state.copyWith(busqueda: encontrados);
    } else if (t.length >= 6 && RegExp(r'^\d+$').hasMatch(t)) {
      // Mercancía nueva: se crea aquí mismo y sigue la compra.
      final creado = await crear(t) == null || !ref.mounted ? null : await productos.porCodigo(t);
      if (!ref.mounted) return null;
      if (creado == null) {
        _marcarCodigo();
      } else {
        _seleccionar(creado);
      }
    } else {
      return 'No se encontró "$t". Si es nuevo, créelo en Productos o escanee su código.';
    }
    return null;
  }

  void cerrarBusqueda() {
    state = state.copyWith(busqueda: null);
    _marcarCodigo();
  }

  /// Escogido de la lista de búsqueda.
  void elegir(Producto p) {
    cerrarBusqueda();
    _seleccionar(p);
  }

  void _seleccionar(Producto p) {
    // Si viene de la factura leída, la cantidad y el costo ya están: solo hay que confirmar con Enter.
    final l = state.leida;
    state = state.copyWith(
      pendiente: p,
      cantidadPendiente: 0,
      busqueda: null,
      porLibra: p.unidad == UnidadVenta.libra,
      seleccion: state.seleccion + 1,
      cantidadInicial: l == null ? '' : formatoCantidad(l.cantidad),
      costoInicial: l != null ? montoCorto(l.costo) : (p.costo > 0 ? montoCorto(p.costo) : ''),
    );
  }

  /// Suelta el producto a medias y vacía la casilla de escanear.
  void limpiarPendiente() {
    state = state.copyWith(pendiente: null, cantidadPendiente: 0);
    _marcarCodigo('');
  }

  /// Enter en la cantidad. Devuelve el mensaje si no sirve.
  String? cantidad(String texto) {
    final p = state.pendiente;
    if (p == null) return null;
    final c = parsearCantidad(texto);
    if (c == null || c <= 0) return 'Escriba cuántos llegaron.';
    if (p.unidad == UnidadVenta.unidad && c % milesimasPorUnidad != 0) {
      return '${p.nombre} se cuenta por unidad; escriba un número entero.';
    }
    state = state.copyWith(cantidadPendiente: c);
    return null;
  }

  /// Enter en el costo: agrega la línea (o la suma a la del mismo producto y
  /// costo). Si así no deja ganancia, pide el precio nuevo con [pedirPrecio].
  /// Devuelve el mensaje si el costo no sirve.
  Future<String?> costo(String texto, {required PedirPrecio pedirPrecio}) async {
    final p = state.pendiente;
    final cantidad = state.cantidadPendiente;
    if (p == null || cantidad <= 0) return null;
    final costo = parsearMonto(texto);
    if (costo == null) return 'Escriba a cuánto le salió cada uno.';
    limpiarPendiente();
    final (lineas, i) = _agregar(state.lineas, p, cantidad, costo, state.leida?.descripcion, revisar: false);
    state = state.copyWith(lineas: lineas, escogida: i, aviso: '');

    final l = lineas[i];
    if (l.precio <= l.costo && l.costo > 0) {
      await _pedirPrecio(i, pedirPrecio,
          'Ahora le cuesta ${formatoRD(l.costo)} y se vende a ${formatoRD(l.precio)}: no deja ganancia.');
      if (!ref.mounted) return null;
    }
    if (state.leida != null) await _siguiente();
    return null;
  }

  (List<LineaCompraVista>, int) _agregar(
    List<LineaCompraVista> lineas,
    Producto p,
    int cantidad,
    int costo,
    String? textoFactura, {
    required bool revisar,
  }) {
    final i = lineas.indexWhere((l) => l.producto.id == p.id && l.costo == costo);
    if (i >= 0) {
      final l = lineas[i];
      return (
        [...lineas]..[i] = l.copyWith(cantidad: l.cantidad + cantidad, textoFactura: l.textoFactura ?? textoFactura),
        i
      );
    }
    final nueva =
        LineaCompraVista(producto: p, cantidad: cantidad, costo: costo, textoFactura: textoFactura, revisar: revisar);
    return ([...lineas, nueva], lineas.length);
  }

  Future<void> _pedirPrecio(int i, PedirPrecio pedir, String nota) async {
    final precio = await pedir(state.lineas[i], nota);
    if (precio == null || !ref.mounted || i >= state.lineas.length) return;
    final l = state.lineas[i];
    state = state.copyWith(
      lineas: [...state.lineas]..[i] = l.copyWith(precioNuevo: precio == l.producto.precio ? null : precio),
    );
  }

  /// El botón "Se vende a" de una línea.
  Future<void> precio(int i, {required PedirPrecio pedirPrecio}) async {
    if (i < 0 || i >= state.lineas.length) return;
    final l = state.lineas[i];
    await _pedirPrecio(i, pedirPrecio, 'Costo ${formatoRD(l.costo)}. El precio nuevo se guarda junto con la compra.');
  }

  void escogerLinea(int i) {
    if (i >= 0 && i < state.lineas.length) state = state.copyWith(escogida: i);
  }

  void quitar(int i) {
    if (i < 0 || i >= state.lineas.length) return;
    state = state.copyWith(lineas: [...state.lineas]..removeAt(i), escogida: null);
  }

  void pago(PagoCompra p) => state = state.copyWith(pago: p);

  void escribirSuplidor(String t) {
    if (t != state.suplidor) state = state.copyWith(suplidor: t);
  }

  void escribirFactura(String t) {
    if (t != state.factura) state = state.copyWith(factura: t);
  }

  // ---------- Leer la factura de una foto ----------

  /// "Leer factura (foto)": [escoger] devuelve la ruta del archivo o null.
  /// Devuelve el mensaje para mostrar si algo no salió.
  Future<String?> leerFactura({required Preguntar preguntar, required Future<String?> Function() escoger}) async {
    if (state.leyendo) return null;
    if (state.pendiente != null) limpiarPendiente();
    if (state.lineas.isNotEmpty &&
        !await preguntar('Ya hay productos en esta compra. ¿Leer la factura y agregarlos a los que ya están?')) {
      return null;
    }
    final ruta = await escoger();
    if (ruta == null || !ref.mounted) return null;

    // El botón se apaga desde que se prepara la foto: así no se lee dos veces.
    state = state.copyWith(leyendo: true);
    final FacturaLeida factura;
    try {
      final (archivo, tipo) = await prepararFactura(ruta);
      if (!ref.mounted) return null;
      factura = await ref.read(nubeServiceProvider).leerFactura(ref.sesion, archivo, tipo);
    } on EmmaError catch (e) {
      return e.mensaje;
    } finally {
      if (ref.mounted) state = state.copyWith(leyendo: false);
    }
    if (!ref.mounted) return null;
    return llenarDeFactura(factura);
  }

  /// Llena la compra con lo que se leyó: lo que se sabe qué producto es entra
  /// de una vez; lo demás queda en cola para escogerlo. Devuelve el mensaje si
  /// la factura no trae productos.
  Future<String?> llenarDeFactura(FacturaLeida f) async {
    final nota = f.nota?.trim() ?? '';
    if (f.lineas.isEmpty) {
      return 'No se encontraron productos en esa foto.${nota.isEmpty ? '' : '\n\n${f.nota}'}'
          '\n\nPruebe con una foto más clara, de frente y con buena luz.';
    }
    final compras = _compras;
    var suplidor = state.suplidor;
    final nombre = f.suplidor?.trim() ?? '';
    if (nombre.isNotEmpty && suplidor.trim().isEmpty) {
      final guardados = await compras.suplidores();
      suplidor = guardados.where((s) => s.nombre.toLowerCase() == nombre.toLowerCase()).firstOrNull?.nombre ?? nombre;
    }
    var factura = state.factura;
    final numero = f.factura?.trim() ?? '';
    if (numero.isNotEmpty && factura.isEmpty) factura = numero;

    final emparejadas = await compras.emparejar(f);
    if (!ref.mounted) return null;
    final cola = <LineaFacturaLeida>[];
    var lineas = state.lineas;
    var directos = 0;
    var aRevisar = 0;
    for (final e in emparejadas) {
      final p = e.producto;
      final l = e.leida;
      final cantidadMala = p != null && p.unidad == UnidadVenta.unidad && l.cantidad % milesimasPorUnidad != 0;
      if (p == null || l.cantidad <= 0 || l.costo < 0 || cantidadMala) {
        cola.add(l);
        continue;
      }
      (lineas, _) = _agregar(lineas, p, l.cantidad, l.costo, l.descripcion, revisar: !e.seguro);
      directos++;
      if (!e.seguro) aRevisar++;
    }

    var aviso = 'Factura leída: $directos de ${f.lineas.length} productos ya están en la compra.';
    if (aRevisar > 0) aviso += ' Revise los $aRevisar marcados en amarillo.';
    if (cola.isNotEmpty) aviso += ' Falta decir cuál producto es en ${cola.length}.';
    final suma = lineas.fold(0, (a, l) => a + l.total);
    final total = f.total;
    if (total != null && cola.isEmpty && (total - suma).abs() > 100) {
      aviso += ' Ojo: la factura dice ${formatoRD(total)} y la suma da ${formatoRD(suma)}.';
    }
    if (nota.isNotEmpty) aviso += ' Nota: ${f.nota}';
    state = state.copyWith(
      suplidor: suplidor,
      factura: factura,
      lineas: lineas,
      porEmparejar: cola,
      leidasEnTotal: cola.length,
      aviso: aviso,
    );
    await _siguiente();
    return null;
  }

  /// Pasa al próximo renglón por escoger y, de ayuda, busca por su primera palabra.
  Future<void> _siguiente() async {
    final cola = state.porEmparejar;
    if (cola.isEmpty) {
      state = state.copyWith(leida: null);
      return;
    }
    final leida = cola.first;
    final palabra = leida.descripcion.split(' ').where((w) => w.length >= 3).firstOrNull ?? '';
    final encontrados = palabra.isEmpty ? const <Producto>[] : await _productos.buscar(palabra, limite: 500);
    if (!ref.mounted) return;
    state =
        state.copyWith(leida: leida, porEmparejar: cola.sublist(1), busqueda: encontrados.isEmpty ? null : encontrados);
    _marcarCodigo(palabra);
  }

  /// "Crear producto" del renglón por escoger: [crear] abre el formulario con
  /// el código, el nombre y el costo de la factura y devuelve lo guardado.
  Future<void> crearDeFactura(
      {required Future<Producto?> Function(String? codigo, String nombre, int costo) crear}) async {
    final l = state.leida;
    if (l == null) return;
    if (state.pendiente != null) limpiarPendiente();
    cerrarBusqueda();
    final codigo = l.codigo?.trim();
    final guardado = await crear(codigo == null || codigo.isEmpty ? null : codigo, enTitulo(l.descripcion), l.costo);
    if (guardado == null || !ref.mounted) return;
    final productos = _productos;
    var creado = guardado.codigo != null ? await productos.porCodigo(guardado.codigo!) : null;
    if (creado == null) {
      final mismos = (await productos.buscar(guardado.nombre, limite: 500)).where((p) => p.nombre == guardado.nombre);
      creado = mismos.isEmpty ? null : mismos.reduce((a, b) => b.id > a.id ? b : a);
    }
    if (creado != null && ref.mounted) _seleccionar(creado);
  }

  /// "Saltar": este renglón no entra en la compra.
  Future<void> saltarDeFactura() async {
    if (state.pendiente != null) limpiarPendiente();
    cerrarBusqueda();
    await _siguiente();
  }

  // ---------- Guardar ----------

  /// GUARDAR COMPRA (F10). Devuelve el mensaje para mostrar si no se pudo.
  Future<String?> guardar({required Preguntar preguntar}) async {
    final s = state;
    if (s.guardando) return null;
    if (s.pendiente != null) {
      return 'Termine el producto que está escribiendo (cantidad y costo con Enter) o pulse Esc.';
    }
    if (s.lineas.isEmpty) return null;
    if (s.leida != null &&
        !await preguntar('Todavía faltan ${s.porEmparejar.length + 1} renglones de la factura por escoger. '
            '¿Guardar la compra sin ellos?')) {
      return null;
    }
    if (!ref.mounted) return null;
    state = state.copyWith(guardando: true);
    final compras = _compras;
    final Compra compra;
    try {
      compra = await compras.registrar(
        ref.sesion,
        SolicitudCompra(
          suplidor: s.suplidor,
          factura: s.factura,
          pago: s.pago,
          lineas: [
            for (final l in s.lineas)
              LineaCompra(
                productoId: l.producto.id,
                cantidad: l.cantidad,
                costo: l.costo,
                precio: l.precioNuevo,
                textoFactura: l.textoFactura,
              ),
          ],
        ),
      );
    } on EmmaError catch (e) {
      if (ref.mounted) state = state.copyWith(guardando: false);
      return e.mensaje;
    }
    if (!ref.mounted) return null;
    // La barra del menú: si salió de la caja, y lo que falta por subir a la nube.
    refrescarEstado(ref);
    final suplidores = await compras.suplidores();
    final recientes = await compras.recientes(cuantas: 50);
    if (!ref.mounted) return null;
    state = state.copyWith(
      guardando: false,
      aviso: 'Compra #${compra.id} guardada: ${formatoRD(compra.total)}.'
          '${compra.pago == PagoCompra.deLaCaja ? ' Se sacó de la caja.' : ''}',
      lineas: const [],
      escogida: null,
      leida: null,
      porEmparejar: const [],
      factura: '',
      suplidor: '',
      suplidores: [for (final x in suplidores) x.nombre],
      recientes: recientes,
      pago: PagoCompra.deLaCaja,
    );
    return null;
  }

  /// Vaciar (Esc): pregunta si hay productos.
  Future<void> vaciar({required Preguntar preguntar}) async {
    if (state.pendiente != null) limpiarPendiente();
    if (state.lineas.isNotEmpty && !await preguntar('¿Vaciar esta compra sin guardarla?')) return;
    if (!ref.mounted) return;
    state = state.copyWith(lineas: const [], escogida: null, leida: null, porEmparejar: const []);
  }
}
