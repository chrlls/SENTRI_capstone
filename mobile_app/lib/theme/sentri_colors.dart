import 'package:flutter/material.dart';

/// Shared color constants — every screen and widget in this app should
/// reference these rather than hardcoding hex values, so a future palette
/// change only has to happen in one place. Most screens don't reference
/// this file directly — they rely on `main.dart`'s `ThemeData` (built from
/// these same values via `theme/sentri_theme.dart`), so they follow this
/// palette without duplicating it. Reach for a token here directly only
/// when painting something Material's theme doesn't cover (custom
/// `CustomPainter`s, ad hoc tints).
class SentriColors {
  const SentriColors._();

  /// Crimson Blaze — the emergency accent. Reserved for the SOS control
  /// and other genuinely emergency-related emphasis — never a general
  /// primary-action color. Matches SENTRI_DESIGN_SYSTEM_V1.1.md §2.2
  /// `sentri-red`.
  static const Color primaryRed = Color(0xFFB40023);

  /// Dark Red — the critical/emergency-mode color. The SOS hold screen's
  /// full-field background, and the SOS label drawn on the white disc
  /// while holding. Never used as an app-wide background — this is
  /// reserved for the emergency takeover only.
  static const Color emergencyDeep = Color(0xFF710004);

  /// Varden — a subtle contextual/highlight surface, e.g. the sending
  /// status card and the holding-screen countdown text. Never a dominant
  /// background.
  static const Color highlight = Color(0xFFFCF0D6);

  /// surface-primary — the app's base background. Off-white rather than
  /// pure white so that white cards (see [surface]) read as a distinct,
  /// elevated layer without needing a shadow (design doc §6: prefer
  /// surface contrast over heavy shadows).
  static const Color background = Color(0xFFF7F7F5);

  /// surface-white — cards, inputs, and other elevated surfaces. Paired
  /// with [border] for a visible edge against [background].
  static const Color surface = Color(0xFFFFFFFF);

  /// A step below [surface] — used for muted fills (avatar placeholders,
  /// track backgrounds, disabled surfaces), never for a primary card.
  static const Color surfaceMuted = Color(0xFFF0F0F2);

  /// ink-300 — the app's one border color: cards, inputs, dividers,
  /// secondary/outlined buttons. Added as part of the surface-inversion
  /// migration (design doc §2.1/§6) — nothing had a border before this,
  /// which is why card edges used to be nearly invisible.
  static const Color border = Color(0xFFD4D4D4);

  /// Blue Obsidian — primary text, and deep system/navigation surfaces.
  static const Color textPrimary = Color(0xFF0E2632);

  /// Matches the doc's `ink-700` §2.1 — "secondary text": darker/more
  /// legible than [textMuted] for text that needs to read clearly without
  /// competing with primary content (e.g. a greeting's lead-in line).
  static const Color textSecondary = Color(0xFF404040);

  /// Darkened from the doc's literal `ink-500` (#737373): on the new
  /// off-white [background] that value computes to 4.42:1, just under the
  /// WCAG AA 4.5:1 body-text floor. This value clears 4.5:1 on both
  /// [background] (4.75:1) and [surface] (5.10:1) — resolving a real
  /// conflict between the doc's §2.1 color and its own §14 contrast
  /// requirement, not a stylistic choice.
  static const Color textMuted = Color(0xFF6E6E6E);

  /// Cosmos Blue — `info` (§2.3): system/trust/informational messaging,
  /// and the app's non-emergency primary-action color (see
  /// `theme/sentri_theme.dart`). Carries informational text and status
  /// dots on light surfaces; at 13.3:1 on white it clears the AA text
  /// minimum with room to spare.
  static const Color info = Color(0xFF05334A);

  /// Blue Marble — secondary information, location/GPS elements. At
  /// 2.9:1 on white this fails the AA text minimum (4.5:1) and the 3:1
  /// non-text minimum, so it must never be body text or a status dot on
  /// a light surface — use [info] there instead. Reserved for large
  /// supporting graphics and for use against the dark emergency field
  /// (4.3:1 there).
  static const Color locationBlue = Color(0xFF6B9EBD);

  /// Matches the doc's `success` — corrected from #1E8E3E.
  static const Color success = Color(0xFF16803C);

  /// Matches the doc's `warning` — corrected from #B45309.
  static const Color caution = Color(0xFFB54708);
}
