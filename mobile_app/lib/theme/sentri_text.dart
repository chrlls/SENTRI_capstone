import 'package:flutter/material.dart';

import 'sentri_colors.dart';

/// Named text styles matching SENTRI_DESIGN_SYSTEM_V1.1.md §3.2's type
/// scale, so screens stop hand-writing one-off `TextStyle` literals (the
/// app had ~16 distinct inline font sizes before this). Every style
/// defaults to [SentriColors.textPrimary]; override `color` at the call
/// site for secondary/muted/semantic text — these are shape, not final
/// color.
///
/// `h2`'s weight is [FontWeight.w600], not the doc's literal 650 — Flutter
/// has no w650, and 600 is the nearest defined weight (also used by `h3`,
/// which is the intended effect: h2 and h3 read at the same weight,
/// distinguished by size).
class SentriText {
  const SentriText._();

  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: SentriColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: SentriColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: SentriColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: SentriColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: SentriColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: SentriColors.textPrimary,
    height: 1.4,
  );

  /// Form labels / controls.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: SentriColors.textPrimary,
  );

  /// Metadata / supporting information.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: SentriColors.textMuted,
  );
}
