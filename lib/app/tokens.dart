import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Eaty design tokens — single source of truth for the brand look.
/// Mirrors the "Eaty — Multi-Vendor Food Delivery · UI Kit" design doc.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFFFF5A2C);
  static const primaryDark = Color(0xFFE8410F);
  static const primaryLight = Color(0xFFFF7A45);
  static const rating = Color(0xFFFFB400);
  static const success = Color(0xFF18A957);

  // Neutrals
  static const ink = Color(0xFF1A1714); // primary text / dark surfaces
  static const canvas = Color(0xFFFBF8F5); // app background
  static const surface = Color(0xFFFFFFFF); // cards
  static const border = Color(0xFFECE6DF); // card / input borders
  static const borderSoft = Color(0xFFF0EAE3); // dividers

  // Text
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF6B635C);
  static const textMuted = Color(0xFF8C8178);
  static const textFaint = Color(0xFFA89C90);

  // Soft accent fills (chips / badges)
  static const warmFill = Color(0xFFFFEDE6); // primary tint bg
  static const amberFill = Color(0xFFFFF3E0); // rating chip bg
  static const amberInk = Color(0xFFB26A00); // rating chip text
  static const successFill = Color(0xFFE4F6EC); // "open now" bg
  static const successInk = Color(0xFF0E7C3F); // "open now" text
}

class AppRadii {
  AppRadii._();

  static const sm = 11.0;
  static const md = 14.0; // inputs, secondary buttons
  static const lg = 16.0; // primary buttons
  static const xl = 20.0; // cards
  static const xxl = 24.0; // bottom sheets
  static const pill = 999.0;
}

class AppShadows {
  AppShadows._();

  /// Soft card lift used across the kit.
  static const card = [
    BoxShadow(
      color: Color(0x12281406), // rgba(40,20,10,.07)
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  /// Glow under the primary CTA / FAB.
  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.45),
      blurRadius: 22,
      offset: const Offset(0, 12),
      spreadRadius: -10,
    ),
  ];
}

/// Display / heading face: Bricolage Grotesque (800).
class AppType {
  AppType._();

  static TextStyle display(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.02 * size,
        height: 1.25,
      );

  static TextStyle heading(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.01 * size,
        height: 1.3,
      );

  /// Numeric / price face: JetBrains Mono.
  static TextStyle mono(
    double size, {
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w600,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
}
