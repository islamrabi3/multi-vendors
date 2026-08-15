import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kitchen IN design tokens — single source of truth for the brand look.
///
/// The brand values below ([primary], [primaryDark], [primaryLight],
/// [pistachio], [onDarkPistachio], [ink], [imagePlaceholder] and
/// [imagePlaceholderInk]) are lifted verbatim from the Kitchen IN design system
/// (`assets/brand/README.md` and its SVGs). The neutrals, tints and semantic
/// fills are *derived* from them — the design system ships an identity, not a
/// full scale — and are tinted toward the aubergine hue so nothing in the app
/// reads as a leftover from the previous warm/orange palette.
class AppColors {
  AppColors._();

  // Brand — aubergine and pistachio.
  /// Aubergine. The brand colour: CTAs, active nav, focus rings, links.
  static const primary = Color(0xFF5C2340);

  /// The deep end of the brand gradient; pressed states, gradient tails.
  static const primaryDark = Color(0xFF431829);

  /// The light end of the brand gradient; gradient heads, hover tints.
  static const primaryLight = Color(0xFF8F4468);

  /// The accent — the dot inside the arch. Used sparingly: it is a highlight,
  /// never a surface.
  static const pistachio = Color(0xFF9DBE3F);

  /// [pistachio] lightened for legibility on an aubergine surface — this is the
  /// tone "IN" takes in the wordmark on dark.
  static const onDarkPistachio = Color(0xFFC3DE84);

  static const rating = Color(0xFFFFB400);
  static const success = Color(0xFF18A957);

  /// The brand gradient, top-left to bottom-right. Splash, hero cards, the
  /// promo banner. Pair with [brandGradientStops].
  static const brandGradient = [primaryLight, primary, primaryDark];
  static const brandGradientStops = [0.0, 0.46, 1.0];

  // Neutrals
  static const ink = Color(0xFF1E1519); // primary text / dark surfaces
  static const canvas = Color(0xFFFBF7F9); // app background
  static const surface = Color(0xFFFFFFFF); // cards
  static const border = Color(0xFFEDE2E6); // card / input borders
  static const borderSoft = Color(0xFFF4ECEF); // dividers

  // Text
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF6B5B62);
  static const textMuted = Color(0xFF8C7A83);
  static const textFaint = Color(0xFFB4A0A9);

  // Soft accent fills (chips / badges)
  static const warmFill = Color(0xFFF5E9EE); // primary tint bg
  static const amberFill = Color(0xFFFFF3E0); // rating chip bg
  static const amberInk = Color(0xFFB26A00); // rating chip text
  static const successFill = Color(0xFFE4F6EC); // "open now" bg
  static const successInk = Color(0xFF0E7C3F); // "open now" text
  static const pistachioFill = Color(0xFFEEF5DC); // accent chip bg
  static const pistachioInk = Color(0xFF4C6516); // accent chip text

  // Destructive / neutral fills (cancelled chips, danger dialogs, muted tiles)
  static const dangerFill = Color(0xFFFBE7E4);
  static const dangerInk = Color(0xFFC0392B);
  static const neutralFill = Color(0xFFF2ECEE);

  /// Heavier hairline than [border] — stepper rails, carousel dots.
  static const borderStrong = Color(0xFFE2D3D9);

  /// Border of a card that wants the eye (applied coupon, needs-action row).
  static const attentionBorder = Color(0xFFEFD3DD);

  /// Where a vendor photo is missing, paint [imagePlaceholder] with a
  /// `restaurant` glyph in [imagePlaceholderInk]. The design system is explicit
  /// that this is reproduced rather than replaced with stock photography —
  /// every real food image in the app is a vendor-uploaded Supabase URL.
  static const imagePlaceholder = Color(0xFFF2E6EA);
  static const imagePlaceholderInk = Color(0xFFB4A0A9);

  // Dark-surface palette (driver header, week hero).
  /// A tile sitting on top of an [ink] surface.
  static const inkElevated = Color(0xFF2B1E24);
  static const onDarkSuccess = Color(0xFF5FE39B);
  static const onDarkTrack = Color(0xFF3A2C32);

  /// Unselected bottom-nav / rail item.
  static const navInactive = Color(0xFFAC9EA5);
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

  /// Running in a browser tab wide enough for a genuine desktop layout —
  /// the gate for a dedicated web widget tree rather than a resized mobile
  /// one. `kIsWeb` alone is not enough: a phone browser is still `kIsWeb`
  /// and must keep getting the mobile screen.
  static bool isWebWide(BuildContext context) =>
      kIsWeb && isWide(MediaQuery.sizeOf(context).width);
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

  /// Soft card lift used across the kit. Every shadow here is tinted with
  /// [AppColors.ink] rather than pure black, so shade on the aubergine-tinted
  /// canvas stays in the same hue family as the surfaces it falls on.
  static const card = [
    BoxShadow(
      color: Color(0x121E1519), // rgba(30,21,25,.07)
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  /// One step above [card] — a card that needs attention, a hovered row.
  static const raised = [
    BoxShadow(color: Color(0x141E1519), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// Bottom sheets and anything anchored to the bottom edge: the shadow rises.
  static const overlay = [
    BoxShadow(color: Color(0x1A1E1519), blurRadius: 30, offset: Offset(0, -8)),
  ];

  /// Modal dialogs, which float free of any edge.
  static const dialog = [
    BoxShadow(color: Color(0x241E1519), blurRadius: 40, offset: Offset(0, 16)),
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

/// Display / heading face: Cairo. The design system sets the wordmark and every
/// display line in **Cairo 800 at −0.02em tracking**, which is exactly what
/// [display] produces; [heading] is the same face one weight down.
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
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
  );
}
