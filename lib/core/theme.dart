import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FluxThemeMode { classic, neoPop }

extension FluxThemeModeX on FluxThemeMode {
  String get storageValue =>
      this == FluxThemeMode.neoPop ? 'neopop' : 'classic';

  String get label => this == FluxThemeMode.neoPop ? 'NeoPOP' : 'Current';

  static FluxThemeMode fromStorageValue(String? value) {
    return value == 'neopop' ? FluxThemeMode.neoPop : FluxThemeMode.classic;
  }
}

class AppTheme {
  static const _prefsKey = 'appThemeMode';

  static final ValueNotifier<FluxThemeMode> modeNotifier =
      ValueNotifier<FluxThemeMode>(FluxThemeMode.classic);

  static const Color bg = Color(0xFF0A0A0F);
  static const Color bgCard = Color(0xFF13131A);
  static const Color bgCardElevated = Color(0xFF1C1C28);
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentGlow = Color(0x336C63FF);
  static const Color accentLight = Color(0xFF9D96FF);
  static const Color success = Color(0xFF22D3A5);
  static const Color successGlow = Color(0x3322D3A5);
  static const Color warning = Color(0xFFFFA63D);
  static const Color error = Color(0xFFFF4D6A);
  static const Color errorGlow = Color(0x33FF4D6A);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFADADB8);
  static const Color textMuted = Color(0xFF6B6B7B);
  static const Color border = Color(0xFF2A2A38);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF9D55FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF22D3A5), Color(0xFF06B6D4)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0A0A0F), Color(0xFF0F0F18)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    modeNotifier.value = FluxThemeModeX.fromStorageValue(
      prefs.getString(_prefsKey),
    );
  }

  static Future<void> setThemeMode(FluxThemeMode mode) async {
    if (modeNotifier.value == mode) return;
    modeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.storageValue);
    applySystemUi();
  }

  static FluxThemeMode get currentMode => modeNotifier.value;
  static bool get isNeoPop => currentMode == FluxThemeMode.neoPop;

  static double get cardRadius => 16;
  static double get cardRadiusLarge => 20;
  static double get inputRadius => 12;
  static double get buttonRadius => 12;

  static BorderRadius get cardBorderRadius => BorderRadius.circular(cardRadius);
  static BorderRadius get cardBorderRadiusLarge =>
      BorderRadius.circular(cardRadiusLarge);
  static BorderRadius get buttonBorderRadius =>
      BorderRadius.circular(buttonRadius);

  static List<BoxShadow> get cardShadow => const [];

  static ThemeData get materialTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentLight,
        surface: bgCard,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          color: textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: textSecondary,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: textMuted,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: cardBorderRadius,
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCardElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: buttonBorderRadius),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          shape: RoundedRectangleBorder(borderRadius: buttonBorderRadius),
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgCardElevated,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static SystemUiOverlayStyle get systemUiOverlayStyle =>
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: Brightness.light,
      );

  static void applySystemUi() {
    SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
  }
}
