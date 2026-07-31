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

  // Destructive / neutral fills (cancelled chips, danger dialogs, muted tiles)
  static const dangerFill = Color(0xFFFBE7E4);
  static const dangerInk = Color(0xFFC0392B);
  static const neutralFill = Color(0xFFF1ECE6);

  /// Heavier hairline than [border] — stepper rails, carousel dots.
  static const borderStrong = Color(0xFFE4DDD4);

  /// Border of a card that wants the eye (applied coupon, needs-action row).
  static const attentionBorder = Color(0xFFFAD9CC);

  // Dark-surface palette (driver header, week hero).
  /// A tile sitting on top of an [ink] surface.
  static const inkElevated = Color(0xFF243029);
  static const onDarkSuccess = Color(0xFF5FE39B);
  static const onDarkTrack = Color(0xFF3A342E);

  /// Unselected bottom-nav / rail item.
  static const navInactive = Color(0xFFB5ABA1);
}

/// The spacing scale. Every gap and pad in the kit is one of these; `gutter` is
/// the horizontal page margin the phone layouts share.
class AppSpace {
  AppSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;

  /// Horizontal page margin (home, orders, driver pool).
  static const gutter = 22.0;
}

/// Layout breakpoints shared by the adaptive shell and every desktop-aware
/// screen, so navigation and content switch on the same numbers.
///
/// Screens measure their own box with a `LayoutBuilder` rather than the window:
/// `AdaptiveShell` caps content at `maxContentWidth`, so the window width and
/// the width a screen actually gets are not the same thing.
class AppBreakpoints {
  AppBreakpoints._();

  /// Bottom navigation below, `NavigationRail` at and above.
  static const rail = 900.0;

  /// Single phone column below, master–detail / multi-column grids above.
  static const split = 1100.0;

  /// The rail shows labels next to its icons.
  static const extended = 1280.0;

  /// Desktop/tablet pointer layout (hover states, selectable ids).
  static bool isWide(double width) => width >= rail;

  /// There is room for a list and a detail pane side by side.
  static bool isSplit(double width) => width >= split;
}

class AppRadii {
  AppRadii._();

  static const xs = 8.0; // skeleton bars, tiny chips
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

  /// One step above [card] — a card that needs attention, a hovered row.
  static const raised = [
    BoxShadow(
      color: Color(0x14281406),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];

  /// Bottom sheets and anything anchored to the bottom edge: the shadow rises.
  static const overlay = [
    BoxShadow(
      color: Color(0x1A281406),
      blurRadius: 30,
      offset: Offset(0, -8),
    ),
  ];

  /// Modal dialogs, which float free of any edge.
  static const dialog = [
    BoxShadow(
      color: Color(0x24281406),
      blurRadius: 40,
      offset: Offset(0, 16),
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
