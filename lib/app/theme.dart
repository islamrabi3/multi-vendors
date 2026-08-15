import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// The app is light-only, so the status and navigation bars are transparent
/// with *dark* icons throughout.
///
/// Android was drawing the clock, signal and battery in white on our light
/// canvas, which made them invisible: with no style set, Flutter derives the
/// overlay from the AppBar's own colour, and every screen without an AppBar —
/// the shells, the sheets, the splash — fell back to the platform default.
/// Setting it once here and once at startup covers both.
///
/// The naming reads backwards: `Brightness.dark` on these fields means dark
/// *content* on a light bar, which is what we want.
const SystemUiOverlayStyle appOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light, // iOS reads this one.
  systemNavigationBarColor: AppColors.canvas,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarDividerColor: Colors.transparent,
);

/// Marks a text style as "ellipsise rather than overflow".
///
/// This is the only lever that reaches a bare `Text` nobody wrote an
/// `overflow:` on. `Text` resolves its overflow as
/// `overflow ?? effectiveStyle.overflow ?? DefaultTextStyle.overflow`, and the
/// effective style is the enclosing `DefaultTextStyle` merged with the widget's
/// own — which inside a Material button, chip, app bar or list tile *is* the
/// style set here. Setting it once per component style therefore fixes every
/// label in the app at once, including the ones in code that has not been
/// touched. A `DefaultTextStyle` wrapped around the app cannot do this:
/// `Material` installs its own with `overflow: clip`, which wins.
///
/// Long labels now clip with an ellipsis instead of painting past their button
/// and tripping a layout overflow — which is what an Arabic translation of a
/// short English word did on almost every dialog.
TextStyle _clipping(TextStyle style) =>
    style.copyWith(overflow: TextOverflow.ellipsis);

/// Kitchen IN theme — aubergine and pistachio, warm-neutral canvas.
/// Cairo throughout; display and heading ramps come from [AppType].
ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.primaryDark,
    onSecondary: Colors.white,
    tertiary: AppColors.rating,
    onTertiary: AppColors.ink,
    error: Color(0xFFD8412B),
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    surfaceContainerLowest: AppColors.canvas,
    surfaceContainerLow: AppColors.canvas,
    outline: AppColors.border,
    outlineVariant: AppColors.borderSoft,
  );

  final baseText = GoogleFonts.cairoTextTheme().apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  final textTheme = baseText.copyWith(
    displayLarge: AppType.display(34),
    displayMedium: AppType.display(30),
    displaySmall: AppType.display(26),
    headlineMedium: AppType.heading(24),
    headlineSmall: AppType.heading(22),
    titleLarge: AppType.heading(19),
    titleMedium: baseText.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: AppColors.ink,
    ),
    titleSmall: baseText.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
    bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
    bodyMedium: baseText.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.5,
      color: AppColors.textSecondary,
    ),
    bodySmall: baseText.bodySmall?.copyWith(
      fontSize: 12.5,
      color: AppColors.textMuted,
    ),
    labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  return ThemeData(
    colorScheme: scheme,
    fontFamily: GoogleFonts.cairo().fontFamily,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _clipping(AppType.heading(20)),
      systemOverlayStyle: appOverlayStyle,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: GoogleFonts.cairo(color: AppColors.textFaint, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.primary, width: 1.6),
      errorBorder: _inputBorder(scheme.error),
      focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        elevation: 0,
        textStyle: _clipping(
          GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(0, 54),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        textStyle: _clipping(
          GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: _clipping(
          GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      side: const BorderSide(color: AppColors.border),
      labelStyle: _clipping(
        GoogleFonts.cairo(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      secondaryLabelStyle: _clipping(
        GoogleFonts.cairo(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.navInactive,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: GoogleFonts.cairo(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: GoogleFonts.cairo(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.warmFill,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.cairo(
          fontSize: 10.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.navInactive,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.navInactive,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
    ),
    // Even an un-migrated bare `AlertDialog` should read as native: same
    // surface, corner and barrier as `showConfirmDialog` & friends.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xxl),
      ),
      titleTextStyle: _clipping(AppType.heading(19)),
    ),
    // Styled only to carry the overflow flag: an elevated button, a segmented
    // control, a list tile and a dropdown entry all render a bare `Text` the
    // caller never set an overflow on.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        textStyle: _clipping(
          GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          _clipping(
            GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: _clipping(
        GoogleFonts.cairo(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      subtitleTextStyle: _clipping(
        GoogleFonts.cairo(fontSize: 12.5, color: AppColors.textMuted),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: _clipping(GoogleFonts.cairo(fontSize: 14)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: _clipping(GoogleFonts.cairo(color: Colors.white)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
      borderSide: BorderSide(color: color, width: width),
    );
