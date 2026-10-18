import 'dart:ui' show FontVariation;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'colores.dart';

/// Tema de las apps de Emma (manual, secciones 05, 06 y 12).
///
/// * Barra azul, fondo blanco, texto azul; textos de apoyo en gris pizarra.
/// * Títulos en Archivo Black.
/// * Textos: Segoe UI en Windows (manual), Archivo en Android e iPhone.
/// * Rojo solo en el botón principal: usar [EmmaTema.botonPrincipal].
///   Los demás botones son azules o con borde azul.
/// * Letra mínima de 16 px en la pantalla de ventas (PRD, accesibilidad).
abstract final class EmmaTema {
  static const familiaTitulos = 'ArchivoBlack';
  static const _familiaArchivo = 'Archivo';

  static ThemeData claro({TargetPlatform? plataforma}) {
    final p = plataforma ?? defaultTargetPlatform;
    final esWindows = p == TargetPlatform.windows;

    // En Windows se deja la letra del sistema (Segoe UI).
    final familiaTexto = esWindows ? null : 'packages/emma_marca/$_familiaArchivo';
    const familiaTit = 'packages/emma_marca/$familiaTitulos';

    final esquema = ColorScheme.fromSeed(
      seedColor: EmmaColores.azul,
      primary: EmmaColores.azul,
      onPrimary: EmmaColores.blanco,
      // El rojo se reserva: no se usa como secondary para que Material no lo
      // reparta por toda la app. Solo lo pinta botonPrincipal.
      secondary: EmmaColores.azul,
      onSecondary: EmmaColores.blanco,
      error: EmmaColores.rojo,
      onError: EmmaColores.blanco,
      surface: EmmaColores.blanco,
      onSurface: EmmaColores.azul,
      onSurfaceVariant: EmmaColores.grisPizarra,
      outline: EmmaColores.azul25,
    );

    TextStyle texto(double tam, double alto, FontWeight peso, {Color? color}) => TextStyle(
          fontFamily: familiaTexto,
          fontSize: tam,
          height: alto,
          fontWeight: peso,
          // Archivo es variable: el peso se pasa también como eje wght.
          fontVariations: familiaTexto == null ? null : [FontVariation('wght', peso.value.toDouble())],
          color: color ?? EmmaColores.azul,
        );

    TextStyle titulo(double tam, double alto) => TextStyle(
          fontFamily: familiaTit,
          fontSize: tam,
          height: alto,
          color: EmmaColores.azul,
        );

    final textos = TextTheme(
      // Manual: Título 40/1.1, Subtítulo 24/1.2, Texto 16/1.55, Etiqueta 13 mayúsculas.
      displaySmall: titulo(40, 1.1),
      headlineMedium: titulo(32, 1.1),
      headlineSmall: titulo(24, 1.2),
      titleLarge: titulo(20, 1.2),
      titleMedium: texto(18, 1.3, FontWeight.w700),
      titleSmall: texto(16, 1.3, FontWeight.w700),
      bodyLarge: texto(18, 1.5, FontWeight.w400),
      bodyMedium: texto(16, 1.55, FontWeight.w400),
      bodySmall: texto(14, 1.45, FontWeight.w400, color: EmmaColores.grisPizarra),
      labelLarge: texto(16, 1.2, FontWeight.w700),
      labelMedium: texto(13, 1.2, FontWeight.w700).copyWith(letterSpacing: 1.5),
      labelSmall: texto(12, 1.2, FontWeight.w500, color: EmmaColores.grisPizarra),
    );

    const radio = BorderRadius.all(Radius.circular(8));

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: EmmaColores.blanco,
      fontFamily: familiaTexto,
      textTheme: textos,
      appBarTheme: AppBarTheme(
        backgroundColor: EmmaColores.azul,
        foregroundColor: EmmaColores.blanco,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: titulo(20, 1.2).copyWith(color: EmmaColores.blanco),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: EmmaColores.azul,
          foregroundColor: EmmaColores.blanco,
          minimumSize: const Size(64, 48),
          textStyle: textos.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: radio),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: EmmaColores.azul,
          side: const BorderSide(color: EmmaColores.azul, width: 1.5),
          minimumSize: const Size(64, 48),
          textStyle: textos.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: radio),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: radio),
        enabledBorder: OutlineInputBorder(
          borderRadius: radio,
          borderSide: BorderSide(color: EmmaColores.azul25),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: radio,
          borderSide: BorderSide(color: EmmaColores.azul, width: 2),
        ),
        labelStyle: textos.bodyMedium?.copyWith(color: EmmaColores.grisPizarra),
      ),
      dividerTheme: DividerThemeData(color: EmmaColores.azul10, thickness: 1),
      cardTheme: CardThemeData(
        color: EmmaColores.blanco,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radio,
          side: BorderSide(color: EmmaColores.azul10),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: EmmaColores.azul,
        contentTextStyle: textos.bodyMedium?.copyWith(color: EmmaColores.blanco),
      ),
    );
  }

  /// Estilo del ÚNICO botón rojo de cada pantalla (Cobrar, Empezar, Conectar).
  static ButtonStyle botonPrincipal(BuildContext context) => FilledButton.styleFrom(
        backgroundColor: EmmaColores.rojo,
        foregroundColor: EmmaColores.blanco,
        minimumSize: const Size(160, 56),
        textStyle: Theme.of(context).textTheme.titleMedium,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      );
}
