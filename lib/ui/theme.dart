import 'package:flutter/material.dart';

class Brain2Theme {
  static const Color primaryBlue = Color(0xFF1A73E8);
  static const Color primaryBlueDark = Color(0xFF1557B0);
  static const Color primaryBlueLight = Color(0xFFE8F0FE);
  static const Color heroCyan = Color(0xFFEBF5FB);
  static const Color canvasLight = Color(0xFFF8FAFC);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFEDF2F7);
  static const Color greenLight = Color(0xFFE6F4EA);
  static const Color greenDark = Color(0xFF137333);

  // Convenient semantic aliases
  static const Color brandBlue = primaryBlue;
  static const Color brandBlueDark = primaryBlueDark;
  static const Color brandBlueLight = primaryBlueLight;
  static const Color scaffoldBg = canvasLight;
  static const Color cardBg = cardWhite;
  static const Color border = borderLight;
  static const Color heroBorder = borderLight;
  static const Color heroCardBg = heroCyan;
  static const Color pillBadgeBg = primaryBlueLight;
  static const Color textPrimary = textDark;
  static const Color textSecondary = textMuted;

  // Context-aware theme colors
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffoldBgOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF0F172A) : canvasLight;

  static Color cardBgOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E293B) : cardWhite;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF334155) : borderLight;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? const Color(0xFFF8FAFC) : textDark;

  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF94A3B8) : textMuted;

  static Color heroCardBgOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF172554) : heroCyan;

  static Color heroBorderOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E3A8A) : const Color(0xFFD4E8F8);

  static Color pillBadgeBgOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E3A8A) : primaryBlueLight;

  static Color primaryBlueOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF8AB4F8) : primaryBlue;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: primaryBlue,
      onPrimary: Colors.white,
      secondary: greenDark,
      surface: cardWhite,
      onSurface: textDark,
      outline: borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvasLight,
      cardColor: cardWhite,
      dividerColor: borderLight,
      canvasColor: cardWhite,
      appBarTheme: const AppBarTheme(
        backgroundColor: cardWhite,
        foregroundColor: textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: cardWhite,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardWhite,
        elevation: 0,
        indicatorColor: primaryBlueLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primaryBlue,
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
            return const IconThemeData(color: primaryBlue, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w900,
          fontSize: 26,
          letterSpacing: -0.6,
        ),
        headlineSmall: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w900,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: textDark,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: textMuted,
          fontSize: 12,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primaryBlue,
      ),
    );
  }

  static ThemeData dark() {
    const darkBg = Color(0xFF0F172A);
    const darkCard = Color(0xFF1E293B);
    const darkBorder = Color(0xFF334155);
    const darkText = Color(0xFFF8FAFC);
    const darkTextMuted = Color(0xFF94A3B8);
    const darkPrimary = Color(0xFF8AB4F8);

    final scheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: darkPrimary,
      onPrimary: const Color(0xFF0F172A),
      secondary: const Color(0xFF81C995),
      surface: darkCard,
      onSurface: darkText,
      outline: darkBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      cardColor: darkCard,
      dividerColor: darkBorder,
      canvasColor: darkCard,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: darkCard,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        elevation: 0,
        indicatorColor: const Color(0xFF1E3A8A),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: darkPrimary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: darkTextMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkPrimary, size: 22);
          }
          return const IconThemeData(color: darkTextMuted, size: 22);
        }),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w900,
          fontSize: 26,
          letterSpacing: -0.6,
        ),
        headlineSmall: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w900,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: darkText,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: darkTextMuted,
          fontSize: 12,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: darkPrimary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: const Color(0xFF0F172A),
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkPrimary,
      ),
    );
  }
}
