import 'dinero.dart';

/// Error de negocio con un mensaje en español simple para mostrar tal cual.
class EmmaError implements Exception {
  const EmmaError(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

class DatoInvalido extends EmmaError {
  const DatoInvalido(super.mensaje);
}

class PermisoDenegado extends EmmaError {
  const PermisoDenegado(super.mensaje);
}

class CajaCerrada extends EmmaError {
  const CajaCerrada() : super('La caja está cerrada. Abra la caja para vender.');
}

class LimiteFiadoExcedido extends EmmaError {
  LimiteFiadoExcedido({required this.debe, required this.limite, required this.quedaria})
      : super('Ese fiado pasa el límite. Debe ${formatoRD(debe)}, '
            'su límite es ${formatoRD(limite)} y quedaría en ${formatoRD(quedaria)}.');

  /// Centavos.
  final int debe;
  final int limite;
  final int quedaria;
}

class ErrorMigracion extends EmmaError {
  const ErrorMigracion(super.mensaje, {this.causa, this.copia});
  final Object? causa;

  /// Ruta de la copia de antes de actualizar.
  final String? copia;
}
