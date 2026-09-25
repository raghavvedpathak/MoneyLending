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
  // MODERN JEWELLERY STUDIO DESIGN SYSTEM (LIGHT PALETTE)
  // ===========================================================================
  static const Color bgDark = Color(0xFFF8FAFC); // Slate-50 Soft Pearl White Canvas
  static const Color cardDark = Color(0xFFFFFFFF); // Pure Crisp White Card Surface
  static const Color subCardDark = Color(0xFFF1F5F9); // Slate-100 Recessed Subcard / Popover
  static const Color borderDark = Color(0xFFE2E8F0); // Slate-200 Subtle 1px Border
  static const Color borderActive = Color(0xFFCBD5E1); // Slate-300 Border Active

  // Semantic Light Aliases
  static const Color bgLight = bgDark;
  static const Color cardLight = cardDark;
  static const Color subCardLight = subCardDark;
  static const Color borderLight = borderDark;

  // Financial Accents (Rich high-contrast tones for Jewellery Light Theme)
  static const Color gold = Color(0xFFD97706); // Amber-600 Rich Jewellery Gold
  static const Color goldGlow = Color(0xFFF59E0B); // Amber-500 Hover / Glow
  static const Color goldDark = Color(0xFFB45309); // Amber-700 Deep Warm Gold
  static const Color silver = Color(0xFF64748B); // Slate-500 Polished Metallic Silver Accent

  static const Color accentCyan = Color(0xFF0284C7); // Sky-600 High Contrast (Given / Loans)
  static const Color emerald = Color(0xFF059669); // Emerald-600 High Contrast (Taken / Repayments)
  static const Color rose = Color(0xFFE11D48); // Rose-600 High Contrast (Risk / Overdue)

  // Typography Tokens (High-contrast Slate)
  static const Color textPrimary = Color(0xFF0F172A); // Slate-900 Deep Charcoal Foreground
  static const Color textSecondary = Color(0xFF475569); // Slate-600 Muted Foreground
  static const Color textMuted = Color(0xFF94A3B8); // Slate-400 Subtle Hint / Inactive

  // Backward-compatible aliases
  static const Color primaryNavy = bgDark;
  static const Color surfaceNavy = cardDark;
  static const Color accentBlue = accentCyan;
  static const Color goldAccent = gold;
  static const Color successGreen = emerald;
  static const Color warningOrange = gold;
  static const Color dangerRed = rose;

  // ===========================================================================
  // MODERN JEWELLERY LIGHT THEMEDATA SPECIFICATION
  // ===========================================================================
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: gold,
      onPrimary: Colors.white,
      secondary: accentCyan,
      onSecondary: Colors.white,
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
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgDark,
      canvasColor: cardDark,
      fontFamily: 'Roboto',
      dividerColor: borderDark,

      // Dropdown & Popup Menu Surfaces
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: const TextStyle(color: textPrimary, fontSize: 14),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll<Color>(cardDark),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          elevation: const WidgetStatePropertyAll<double>(6),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: borderDark, width: 1),
            ),
          ),
        ),
      ),

      // Minimalist Clean White AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: cardDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      // Precision 1px Border Card with Soft Shadow
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

      // Modern NavigationBar (White surface with Amber indicator)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: cardDark,
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
            color: textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: gold, size: 22);
          }
          return const IconThemeData(color: textSecondary, size: 22);
        }),
      ),

      // Compact Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: gold,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // Clean Form Inputs
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

      // Primary Button (Amber-600 with White Text)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),

      // Secondary / Outline Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderDark, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // Ghost / Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      // Dialog Surface
      dialogTheme: DialogThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: borderDark, width: 1),
        ),
      ),

      // Segmented Button
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: gold.withValues(alpha: 0.15),
          selectedForegroundColor: gold,
          foregroundColor: textSecondary,
          side: const BorderSide(color: borderDark, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Tabs
      tabBarTheme: const TabBarThemeData(
        labelColor: gold,
        unselectedLabelColor: textSecondary,
        indicatorColor: gold,
        dividerColor: borderDark,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;

  // ===========================================================================
  // REUSABLE SHADCN ATOMIC COMPONENT DECORATIONS
  // ===========================================================================

  /// Metric Card surface: 1px Slate-200 border with white card surface and soft shadow
  static BoxDecoration get metricCardDecoration => BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderDark, width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
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
      );
}
