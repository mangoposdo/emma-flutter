import '../db/database.dart';

/// Un renglón de la factura tal como lo leyó la nube. Cantidad en milésimas,
/// montos en centavos.
class LineaFacturaLeida {
  const LineaFacturaLeida({required this.descripcion, this.codigo, required this.cantidad, required this.costo, this.total});

  factory LineaFacturaLeida.fromJson(Map<String, Object?> j) => LineaFacturaLeida(
        descripcion: (_campo(j, 'descripcion') as String?) ?? '',
        codigo: _campo(j, 'codigo') as String?,
        cantidad: _milesimas(_campo(j, 'cantidad')) ?? 0,
        costo: _centavos(_campo(j, 'costo')) ?? 0,
        total: _centavos(_campo(j, 'total')),
      );

  final String descripcion;
  final String? codigo;
  final int cantidad;
  final int costo;
  final int? total;
}

/// Lo que la nube leyó de la foto de una factura de suplidor.
class FacturaLeida {
  const FacturaLeida({this.suplidor, this.factura, this.fecha, required this.lineas, this.total, this.nota});

  factory FacturaLeida.fromJson(Map<String, Object?> j) => FacturaLeida(
        suplidor: _campo(j, 'suplidor') as String?,
        factura: _campo(j, 'factura') as String?,
        fecha: _campo(j, 'fecha') as String?,
        lineas: [
          for (final l in (_campo(j, 'lineas') as List<Object?>?) ?? const [])
            LineaFacturaLeida.fromJson((l! as Map).cast<String, Object?>()),
        ],
        total: _centavos(_campo(j, 'total')),
        nota: _campo(j, 'nota') as String?,
      );

  final String? suplidor;
  final String? factura;
  final String? fecha;
  final List<LineaFacturaLeida> lineas;
  final int? total;
  final String? nota;
}

/// Un renglón leído con el producto de Emma que le toca. [seguro] es falso
/// cuando se adivinó por el nombre y conviene que el dueño lo mire; [producto]
/// es null cuando hay que escogerlo.
class LineaEmparejada {
  const LineaEmparejada(this.leida, this.producto, this.seguro);

  final LineaFacturaLeida leida;
  final Producto? producto;
  final bool seguro;
}

/// Busca qué producto de Emma es cada renglón de una factura leída (igual que la 0.7.1).
abstract final class Emparejador {
  static const minimoParecido = 0.6;

  static const _unidades = {
    'lbs': 'lb', 'libra': 'lb', 'libras': 'lb', //
    'lt': 'l', 'lts': 'l', 'litro': 'l', 'litros': 'l', 'ltr': 'l',
    'onza': 'oz', 'onzas': 'oz',
    'gr': 'g', 'grs': 'g', 'gramos': 'g',
    'unidades': 'und', 'unidad': 'und', 'un': 'und', 'uds': 'und',
  };

  static const _acentos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  /// "Arroz SELECTO 25Lbs." → "arroz selecto 25 lb".
  static String normalizar(String? texto) {
    if (texto == null || texto.trim().isEmpty) return '';
    final b = StringBuffer();
    for (final c in texto.toLowerCase().split('')) {
      b.write(_acentos[c] ?? c);
    }
    var s = b.toString().replaceAll(',', '.');
    s = s.replaceAll(RegExp(r'[^a-z0-9.]+'), ' ');
    s = s.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}');
    s = s.replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}');
    return s
        .split(' ')
        .map((p) => p.replaceAll(RegExp(r'^\.+|\.+$'), ''))
        .where((p) => p.isNotEmpty)
        .map((p) => _unidades[p] ?? p)
        .join(' ');
  }

  static bool _esNumero(String s) => s.isNotEmpty && s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

  /// Qué tanto se parecen dos nombres normalizados, de 0 a 1. Si los números
  /// (tamaños) no cuadran, casi nada.
  static double parecido(String a, String b) {
    final ta = a.split(' ').where((x) => x.isNotEmpty).toSet();
    final tb = b.split(' ').where((x) => x.isNotEmpty).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final na = ta.where(_esNumero).toSet();
    final nb = tb.where(_esNumero).toSet();
    if (na.isNotEmpty && nb.isNotEmpty && !(na.length == nb.length && na.containsAll(nb))) return 0.1;
    // Palabras cortadas en la factura ("sel" por "selecto") cuentan si una empieza como la otra.
    final comunes = ta
        .where((x) =>
            tb.contains(x) ||
            (x.length >= 3 && !_esNumero(x) && tb.any((y) => y.length >= 3 && (y.startsWith(x) || x.startsWith(y)))))
        .length;
    return 2.0 * comunes / (ta.length + tb.length);
  }

  /// [alias] son los ya aprendidos; [suplidorId] el suplidor de la factura, si se conoce.
  static List<LineaEmparejada> emparejar(
    FacturaLeida factura,
    List<Producto> productos, {
    List<AliasProducto> alias = const [],
    int? suplidorId,
  }) {
    final vendibles = productos.where((p) => p.activo && !esServicio(p)).toList();
    final porId = {for (final p in vendibles) p.id: p};
    final porCodigo = <String, Producto>{};
    for (final p in vendibles) {
      final c = p.codigo?.trim();
      if (c != null && c.isNotEmpty) porCodigo.putIfAbsent(c, () => p);
    }
    final nombres = [for (final p in vendibles) (p, normalizar(p.nombre))];

    final res = <LineaEmparejada>[];
    for (final l in factura.lineas) {
      final codigo = l.codigo?.trim();
      if (codigo != null && codigo.isNotEmpty && porCodigo[codigo] != null) {
        res.add(LineaEmparejada(l, porCodigo[codigo], true));
        continue;
      }
      final texto = normalizar(l.descripcion);
      // Lo que el dueño ya escogió antes: primero lo de este suplidor, después lo de cualquiera.
      final a = alias.where((x) => x.texto == texto && suplidorId != null && x.suplidorId == suplidorId).firstOrNull ??
          alias.where((x) => x.texto == texto).firstOrNull;
      if (a != null && porId[a.productoId] != null) {
        res.add(LineaEmparejada(l, porId[a.productoId], true));
        continue;
      }
      final exacto = nombres.where((n) => n.$2 == texto).firstOrNull;
      if (exacto != null) {
        res.add(LineaEmparejada(l, exacto.$1, true));
        continue;
      }
      (Producto, double)? mejor;
      for (final n in nombres) {
        final pts = parecido(texto, n.$2);
        if (mejor == null || pts > mejor.$2) mejor = (n.$1, pts);
      }
      res.add(mejor != null && mejor.$2 >= minimoParecido ? LineaEmparejada(l, mejor.$1, false) : LineaEmparejada(l, null, false));
    }
    return res;
  }
}

/// La web manda los campos en camelCase; se aceptan también en PascalCase.
Object? _campo(Map<String, Object?> j, String nombre) =>
    j[nombre] ?? j[nombre[0].toUpperCase() + nombre.substring(1)];

int? _centavos(Object? v) => v is num ? (v * 100).round() : null;

int? _milesimas(Object? v) => v is num ? (v * 1000).round() : null;
