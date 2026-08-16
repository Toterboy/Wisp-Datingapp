import 'package:flutter/material.dart';

/// Zentrale Design-Farben der App (warm, einladend, modern).
class AppColors {
  AppColors._();

  /// Primärfarbe (romantisches Korallen/Rosa).
  static const Color primary = Color(0xFFE9457B);
  static const Color primaryLight = Color(0xFFF4799E);
  static const Color primaryDark = Color(0xFFB72E5C);

  /// Akzentfarbe für Sekundäres (Like = grün).
  static const Color like = Color(0xFF4CAF82);
  static const Color nope = Color(0xFFEF5350);
  static const Color superLike = Color(0xFF42A5F5);

  /// Neutrale Hintergründe.
  static const Color backgroundLight = Color(0xFFF7F7FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  /// Verlauf für Hero-Bereiche.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Wiederverwendbare Theme-Definitionen (Material 3).
///
/// Runde Buttons, abgerundete Karten und weiche Schatten werden hier
/// zentral definiert, damit alle Screens konsistent aussehen.
class AppTheme {
  AppTheme._();

  /// Light Theme (Material 3).
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.surfaceLight,
        ),
        scaffoldBackgroundColor: AppColors.backgroundLight,
        cardTheme: _cardTheme(AppColors.surfaceLight),
        elevatedButtonTheme: _elevatedButtonTheme,
        filledButtonTheme: _filledButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceLight),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          elevation: 8,
          selectedItemColor: AppColors.primary,
        ),
        // Snackbars als schwebende Bubbles am unteren Rand – konsistent
        // für Light- und Dark-Mode.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        extensions: const <ThemeExtension<dynamic>>[
          BlindModeTheme(placeholderColor: Color(0xFFE1E1EC)),
        ],
      );

  /// Dark Theme (Material 3).
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: AppColors.surfaceDark,
        ),
        scaffoldBackgroundColor: AppColors.backgroundDark,
        cardTheme: _cardTheme(AppColors.surfaceDark),
        elevatedButtonTheme: _elevatedButtonTheme,
        filledButtonTheme: _filledButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceDark),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          elevation: 8,
          selectedItemColor: AppColors.primaryLight,
        ),
        // Snackbars als schwebende Bubbles am unteren Rand – konsistent
        // für Light- und Dark-Mode.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        extensions: const <ThemeExtension<dynamic>>[
          BlindModeTheme(placeholderColor: Color(0xFF2C2C2C)),
        ],
      );

  static CardThemeData _cardTheme(Color surface) => CardThemeData(
        color: surface,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.12),
      );

  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static FilledButtonThemeData get _filledButtonTheme => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static InputDecorationTheme _inputDecorationTheme(Color surface) =>
      InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primaryLight,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

/// Theme-Extension für Blind-Mode-spezifische Farben.
class BlindModeTheme extends ThemeExtension<BlindModeTheme> {
  const BlindModeTheme({required this.placeholderColor});

  /// Farbe des Platzhalters, wenn Fotos ausgeblendet sind.
  final Color placeholderColor;

  @override
  BlindModeTheme copyWith({Color? placeholderColor}) {
    return BlindModeTheme(
      placeholderColor: placeholderColor ?? this.placeholderColor,
    );
  }

  @override
  BlindModeTheme lerp(ThemeExtension<BlindModeTheme>? other, double t) {
    if (other is! BlindModeTheme) return this;
    return BlindModeTheme(
      placeholderColor:
          Color.lerp(placeholderColor, other.placeholderColor, t) ??
              placeholderColor,
    );
  }
}
