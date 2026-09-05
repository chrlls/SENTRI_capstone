import 'package:flutter/material.dart';

/// Shared color constants — every screen and widget in this app should
/// reference these rather than hardcoding hex values, so a future palette
/// change (like this white/red one, replacing the prior dark #0B0D13
/// theme) only has to happen in one place. `login_screen.dart` and
/// `register_screen.dart` don't reference this file directly — they rely
/// entirely on Material 3's generated ColorScheme from `main.dart`'s
/// `ThemeData(colorSchemeSeed: SentriColors.primaryRed, ...)`, which is
/// itself built from these same values, so they still follow this
/// palette without duplicating it.
class SentriColors {
  const SentriColors._();

  /// The one accent color across the app — SOS button solid states,
  /// primary CTA buttons, and any other primary-action accent. Matches
  /// SENTRI_DESIGN_SYSTEM_V1.1.md §2.2 `sentri-red` — corrected from the
  /// brighter #EB1B1D this shipped with, which had drifted from the doc.
  static const Color primaryRed = Color(0xFFD92D20);

  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFAFAFA);
  static const Color surfaceMuted = Color(0xFFF0F0F2);

  static const Color textPrimary = Color(0xFF1A1A1A);

  /// Matches the doc's `ink-700` §2.1 — "secondary text": darker/more
  /// legible than [textMuted] for text that needs to read clearly without
  /// competing with primary content (e.g. a greeting's lead-in line).
  static const Color textSecondary = Color(0xFF404040);

  /// Matches the doc's `ink-500` — corrected from #6B7280 (Tailwind's
  /// gray-500), which was never a value the doc defined.
  static const Color textMuted = Color(0xFF737373);

  /// `info` (§2.3): informational/neutral system messaging. Not yet used
  /// anywhere in the shipped app — added so screens have it available
  /// instead of reaching for an ad hoc blue.
  static const Color info = Color(0xFF2563EB);

  /// The SOS button is solid `primaryRed` in every phase now (idle,
  /// holding, sent) per the reference image's "solid red badge at rest"
  /// look — state is communicated by the glow/ring/dots, not by the
  /// disc changing color. Kept as separate names (not all just
  /// `primaryRed` inline) so each phase's intent stays legible at the
  /// call site, even though they resolve to the same value today.
  static const Color sosIdle = primaryRed;
  static const Color sosHoldStart = primaryRed;
  static const Color sosAlarm = primaryRed;

  /// Soft halo rings behind the SOS button's solid disc, always visible
  /// (not just while holding) — the reference image's layered-circle
  /// glow. Low opacity outer ring, slightly stronger inner ring.
  static const Color glowOuter = Color(0x14EB1B1D);
  static const Color glowInner = Color(0x29EB1B1D);

  /// Matches the doc's `success` — corrected from #1E8E3E.
  static const Color success = Color(0xFF16803C);

  /// Matches the doc's `warning` — corrected from #B45309.
  static const Color caution = Color(0xFFB54708);
}
