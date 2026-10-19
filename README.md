# Emma en Flutter

Caja de Emma (Windows y Android) y app del dueño (Android e iPhone), rehechas en Flutter según el PRD "Emma en Flutter". La nube (.NET + Azure) no cambia.

```
emma_flutter/
  packages/emma_core/   reglas de negocio y base de datos (Dart puro, se prueba sin pantallas)
  packages/emma_marca/  identidad gráfica: colores, letras, logos y tema (Flutter)
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

## Marca

Todo sale del manual "Identidad gráfica Emma" (octubre de 2026) y vive en `packages/emma_marca`. Las pantallas no escriben colores ni letras a mano: usan `EmmaColores`, `EmmaTema` y `EmmaLogo`.

- **Colores:** azul Emma `#14213D` (barras y texto), rojo toldo `#D7263D`, blanco, gris pizarra `#56607A` (textos de apoyo).
- **Rojo:** una sola cosa por pantalla, la acción principal (Cobrar, Empezar, Conectar), con `EmmaTema.botonPrincipal(context)`. El tema no usa el rojo en ningún otro lado.
- **Letras:** títulos en Archivo Black. Textos en Segoe UI en Windows (como dice el manual) y en Archivo en Android e iPhone. Las fuentes van dentro de la app (licencia OFL), así funcionan sin internet.
- **Logo:** horizontal negativo en la barra azul; principal en fondos claros. Por debajo de 120 px `EmmaLogo` cambia solo al ícono. Nunca estirar, girar, recolorear ni poner sombra.
- **Ticket:** logo a una tinta de 384 puntos (`assets/ticket/emma-ticket-384.png`), para el generador ESC/POS de la Fase 2.
- **Ícono de Windows:** `packages/emma_marca/assets/windows/emma.ico`. Después de `flutter create`, copiarlo a `apps/emma_caja/windows/runner/resources/app_icon.ico`.
- **Cómo se habla en el programa:** de **usted**, frases cortas, palabras del colmado, nada técnico ("Abra la caja para vender", no "Abre la caja"). El tuteo es solo para la publicidad.

## Estado: la caja de la 0.7.1, completa

La caja replica la versión de escritorio en C# (0.7.1, carpeta `donador-emmapos/emma-main-actualizado`): mismas pantallas, textos, teclas y reglas, con el mismo contrato con la nube.

- **Núcleo (`emma_core`)**: esquema con 19 tablas (las 15 de la 0.6 más suplidores, compras, líneas de compra y alias de productos). Servicios de ventas, pedidos abiertos, delivery, caja y cuadre, productos e inventario (ajustes, CSV), compras (con lectura de factura y alias aprendidos), clientes y fiado, usuarios y bitácora, reportes y recurrencia, configuración, respaldos y mantenimiento, nube (activar, enviar eventos, leer factura) e impresión ESC/POS (venta, abono, cuadre, comanda, logo, intensidad, CP850).
- **App (`emma_caja`)**: entrada con usuario y PIN, menú lateral de la 0.7 (el cajero no ve Compras, Reportes, Usuarios ni Configuración) y las ocho pantallas. Al abrir: revisa que la base esté sana (si no, ofrece el último respaldo), respalda (y cada 2 horas), mantenimiento semanal, aviso de reloj atrasado y envío a la nube cada minuto.
- **Impresión**: Windows por winspool en modo RAW (como la 0.7); macOS y Linux por CUPS (`lp -o raw`).
- **Pruebas**: 128 del núcleo (las de la 0.7.1 traducidas, más las propias) y 108 de la app (ViewModels con base en memoria, y una prueba que arma la entrada y las ocho pantallas a 1280 x 800 para detectar desbordes).

Diferencias con la 0.7 a propósito:

- **Escanear agrega 1 al instante** (en la 0.7 pasaba a la casilla de cantidad). Lo que va por libra sí pasa a la cantidad (libras o `$50`).
- **La lista de productos sale desde la primera letra**, debajo de la casilla del código (la 0.7 buscaba al dar Enter). Primero los que empiezan con lo escrito; un toque escoge, o las flechas y Enter. Sin ninguno marcado, Enter sigue buscando por código primero, y la lista espera 120 ms a que se deje de escribir para no salir con el lector de código de barras.
- **Libra por monto exacta**: "$50" de queso cobra exactamente RD$ 50.00 (la 0.7 redondeaba la cantidad y podía dar un centavo de diferencia).
- **Base nueva y aparte**: `C:\ProgramData\ColmadoEmma\emma.db` (la 0.7 usa `colmado.db` en la misma carpeta; no se tocan). La importación de los datos de la 0.7 es la Fase 7; los PIN de la 0.7 ya se pueden verificar.

Pendiente: importar los datos de la 0.7 (Fase 7), la app del dueño, y probar la impresión y el instalador en Windows. En macOS la "copia extra en USB" necesita permiso de carpeta del sistema (sandbox); en Windows no.

## Cómo probar en macOS (mientras se desarrolla)

```bash
cd emma_flutter && flutter pub get
cd packages/emma_core && dart run build_runner build && dart test
cd ../../apps/emma_caja && flutter test && flutter run -d macos
```

Entre con usuario `admin` y PIN `1234`. En debug, una base nueva trae productos de colmado de prueba.

La base queda en `~/Library/Containers/com.example.emmaCaja/Data/Library/Application Support/com.example.emmaCaja/emma.db`. Para empezar de cero, cierre la app y borre esa carpeta. No abra dos copias de la app a la vez sobre la misma base.

`emma_core` fija `analyzer` por debajo de 10: con analyzer 10, drift_dev 2.31 (la última para sqlite3 2.x) genera las tablas **sin llaves foráneas**. La prueba "las tablas tienen sus llaves foráneas" lo vigila.

## Cómo probar en Windows

Requisitos: Flutter 3 estable (trae Dart 3.6 o más nuevo).

```powershell
cd emma_flutter
flutter pub get

cd packages\emma_core
dart run build_runner build --delete-conflicting-outputs   # genera database.g.dart
dart test

cd ..\emma_marca
flutter test
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
5. **Anular una venta de un turno ya cerrado no se permite** (igual que la 0.7): se corrige con un ajuste de inventario o de caja.
6. **Descuentos van a la bitácora** (lo dice el documento de diseño).
7. **PIN de fábrica:** al entrar con `admin` y PIN 1234 la app avisa que se cambie (igual que la 0.7).
8. **`nubeLlave`** se guarda en la base, como la 0.7 (pasarla a `flutter_secure_storage` queda para después).
9. **Nombres de tablas en snake_case.** La importación de la 0.6 (Fase 7) mapeará los nombres de EF Core.
10. **Códigos reservados:** `__VARIOS__` (venta suelta) y `__ENVIO__` (cargo del delivery). Los productos pueden no tener código.
11. **El precio sale de la base** al cobrar, no de la pantalla (igual que la 0.7); solo los servicios llevan el monto escrito.
12. **Ancho del ticket en letras:** 48 (80 mm) o 32 (58 mm), como la 0.7.

## Preguntas abiertas

- Resuelto: la 0.6/0.7 guarda el PIN como `<vueltas>.<sal base64>.<hash base64>` (PBKDF2-SHA256); `PinHasher` lo verifica.
- ¿`tasaItbis` se usa en algún flujo hoy? Queda guardada pero sin uso.
- Los nombres de tablas y columnas de la 0.7 están en `emma-main-actualizado/src/Colmado.Core/Modelos/Entidades.cs` (EF Core, montos como enteros con 4 decimales); la Fase 7 los mapea.
