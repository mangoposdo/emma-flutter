# Emma en Flutter

Caja de Emma (Windows y Android) y app del dueño (Android e iPhone), rehechas en Flutter según el PRD "Emma en Flutter". La nube (.NET + Azure) no cambia.

```
emma_flutter/
  packages/emma_core/   reglas de negocio y base de datos (Dart puro, se prueba sin pantallas)
  apps/emma_caja/       app del mostrador: Windows y Android (pantallas en la Fase 2)
  apps/emma_dueno/      app del dueño: Android e iPhone (Fase 6)
```

## Arquitectura: MVVM

Las dos apps siguen MVVM. La regla: la Vista no habla con la base ni con la nube; solo con su ViewModel.

| Capa | Dónde vive | Qué hace |
|---|---|---|
| **Model** | `packages/emma_core` | Tablas drift, servicios de negocio (`VentaService`, `CajaService`...), cola de nube, tickets ESC/POS. Dart puro, sin Flutter. En la app del dueño, el Model es el cliente de la API de la nube. |
| **ViewModel** | `apps/*/lib/features/<pantalla>/<pantalla>_view_model.dart` | Un `Notifier` / `AsyncNotifier` de Riverpod por pantalla. Guarda el estado de la pantalla (inmutable), llama a los servicios del Model y traduce `EmmaError` a mensajes. No importa `package:flutter/material.dart`. |
| **View** | `apps/*/lib/features/<pantalla>/<pantalla>_view.dart` | Widgets. Lee el estado con `ref.watch` y manda acciones al ViewModel (teclas F1 a F10, toques, Enter). Sin lógica de negocio. |

```
apps/emma_caja/lib/
  main.dart
  app/                 router (go_router), tema, providers del Model (base, servicios, sesión)
  features/
    ventas/
      ventas_view.dart
      ventas_view_model.dart
      ventas_state.dart
    cobro/  delivery/  productos/  caja/  clientes/  reportes/  usuarios/  configuracion/
  plataforma/          impresión RAW Win32, USB, Bluetooth, red (detrás de una interfaz del Model)
```

Así se prueba en tres niveles: el Model con `dart test` (ya hecho), los ViewModels con pruebas de Riverpod sin pantallas (`ProviderContainer` con servicios sobre SQLite en memoria) y las Vistas a mano o con pruebas de widgets.

## Estado: Fase 1, primera tarea

Hecho:

- Monorepo con pub workspaces (un solo `flutter pub get` en la raíz).
- Esquema drift con las 15 tablas del modelo de datos, migración inicial (versión 1) y siembra del primer arranque: negocio con `instalacionId`, usuario `admin` dueño con PIN 1234 (hash PBKDF2-SHA256, 100,000 vueltas, igual que la 0.6) y el producto interno "Varios".
- Apertura de la base en `C:\ProgramData\ColmadoEmma\emma.db` con WAL, `synchronous=FULL` y llaves foráneas. Si hay migración pendiente, copia a `Respaldos\AntesDeActualizar` y, si falla, vuelve sola a la copia.
- `VentaService`: cobrar (efectivo con devuelta, monto exacto, tarjeta, transferencia, fiado con límite, descuento en pesos, venta suelta, libra por monto), anular, tickets pendientes. Todo en una sola transacción con el evento `venta.registrada` / `venta.anulada` para la nube.
- Pruebas: `venta_service_test.dart` (27), `migracion_test.dart` (10), `dinero_test.dart` (8).

Falta en la Fase 1: CajaService (abrir, entradas y salidas, cuadre), FiadoService (abonos, estado de cuenta), ProductoService (ajustes, CSV), UsuarioService (login, PIN, bitácora), TicketService (pedidos abiertos), recurrencia de clientes, y llevar las pruebas al nivel de las 53 de la 0.6.

## Cómo probar en Windows

Requisitos: Flutter 3 estable (trae Dart 3.6 o más nuevo).

```powershell
cd emma_flutter
flutter pub get

cd packages\emma_core
dart run build_runner build --delete-conflicting-outputs   # genera database.g.dart
dart test
```

Las pruebas de `emma_core` usan el SQLite del sistema. En Windows hace falta `sqlite3.dll` (64 bits):

1. Bajar "Precompiled Binaries for Windows" (sqlite-dll-win-x64) de sqlite.org.
2. Poner `sqlite3.dll` en una carpeta que esté en el PATH (por ejemplo `C:\sqlite`) y abrir una consola nueva.

Las apps no lo necesitan: `sqlite3_flutter_libs` mete SQLite dentro del instalador.

Para generar las carpetas de plataforma de las apps (una sola vez):

```powershell
cd apps\emma_caja
flutter create --platforms=windows,android --project-name emma_caja .
del test\widget_test.dart

cd ..\emma_dueno
flutter create --platforms=android,ios --project-name emma_dueno .
del test\widget_test.dart
```

## Reglas del núcleo

- Montos: enteros en centavos. Cantidades y existencias: enteros en milésimas (0.5 lb = 500). Nunca `double`; solo el JSON de la nube los convierte a número decimal en el último paso.
- La venta queda con `ticketPendiente = true` hasta que la impresora confirma (`marcarTicketImpreso`). Si la app se cae antes de imprimir, el ticket sigue pendiente.
- Los servicios revisan el rol (no solo la pantalla). Anular es solo del dueño.
- Fechas de los eventos: hora local del colmado sin zona (`2026-10-18T10:30:05`).

## Decisiones tomadas (confirmar)

1. **Cantidades en milésimas de libra.** "$50" de arroz a RD$35 la lb queda en 1.429 lb y el total es exactamente RD$50.00.
2. **Redondeo de línea:** al centavo, la mitad sube.
3. **Existencia negativa permitida.** El PRD no dice que se bloquee la venta sin existencia; no se bloquea.
4. **Límite de fiado:** se permite llegar justo al límite; pasarlo, no. Límite 0 = sin límite.
5. **Anular una venta de un turno ya cerrado** se permite (el PRD no lo limita). Eso cambia el cuadre de un turno cerrado; hay que decidir si se bloquea.
6. **Descuentos van a la bitácora** (lo dice el documento de diseño).
7. **Forzar cambio de PIN:** sin columna nueva; al entrar con `admin` y PIN 1234 la app pide cambiarlo.
8. **`nubeLlave`** se deja vacía en SQLite; la llave real va en `flutter_secure_storage`.
9. **Nombres de tablas en snake_case.** La importación de la 0.6 (Fase 7) mapeará los nombres de EF Core.
10. **Código reservado de Varios:** `__VARIOS__`.

## Preguntas abiertas

- ¿Cómo guarda la 0.6 el hash del PIN (orden de sal y hash, base64 o hex)? Hace falta para que el PIN siga funcionando después de importar en la Fase 7.
- ¿`tasaItbis` se usa en algún flujo hoy? Queda guardada pero sin uso.
- ¿Los nombres de tablas y columnas de la base de la 0.6? Con acceso al repo de la 0.6 se resuelve.
