import 'package:flutter/material.dart';

/// The colours, radii and type of the web client, in one place, so the app and
/// the browser build read as the same product.
class ReveTokens {
  const ReveTokens._();

  static const Color seed = Color(0xFF5B3FD6);

  /// The violet used for the brand gradient.
  static const Color brandA = Color(0xFF5B3FD6);
  static const Color brandB = Color(0xFF8B5CF6);
  static const Color brandC = Color(0xFF38BDF8);

  static const double rXs = 8;
  static const double rS = 12;
  static const double rM = 16;
  static const double rL = 22;
  static const double rXl = 28;

  static const List<Color> brandGradient = [brandA, brandB];
}

/// Explicit token overrides on top of a seeded scheme: `fromSeed` alone drifts
/// away from the web palette (especially the near-black dark surface).
ColorScheme reveScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: ReveTokens.seed,
    brightness: brightness,
  );
  if (brightness == Brightness.dark) {
    return base.copyWith(
      primary: const Color(0xFFC9BFFF),
      onPrimary: const Color(0xFF2F0D8F),
      primaryContainer: const Color(0xFF4530A8),
      onPrimaryContainer: const Color(0xFFE7DFFF),
      secondaryContainer: const Color(0xFF453A6F),
      onSecondaryContainer: const Color(0xFFE5DEFF),
      tertiaryContainer: const Color(0xFF1B4A68),
      onTertiaryContainer: const Color(0xFFCFE6FF),
      surface: const Color(0xFF101014),
      surfaceContainerLowest: const Color(0xFF0B0B0F),
      surfaceContainerLow: const Color(0xFF17171C),
      surfaceContainer: const Color(0xFF1C1C22),
      surfaceContainerHigh: const Color(0xFF26262D),
      surfaceContainerHighest: const Color(0xFF313138),
      onSurface: const Color(0xFFE5E1E9),
      onSurfaceVariant: const Color(0xFFC8C5D0),
      outline: const Color(0xFF918F9A),
      outlineVariant: const Color(0xFF46464F),
      error: const Color(0xFFFFB4AB),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
    );
  }
  return base.copyWith(
    primary: const Color(0xFF5B3FD6),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE7DFFF),
    onPrimaryContainer: const Color(0xFF190066),
    secondaryContainer: const Color(0xFFE5DEFF),
    onSecondaryContainer: const Color(0xFF1C1145),
    tertiaryContainer: const Color(0xFFCFE6FF),
    onTertiaryContainer: const Color(0xFF001E33),
    surface: const Color(0xFFFBF8FF),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF5F2FA),
    surfaceContainer: const Color(0xFFEFECF4),
    surfaceContainerHigh: const Color(0xFFE9E6EF),
    surfaceContainerHighest: const Color(0xFFE3E0E9),
    onSurface: const Color(0xFF1B1B21),
    onSurfaceVariant: const Color(0xFF46464F),
    outline: const Color(0xFF777680),
    outlineVariant: const Color(0xFFC8C5D0),
    error: const Color(0xFFBA1A1A),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
  );
}

ThemeData reveTheme(Brightness brightness) {
  final cs = reveScheme(brightness);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.standard,
  );

  final text = base.textTheme.copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.4),
  );

  return base.copyWith(
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rL),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: BorderSide(color: cs.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        highlightColor: cs.primary.withValues(alpha: 0.10),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.secondaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: cs.primary, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rXl),
      ),
      titleTextStyle: text.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ReveTokens.rXl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface, fontSize: 13),
      actionTextColor: cs.inversePrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rM),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
      circularTrackColor: cs.surfaceContainerHighest,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rM),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rM),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReveTokens.rM + 2),
      ),
    ),
  );
}
