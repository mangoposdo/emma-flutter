import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'impresora.dart';

/// Windows: winspool en modo RAW, como la 0.7 (OpenPrinter, StartDocPrinter, WritePrinter).
class ImpresoraWindows implements Impresora {
  @override
  Future<List<String>> instaladas() async {
    final flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    final necesarios = calloc<Uint32>();
    final cuantos = calloc<Uint32>();
    try {
      EnumPrinters(flags, nullptr, 4, nullptr, 0, necesarios, cuantos);
      if (necesarios.value == 0) return [];
      final buffer = calloc<Uint8>(necesarios.value);
      try {
        if (EnumPrinters(flags, nullptr, 4, buffer, necesarios.value, necesarios, cuantos) == 0) return [];
        final info = buffer.cast<PRINTER_INFO_4>();
        final nombres = [for (var i = 0; i < cuantos.value; i++) (info + i).ref.pPrinterName.toDartString()];
        return nombres..sort();
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(necesarios);
      calloc.free(cuantos);
    }
  }

  @override
  Future<void> enviarRaw(String impresora, Uint8List datos) async {
    final nombre = impresora.toNativeUtf16();
    final manija = calloc<IntPtr>();
    try {
      if (OpenPrinter(nombre, manija, nullptr) == 0) {
        throw const ErrorImpresora('No se encontró la impresora.');
      }
      final h = manija.value;
      final doc = calloc<DOC_INFO_1>();
      final nombreDoc = 'Ticket'.toNativeUtf16();
      final tipo = 'RAW'.toNativeUtf16();
      final bytes = calloc<Uint8>(datos.length);
      final escritos = calloc<Uint32>();
      try {
        doc.ref
          ..pDocName = nombreDoc
          ..pOutputFile = nullptr
          ..pDatatype = tipo;
        if (StartDocPrinter(h, 1, doc) == 0) throw const ErrorImpresora('La impresora no aceptó el trabajo.');
        try {
          StartPagePrinter(h);
          bytes.asTypedList(datos.length).setAll(0, datos);
          if (WritePrinter(h, bytes, datos.length, escritos) == 0) {
            throw const ErrorImpresora('Falló el envío a la impresora.');
          }
          EndPagePrinter(h);
        } finally {
          EndDocPrinter(h);
        }
      } finally {
        calloc
          ..free(doc)
          ..free(nombreDoc)
          ..free(tipo)
          ..free(bytes)
          ..free(escritos);
        ClosePrinter(h);
      }
    } finally {
      calloc
        ..free(nombre)
        ..free(manija);
    }
  }
}
