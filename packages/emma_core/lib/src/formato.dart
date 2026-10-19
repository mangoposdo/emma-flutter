/// Fechas y cantidades como salen en la pantalla y en el ticket (igual que la 0.7).
library;

import 'db/enums.dart';
import 'dinero.dart';

String _dos(int n) => n.toString().padLeft(2, '0');

/// "07:42 PM". En el ticket no va "p. m.": la impresora no tiene ese espacio especial.
String formatoHora(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '${_dos(h)}:${_dos(f.minute)} ${f.hour < 12 ? 'AM' : 'PM'}';
}

/// "07:42 p. m.", como Windows en español escribe la hora en pantalla (menú y caja).
String formatoHoraPantalla(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '${_dos(h)}:${_dos(f.minute)} ${f.hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// "7:42 PM", para el reloj de la barra de ventas.
String formatoHoraCorta(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '$h:${_dos(f.minute)} ${f.hour < 12 ? 'AM' : 'PM'}';
}

/// "17/10/2026".
String formatoFecha(DateTime f) => '${_dos(f.day)}/${_dos(f.month)}/${f.year}';

/// "17/10/2026 07:42 PM".
String formatoFechaHora(DateTime f) => '${formatoFecha(f)} ${formatoHora(f)}';

/// "17/10/26 07:42 PM", para la bitácora.
String formatoFechaHoraCorta(DateTime f) =>
    '${_dos(f.day)}/${_dos(f.month)}/${_dos(f.year % 100)} ${formatoHora(f)}';

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "sáb 17/10/2026".
String formatoDia(DateTime f) => '${_dias[f.weekday - 1]} ${formatoFecha(f)}';

/// "1.5 lb" o "3".
String formatoCantidadUnidad(int milesimas, UnidadVenta unidad) =>
    unidad == UnidadVenta.libra ? '${formatoCantidad(milesimas)} lb' : formatoCantidad(milesimas);

/// Medianoche del día de [f].
DateTime soloDia(DateTime f) => DateTime(f.year, f.month, f.day);
