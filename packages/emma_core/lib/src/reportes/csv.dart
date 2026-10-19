/// CSV para abrir en Excel: separado por punto y coma, con BOM para los acentos
/// (igual que la 0.7).
library;

/// Arma el archivo completo. Las celdas ya vienen como texto.
String armarCsv(List<String> titulos, Iterable<List<String?>> filas) {
  String celda(String? s) {
    final t = s ?? '';
    return t.contains(';') || t.contains('"') || t.contains('\n') ? '"${t.replaceAll('"', '""')}"' : t;
  }

  final b = StringBuffer('﻿')..writeln(titulos.map(celda).join(';'));
  for (final f in filas) {
    b.writeln(f.map(celda).join(';'));
  }
  return b.toString();
}

/// Parte una línea de CSV respetando las comillas.
List<String> dividirCsv(String linea, String separador) {
  final res = <String>[];
  final actual = StringBuffer();
  var comillas = false;
  for (var i = 0; i < linea.length; i++) {
    final ch = linea[i];
    if (ch == '"') {
      if (comillas && i + 1 < linea.length && linea[i + 1] == '"') {
        actual.write('"');
        i++;
      } else {
        comillas = !comillas;
      }
    } else if (ch == separador && !comillas) {
      res.add(actual.toString());
      actual.clear();
    } else {
      actual.write(ch);
    }
  }
  res.add(actual.toString());
  return res;
}

/// "1234.50" para Excel (sin separador de miles).
String montoCsv(int centavos) {
  final neg = centavos < 0;
  final a = centavos.abs();
  return '${neg ? '-' : ''}${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}
