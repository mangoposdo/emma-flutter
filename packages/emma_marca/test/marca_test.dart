import 'package:emma_marca/emma_marca.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colores del manual', () {
    expect(EmmaColores.azul, const Color(0xFF14213D));
    expect(EmmaColores.rojo, const Color(0xFFD7263D));
    expect(EmmaColores.grisPizarra, const Color(0xFF56607A));
  });

  test('el rojo no se reparte por el tema: solo error y botonPrincipal', () {
    final t = EmmaTema.claro(plataforma: TargetPlatform.android);
    expect(t.colorScheme.primary, EmmaColores.azul);
    expect(t.colorScheme.secondary, EmmaColores.azul);
    expect(t.appBarTheme.backgroundColor, EmmaColores.azul);
  });

  test('títulos en Archivo Black; textos en Segoe UI (Windows) o Archivo', () {
    final win = EmmaTema.claro(plataforma: TargetPlatform.windows);
    final and = EmmaTema.claro(plataforma: TargetPlatform.android);
    expect(win.textTheme.headlineSmall!.fontFamily, contains('ArchivoBlack'));
    expect(win.textTheme.bodyMedium!.fontFamily, isNull);
    expect(and.textTheme.bodyMedium!.fontFamily, contains('Archivo'));
  });

  test('ventas: letra de 16 px o más', () {
    final t = EmmaTema.claro(plataforma: TargetPlatform.windows);
    expect(t.textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(16));
    expect(t.textTheme.labelLarge!.fontSize, greaterThanOrEqualTo(16));
  });

  testWidgets('el logo con lema pasa al ícono por debajo de 120 px', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: EmmaLogo(ancho: 64),
    ));
    final img = tester.widget<Image>(find.byType(Image));
    expect((img.image as AssetImage).assetName, contains('emma-icono.png'));
  });

  testWidgets('el logo mantiene su proporción', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: EmmaLogo(ancho: 400),
    ));
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.height, closeTo(400 / (2000 / 770), 0.01));
  });
}
