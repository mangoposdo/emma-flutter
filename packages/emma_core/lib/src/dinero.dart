/// Dinero y cantidades sin `double`.
///
/// * Montos: enteros en centavos. RD$ 1,234.50 = 123450.
/// * Cantidades y existencias: enteros en milésimas. 1 unidad = 1000,
///   media libra = 500.
library;

const int milesimasPorUnidad = 1000;

/// "1,234.50" (sin símbolo). Negativos: "-1,234.50".
String formatoMonto(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final entero = (abs ~/ 100).toString();
  final cent = (abs % 100).toString().padLeft(2, '0');
  final grupos = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) grupos.write(',');
    grupos.write(entero[i]);
  }
  return '${negativo ? '-' : ''}$grupos.$cent';
}

/// "RD$ 1,234.50".
String formatoRD(int centavos) => 'RD\$ ${formatoMonto(centavos)}';

final _reMonto = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');
final _reCantidad = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$');

/// Lee "1,234.50", "50", "$50", "RD$ 50.5". Devuelve centavos o null si no es un monto.
int? parsearMonto(String texto) {
  final limpio = texto
      .trim()
      .replaceAll(RegExp(r'^RD\$', caseSensitive: false), '')
      .replaceAll(r'$', '')
      .replaceAll(',', '')
      .replaceAll(' ', '');
  final m = _reMonto.firstMatch(limpio);
  if (m == null) return null;
  final entero = int.parse(m.group(1)!);
  final dec = (m.group(2) ?? '').padRight(2, '0');
  return entero * 100 + int.parse(dec);
}

/// Lee "3", "0.5", "1.25". Devuelve milésimas o null.
int? parsearCantidad(String texto) {
  final m = _reCantidad.firstMatch(texto.trim());
  if (m == null) return null;
  final entero = int.parse(m.group(1)!);
  final dec = (m.group(2) ?? '').padRight(3, '0');
  return entero * milesimasPorUnidad + int.parse(dec);
}

/// "3", "0.5", "1.429".
String formatoCantidad(int milesimas) {
  final negativo = milesimas < 0;
  final abs = milesimas.abs();
  final entero = abs ~/ milesimasPorUnidad;
  var dec = (abs % milesimasPorUnidad).toString().padLeft(3, '0');
  while (dec.endsWith('0')) {
    dec = dec.substring(0, dec.length - 1);
  }
  return '${negativo ? '-' : ''}$entero${dec.isEmpty ? '' : '.$dec'}';
}

/// Total de una línea: precio (centavos por unidad o por libra) por cantidad
/// (milésimas), redondeado al centavo (la mitad sube).
int totalLinea(int precioCentavos, int cantidadMilesimas) {
  final p = precioCentavos * cantidadMilesimas;
  if (p >= 0) return (p + 500) ~/ 1000;
  return -((-p + 500) ~/ 1000);
}

/// Cantidad (milésimas) que corresponde a un monto en un producto por libra.
/// Ej.: RD$ 50 de arroz a RD$ 35 la libra = 1.429 lb.
int cantidadPorMonto(int montoCentavos, int precioCentavos) {
  if (precioCentavos <= 0) {
    throw ArgumentError.value(precioCentavos, 'precioCentavos', 'debe ser mayor que cero');
  }
  return (montoCentavos * milesimasPorUnidad + precioCentavos ~/ 2) ~/ precioCentavos;
}

/// Solo para el JSON que va a la nube (que espera números decimales).
/// Un monto de 2 decimales se convierte sin pérdida mientras sea menor
/// que 90 billones de pesos. Nunca usar para cálculos.
num montoJson(int centavos) => centavos % 100 == 0 ? centavos ~/ 100 : centavos / 100;

/// Igual que [montoJson] para cantidades en milésimas.
num cantidadJson(int milesimas) => milesimas % milesimasPorUnidad == 0
    ? milesimas ~/ milesimasPorUnidad
    : milesimas / milesimasPorUnidad;
