import 'package:flutter/material.dart';

/// Central Design System for MoneyLending.
///
/// Implements the Shadcn UI (Zinc Theme) design system:
/// - Deep Zinc background (#09090B)
/// - Zinc 900 card surfaces (#18181B)
/// - Zinc 800 borders & popovers (#27272A)
/// - Crisp 1px borders, compact radii (8-12px)
/// - High-contrast Zinc typography (#FAFAFA / #A1A1AA)
/// - Luxury gold financial accent (#F59E0B)
///
/// ARCHITECTURAL GUARANTEE:
/// All styling throughout the entire application flows through this central file.
/// If migrating or switching to another styling engine (such as `mix`),
/// ONLY this file needs to be updated — avoiding changes to individual screens.
class AppTheme {
  AppTheme._();

  // ===========================================================================
  // SHADCN ZINC COLOR TOKENS
  // ===========================================================================
  static const Color bgDark = Color(0xFF09090B); // Shadcn Zinc-950 Background
  static const Color cardDark = Color(0xFF18181B); // Shadcn Zinc-900 Card
  static const Color subCardDark = Color(0xFF27272A); // Shadcn Zinc-800 Subcard / Popover
  static const Color borderDark = Color(0xFF27272A); // Shadcn Zinc-800 Border
  static const Color borderActive = Color(0xFF3F3F46); // Shadcn Zinc-700 Border Active

  // Financial Accents
  static const Color gold = Color(0xFFF59E0B); // Amber-500 Primary Financial Accent
  static const Color goldGlow = Color(0xFFFBBF24); // Amber-400 Hover / Glow
  static const Color goldDark = Color(0xFFD97706); // Amber-600 Dark

  static const Color accentCyan = Color(0xFF38BDF8); // Sky-400 (Given / Loans)
  static const Color emerald = Color(0xFF10B981); // Emerald-500 (Taken / Success)
  static const Color rose = Color(0xFFF43F5E); // Rose-500 (Risk / Overdue)

  // Typography Tokens
  static const Color textPrimary = Color(0xFFFAFAFA); // Shadcn Zinc-50 Foreground
  static const Color textSecondary = Color(0xFFA1A1AA); // Shadcn Zinc-400 Muted Foreground
  static const Color textMuted = Color(0xFF71717A); // Shadcn Zinc-500 Muted

  // Backward-compatible aliases
  static const Color primaryNavy = bgDark;
  static const Color surfaceNavy = cardDark;
  static const Color accentBlue = accentCyan;
  static const Color goldAccent = gold;
  static const Color successGreen = emerald;
  static const Color warningOrange = gold;
  static const Color dangerRed = rose;

  // ===========================================================================
  // SHADCN ZINC THEMEDATA SPECIFICATION
  // ===========================================================================
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
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
      canvasColor: cardDark,
      fontFamily: 'Roboto',
      dividerColor: borderDark,

      // Shadcn Dropdown & Popup Menu Surfaces
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: const TextStyle(color: textPrimary, fontSize: 14),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll<Color>(cardDark),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          elevation: const WidgetStatePropertyAll<double>(8),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: borderDark, width: 1),
            ),
          ),
        ),
      ),

      // Shadcn Minimalist AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: textPrimary,
        ),
      ),

      // Shadcn Precision 1px Border Card
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderDark, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Shadcn NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: bgDark,
        indicatorColor: gold.withValues(alpha: 0.15),
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
            return const IconThemeData(color: gold, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
      ),

      // Shadcn Compact Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: gold,
        foregroundColor: bgDark,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // Shadcn Minimalist 1px Border Form Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderDark, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderDark, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),

      // Shadcn Primary Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: bgDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),

      // Shadcn Secondary / Outline Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderDark, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // Shadcn Ghost / Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      // Shadcn Dialog Surface
      dialogTheme: DialogThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),

      // Shadcn BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: borderDark, width: 1),
        ),
      ),

      // Shadcn Segmented Button
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: subCardDark,
          selectedForegroundColor: gold,
          foregroundColor: textSecondary,
          side: const BorderSide(color: borderDark, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Shadcn Tabs
      tabBarTheme: const TabBarThemeData(
        labelColor: gold,
        unselectedLabelColor: textMuted,
        indicatorColor: gold,
        dividerColor: borderDark,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ===========================================================================
  // REUSABLE SHADCN ATOMIC COMPONENT DECORATIONS
  // ===========================================================================

  /// Metric Card surface: 1px Zinc-800 border with dark card surface
  static BoxDecoration get metricCardDecoration => BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderDark, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Sub-card surface (recessed background for nested tables and forms)
  static BoxDecoration get subCardDecoration => BoxDecoration(
        color: subCardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderDark, width: 1),
      );

  /// Shadcn Pill Badge: subtle 12% tint with matching 1px border
  static BoxDecoration badgeDecoration(Color accent, {double borderRadius = 6}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
      );

  /// Standard tag decoration for IDs, labels, and chips
  static BoxDecoration tagDecoration({Color? bg, Color? border, double borderRadius = 6}) =>
      BoxDecoration(
        color: bg ?? subCardDark,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border ?? borderDark, width: 1),
      );

  /// Shadcn Alert Banner: 1px crisp border with 10% tint
  static BoxDecoration bannerDecoration(Color accent, {double borderRadius = 10}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1),
      );

  /// Metric or statistical summary box container
  static BoxDecoration statBoxDecoration(Color accent, {double borderRadius = 8}) =>
      BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 1),
      );

  /// Bottom sheet drag handle
  static BoxDecoration get handleDecoration => BoxDecoration(
        color: borderDark,
        borderRadius: BorderRadius.circular(2),
      );

  /// Empty state container decoration
  static BoxDecoration get emptyStateDecoration => BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderDark, width: 1),
      );

  // ===========================================================================
  // SNACKBAR HELPERS
  // ===========================================================================

  static SnackBar successSnackBar(String message) => SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  static SnackBar errorSnackBar(String message) => SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: rose,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  // ===========================================================================
  // TYPOGRAPHY HELPERS
  // ===========================================================================

  static const TextStyle titleStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
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
    fontSize: 15,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.1,
    color: textPrimary,
  );

  static TextStyle badgeTextStyle(
    Color color, {
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );

  // Light theme alias
  static ThemeData get lightTheme => darkTheme;
}
