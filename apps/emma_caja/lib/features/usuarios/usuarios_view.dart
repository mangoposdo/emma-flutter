import 'package:emma_core/emma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comun/botones.dart';
import '../../comun/formulario.dart';
import '../../comun/piezas.dart';
import '../../comun/tabla.dart';
import 'usuarios_view_model.dart';

/// Usuarios de la 0.7: la lista a la izquierda y la bitácora a la derecha.
class UsuariosView extends ConsumerWidget {
  const UsuariosView({super.key});

  Future<void> _editar(BuildContext context, WidgetRef ref, Usuario? u) async {
    final nuevo = u == null;
    final vm = ref.read(usuariosViewModelProvider.notifier);
    final f = Formulario(nuevo ? 'Nuevo usuario' : 'Editar usuario', ancho: 480)
        .texto('nombre', 'Nombre', valor: u?.nombre, requerido: true)
        .texto('login', 'Usuario (para entrar)', valor: u?.login, requerido: true)
        .opciones<Rol>('rol', 'Rol', const [Rol.cajero, Rol.dueno], u?.rol ?? Rol.cajero, textoRolFormulario)
        .clave('pin', nuevo ? 'PIN' : 'PIN nuevo')
        .casilla('activo', 'Activo (puede entrar)', u?.activo ?? true);
    if (!nuevo) f.nota('Deje el PIN vacío para no cambiarlo.');
    await f.mostrar(
      context,
      alAceptar: (v) => vm.guardar(
        id: u?.id,
        nombre: v.txt('nombre'),
        login: v.txt('login'),
        rol: v.opcion<Rol>('rol'),
        activo: v.marcado('activo'),
        pin: v.txtONulo('pin'),
      ),
    );
  }

  void _editarEscogido(BuildContext context, WidgetRef ref) {
    final u = ref.read(usuariosViewModelProvider).value?.usuarioEscogido;
    if (u != null) _editar(context, ref, u);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(usuariosViewModelProvider);
    final s = estado.value;
    final vm = ref.read(usuariosViewModelProvider.notifier);
    if (s == null) {
      return estado.hasError
          ? TextoGris('No se pudieron cargar los usuarios: ${estado.error}')
          : const Center(child: CircularProgressIndicator());
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TituloPantalla('Usuarios'),
              Expanded(
                child: Tabla<Usuario>(
                  filas: s.usuarios,
                  escogida: s.escogido,
                  alEscoger: vm.escoger,
                  alAbrir: (i) => _editar(context, ref, s.usuarios[i]),
                  columnas: [
                    Columna('Nombre', (u) => u.nombre),
                    Columna('Usuario', (u) => u.login, ancho: 120),
                    Columna('Rol', (u) => textoRol(u.rol), ancho: 90),
                    Columna('Activo', (u) => '', ancho: 70, celda: (u) => celdaMarcada(u.activo)),
                  ],
                ),
              ),
              Wrap(
                children: [
                  Boton('Nuevo usuario', tipo: TipoBoton.principal, onPressed: () => _editar(context, ref, null)),
                  Boton('Editar', onPressed: () => _editarEscogido(context, ref)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TituloPantalla('Bitácora: quién hizo qué'),
                Expanded(
                  child: Tabla<LineaBitacora>(
                    filas: s.bitacora,
                    tamano: 14,
                    altoFila: 28,
                    columnas: [
                      Columna('Fecha', (b) => formatoFechaHoraCorta(b.entrada.fecha), ancho: 150),
                      Columna('Usuario', (b) => b.usuario, ancho: 110),
                      Columna('Acción', (b) => b.entrada.accion, ancho: 180),
                      Columna('Detalle', (b) => b.entrada.detalle ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
