import 'package:flutter/material.dart';

import 'sentri_colors.dart';
import 'sentri_text.dart';
import 'sentri_tokens.dart';

/// Centralised `ThemeData` for the whole app. Everything a screen would
/// otherwise hand-roll (button shape/height, input borders, switch/
/// checkbox colors, divider color, progress-indicator color, typography)
/// lives here once, so a palette or shape change never has to be repeated
/// per screen.
///
/// The one deliberate design choice worth calling out: [ColorScheme.primary]
/// is [SentriColors.info] (Cosmos Blue), **not** the emergency red. Material
/// 3 derives a long list of defaults from `primary` — switch "on", checkbox
/// "checked", text-field focus border, `CircularProgressIndicator`,
/// `RefreshIndicator` — and none of those are emergency actions. Pinning
/// `primary` to blue is what makes [SentriColors.primaryRed] an opt-in,
/// deliberate choice (the SOS control paints it directly) rather than the
/// color Material reaches for by default everywhere.
class SentriTheme {
  const SentriTheme._();

  static const TextStyle _buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: SentriColors.info,
          brightness: Brightness.light,
        ).copyWith(
          primary: SentriColors.info,
          onPrimary: Colors.white,
          surface: SentriColors.background,
          surfaceContainerLowest: SentriColors.surface,
          onSurface: SentriColors.textPrimary,
          onSurfaceVariant: SentriColors.textMuted,
          outline: SentriColors.border,
          outlineVariant: SentriColors.border,
          error: SentriColors.primaryRed,
          onError: Colors.white,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: SentriColors.background,
      colorScheme: colorScheme,

      textTheme: const TextTheme(
        displayLarge: SentriText.display,
        headlineLarge: SentriText.h1,
        headlineMedium: SentriText.h2,
        headlineSmall: SentriText.h3,
        titleLarge: SentriText.h3,
        titleMedium: SentriText.body,
        bodyLarge: SentriText.body,
        bodyMedium: SentriText.bodySmall,
        bodySmall: SentriText.caption,
        labelLarge: SentriText.label,
        labelMedium: SentriText.label,
        labelSmall: SentriText.caption,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: SentriColors.background,
        foregroundColor: SentriColors.textPrimary,
        elevation: 0,
        titleTextStyle: SentriText.h3,
      ),

      // Standard input — design doc §9: white fill, ink-300 border,
      // radius 10-12, ~48px tall. Focus uses the non-emergency accent
      // (Cosmos Blue) so a focused field is never confusable with an
      // error one; error uses the emergency red plus (at each call site)
      // explicit error text, never color alone.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SentriColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SentriSpacing.lg,
          vertical: SentriSpacing.lg,
        ),
        labelStyle: const TextStyle(
          color: SentriColors.textMuted,
          fontSize: 16,
        ),
        hintStyle: const TextStyle(color: SentriColors.textMuted),
        helperStyle: SentriText.caption,
        errorStyle: const TextStyle(
          color: SentriColors.primaryRed,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.info, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.primaryRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.primaryRed, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          borderSide: const BorderSide(color: SentriColors.surfaceMuted),
        ),
      ),

      // Primary button — design doc §8: filled, radius 12, ~48px,
      // weight 600. Reserved for the screen's one dominant action; NOT
      // automatically red (see class doc comment) — screens that need the
      // emergency treatment set `backgroundColor: SentriColors.primaryRed`
      // explicitly at the call site (there are none outside the SOS flow
      // today).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SentriColors.info,
          foregroundColor: Colors.white,
          disabledBackgroundColor: SentriColors.surfaceMuted,
          disabledForegroundColor: SentriColors.textMuted,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: SentriSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SentriRadius.md),
          ),
          textStyle: _buttonLabel,
        ),
      ),

      // Secondary button — design doc §8: white/surface fill, ink-900
      // text, ink-300 border, same radius/height as primary.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SentriColors.textPrimary,
          disabledForegroundColor: SentriColors.textMuted,
          side: const BorderSide(color: SentriColors.border),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: SentriSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SentriRadius.md),
          ),
          textStyle: _buttonLabel,
        ),
      ),

      // Tertiary/text button — design doc §5: Blue Obsidian or Cosmos
      // Blue. Cosmos Blue is used here so a text button reads as
      // distinctly tappable rather than blending into ordinary
      // Blue-Obsidian body text.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SentriColors.info,
          disabledForegroundColor: SentriColors.textMuted,
          minimumSize: const Size(44, 44),
          textStyle: _buttonLabel.copyWith(fontSize: 14),
        ),
      ),

      // Design doc §6/§13: OFF vs ON must never rely on color alone —
      // the thumb also carries a check icon once selected, on top of the
      // built-in position/size/track-fill cues.
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SentriColors.surfaceMuted;
          }
          return states.contains(WidgetState.selected)
              ? SentriColors.info
              : SentriColors.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.transparent
              : SentriColors.border;
        }),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) {
            return null;
          }
          return const Icon(Icons.check, size: 14, color: SentriColors.info);
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SentriColors.surfaceMuted;
          }
          return states.contains(WidgetState.selected)
              ? SentriColors.info
              : Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: SentriColors.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SentriColors.info,
        linearTrackColor: SentriColors.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),

      dividerTheme: const DividerThemeData(
        color: SentriColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
