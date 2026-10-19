import 'dart:async';

import 'package:emma_caja/app/providers.dart';
import 'package:emma_caja/features/usuarios/usuarios_view_model.dart';
import 'package:emma_core/emma_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudantes.dart';

Future<UsuariosState> _cargado(ProviderContainer c) async {
  c.listen(usuariosViewModelProvider, (_, __) {});
  return c.read(usuariosViewModelProvider.future);
}

void main() {
  test('textos del rol como en la 0.7', () {
    expect(textoRol(Rol.dueno), 'Dueño');
    expect(textoRol(Rol.cajero), 'Cajero');
    expect(textoRolFormulario(Rol.dueno), 'Dueño (todo)');
    expect(textoRolFormulario(Rol.cajero), 'Cajero (vende, cobra, cuadra)');
  });

  test('crear un usuario lo pone en la lista y en la bitácora', () async {
    final b = await Banco.crear();
    var s = await _cargado(b.c);
    expect([for (final u in s.usuarios) u.login], ['admin']);
    final vm = b.c.read(usuariosViewModelProvider.notifier);

    vm.escoger(0);
    expect(b.c.read(usuariosViewModelProvider).value!.usuarioEscogido?.login, 'admin');

    await vm.guardar(nombre: ' María ', login: 'Maria', rol: Rol.cajero, activo: true, pin: '4321');
    s = b.c.read(usuariosViewModelProvider).value!;
    expect([for (final u in s.usuarios) (u.nombre, u.login, u.rol, u.activo)], [
      ('Dueño', 'admin', Rol.dueno, true),
      ('María', 'maria', Rol.cajero, true),
    ]);
    // Como en la 0.7, al recargar se pierde la fila escogida.
    expect(s.escogido, isNull);
    final linea = s.bitacora.first;
    expect((linea.usuario, linea.entrada.accion, linea.entrada.detalle), ('Dueño', 'Usuario creado', 'maria'));
    expect(formatoFechaHoraCorta(linea.entrada.fecha), matches(RegExp(r'^\d\d/\d\d/\d\d \d\d:\d\d (AM|PM)$')));
    expect(await b.c.read(usuarioServiceProvider).iniciarSesion('maria', '4321'), isNotNull);
  });

  test('editar sin PIN deja el PIN como estaba', () async {
    final b = await Banco.crear();
    await _cargado(b.c);
    final vm = b.c.read(usuariosViewModelProvider.notifier);
    await vm.guardar(nombre: 'María', login: 'maria', rol: Rol.cajero, activo: true, pin: '4321');
    final maria = b.c.read(usuariosViewModelProvider).value!.usuarios.firstWhere((u) => u.login == 'maria');

    await vm.guardar(id: maria.id, nombre: 'María Pérez', login: 'maria', rol: Rol.dueno, activo: true);
    final s = b.c.read(usuariosViewModelProvider).value!;
    final cambiada = s.usuarios.firstWhere((u) => u.id == maria.id);
    expect((cambiada.nombre, cambiada.rol), ('María Pérez', Rol.dueno));
    expect(s.bitacora.first.entrada.accion, 'Usuario modificado');
    expect(await b.c.read(usuarioServiceProvider).iniciarSesion('maria', '4321'), isNotNull);
  });

  test('las reglas del servicio llegan con su mensaje', () async {
    final b = await Banco.crear();
    final s = await _cargado(b.c);
    final vm = b.c.read(usuariosViewModelProvider.notifier);
    final admin = s.usuarios.single;

    await expectLater(
      vm.guardar(nombre: 'Juan', login: 'juan', rol: Rol.cajero, activo: true),
      throwsA(isA<EmmaError>().having((e) => e.mensaje, 'mensaje', 'El usuario nuevo necesita un PIN.')),
    );
    await expectLater(
      vm.guardar(id: admin.id, nombre: admin.nombre, login: admin.login, rol: Rol.cajero, activo: true),
      throwsA(isA<EmmaError>().having((e) => e.mensaje, 'mensaje', 'Debe quedar al menos un dueño activo.')),
    );
    await expectLater(
      vm.guardar(nombre: 'Juan', login: 'juan', rol: Rol.cajero, activo: true, pin: '12'),
      throwsA(isA<EmmaError>().having((e) => e.mensaje, 'mensaje', 'El PIN debe tener al menos 4 caracteres.')),
    );
    expect(b.c.read(usuariosViewModelProvider).value!.usuarios, hasLength(1));
  });

  test('el cajero no puede ver la bitácora', () async {
    final b = await Banco.crear(comoCajero: true);
    final error = Completer<Object>();
    b.c.listen(usuariosViewModelProvider, (_, s) {
      if (s.hasError && !error.isCompleted) error.complete(s.error!);
    });
    expect(await error.future, isA<PermisoDenegado>());
  });
}
