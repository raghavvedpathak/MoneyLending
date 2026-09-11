import 'package:flutter/material.dart';

/// Material 3 Modern Dark Mode Luxe Design System for MoneyLending / ByajBook.
/// Curated aesthetic: Ultra-sleek OLED Dark (#0B0F19), glowing Amber/Gold (#F59E0B)
/// accents, midnight slate cards (#131B2E), and subtle glassmorphic borders (#222F48).
class AppTheme {
  AppTheme._();

  // ===========================================================================
  // LUXURY COLOR TOKENS
  // ===========================================================================
  static const Color bgDark = Color(0xFF0B0F19);
  static const Color cardDark = Color(0xFF131B2E);
  static const Color subCardDark = Color(0xFF0E1526);
  static const Color borderDark = Color(0xFF222F48);

  static const Color gold = Color(0xFFF59E0B);
  static const Color goldGlow = Color(0xFFFBBF24);
  static const Color goldDark = Color(0xFFB45309);

  static const Color accentCyan = Color(0xFF38BDF8);
  static const Color emerald = Color(0xFF10B981);
  static const Color rose = Color(0xFFF43F5E);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Legacy aliases
  static const Color primaryNavy = Color(0xFF0F172A);
  static const Color surfaceNavy = cardDark;
  static const Color accentBlue = accentCyan;
  static const Color goldAccent = gold;
  static const Color successGreen = emerald;
  static const Color warningOrange = gold;
  static const Color dangerRed = rose;

  // ===========================================================================
  // MODERN DARK MODE LUXE THEME
  // ===========================================================================
  static ThemeData get darkTheme {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: gold,
      onPrimary: bgDark,
      secondary: accentCyan,
      onSecondary: bgDark,
      tertiary: emerald,
      error: rose,
      onError: Colors.white,
      surface: cardDark,
      onSurface: textPrimary,
      surfaceContainer: subCardDark,
      outline: borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgDark,
      fontFamily: 'Roboto',
      dividerColor: borderDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderDark, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: const Color(0xFF080C14),
        indicatorColor: gold.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: gold,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: gold, size: 24);
          }
          return const IconThemeData(color: textMuted, size: 24);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: gold,
        foregroundColor: bgDark,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: subCardDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gold, width: 1.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: bgDark,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: gold.withValues(alpha: 0.15),
          selectedForegroundColor: gold,
          foregroundColor: textSecondary,
          side: const BorderSide(color: borderDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: gold,
        unselectedLabelColor: textMuted,
        indicatorColor: gold,
        dividerColor: borderDark,
      ),
    );
  }

  // ===========================================================================
  // REUSABLE COMPONENT DECORATIONS
  // ===========================================================================

  /// Metric Card surface with subtle elevation shadow and luxury glass border
  static BoxDecoration get metricCardDecoration => BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Sub-card surface (recessed background for nested tables and forms)
  static BoxDecoration get subCardDecoration => BoxDecoration(
        color: subCardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark),
      );

  /// Status badge or pill decoration (15% tint with 30% border)
  static BoxDecoration badgeDecoration(Color accent, {double borderRadius = 6}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      );

  /// Standard tag decoration for IDs, labels, and chips
  static BoxDecoration tagDecoration({Color? bg, Color? border, double borderRadius = 6}) =>
      BoxDecoration(
        color: bg ?? subCardDark,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border ?? borderDark),
      );

  /// Alert or banner callout container (12% tint with 35% border)
  static BoxDecoration bannerDecoration(Color accent, {double borderRadius = 12}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      );

  /// Metric or statistical summary box container
  static BoxDecoration statBoxDecoration(Color accent, {double borderRadius = 10}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      );

  /// Bottom sheet drag handle
  static BoxDecoration get handleDecoration => BoxDecoration(
        color: borderDark,
        borderRadius: BorderRadius.circular(2),
      );

  /// Empty state container decoration
  static BoxDecoration get emptyStateDecoration => BoxDecoration(
        color: subCardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderDark),
      );

  // ===========================================================================
  // SNACKBAR HELPERS
  // ===========================================================================

  static SnackBar successSnackBar(String message) => SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static SnackBar errorSnackBar(String message) => SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: rose,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  // ===========================================================================
  // TYPOGRAPHY HELPERS
  // ===========================================================================

  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 13,
    color: textSecondary,
  );

  static const TextStyle mutedStyle = TextStyle(
    fontSize: 12,
    color: textMuted,
  );

  static const TextStyle sectionHeaderStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static TextStyle badgeTextStyle(
    Color color, {
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.bold,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );

  // Light theme alias
  static ThemeData get lightTheme => darkTheme;
}
