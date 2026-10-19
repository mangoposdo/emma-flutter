import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/formulario.dart';
import 'cliente_formulario_view_model.dart';

/// Formulario de un cliente (nuevo si [datos].id es null). Devuelve el cliente
/// guardado, o null si cancelan.
Future<Cliente?> editarCliente(BuildContext context, WidgetRef ref, DatosCliente datos) async {
  // El ViewModel vive mientras el formulario está abierto.
  final vivo = ref.listenManual(clienteFormularioViewModelProvider, (_, __) {});
  try {
    final vm = ref.read(clienteFormularioViewModelProvider.notifier);
    final nuevo = datos.id == null;
    Cliente? guardado;
    final v = await Formulario(nuevo ? 'Nuevo cliente' : 'Editar cliente', ancho: 500)
        .texto('nombre', 'Nombre', valor: datos.nombre, requerido: true)
        .texto('telefono', 'Teléfono', valor: datos.telefono)
        .texto('direccion', 'Dirección', valor: datos.direccion)
        .texto('sector', 'Sector', valor: datos.sector)
        .texto('referencia', 'Referencia', valor: datos.referencia)
        .texto('correo', 'Correo', valor: datos.correo)
        .texto('cumple', 'Cumpleaños (día/mes)', valor: datos.cumpleanos)
        .texto('cedula', 'Cédula', valor: datos.cedula)
        .texto('notas', 'Notas', valor: datos.notas)
        .monto('limite', 'Límite de crédito RD\$', valor: datos.limiteCredito)
        .casilla('fijo', 'Cliente fijo (sale primero y en el reporte de recurrencia)', nuevo || datos.esFijo)
        .casilla('activo', 'Activo (puede tomar fiado)', nuevo || datos.activo)
        .nota('Referencia: cómo llegar (ej. casa verde al lado del colmado). Notas: lo que conviene saber '
            '(ej. siempre paga con 1,000). Límite 0 = sin límite; solo el dueño lo cambia.')
        .mostrar(context, alAceptar: (v) async {
      guardado = await vm.guardar(DatosCliente(
        id: datos.id,
        nombre: v.txt('nombre'),
        telefono: v.txtONulo('telefono'),
        direccion: v.txtONulo('direccion'),
        sector: v.txtONulo('sector'),
        referencia: v.txtONulo('referencia'),
        correo: v.txtONulo('correo'),
        cumpleanos: v.txtONulo('cumple'),
        cedula: v.txtONulo('cedula'),
        notas: v.txtONulo('notas'),
        limiteCredito: v.monto('limite'),
        esFijo: v.marcado('fijo'),
        activo: v.marcado('activo'),
      ));
    });
    return v == null ? null : guardado;
  } finally {
    vivo.close();
  }
}
