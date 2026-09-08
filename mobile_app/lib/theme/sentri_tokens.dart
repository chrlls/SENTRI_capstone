/// Spacing scale — SENTRI_DESIGN_SYSTEM_V1.1.md §4. A 4px base unit with an
/// 8px visual rhythm. Prefer these over arbitrary values (13, 17, 21...).
class SentriSpacing {
  const SentriSpacing._();

  /// Tight relationship between elements (e.g. an icon and its label).
  static const double xs = 4;

  /// Icon/text gaps, compact grouping.
  static const double sm = 8;

  /// Internal component spacing.
  static const double md = 12;

  /// Standard component padding.
  static const double lg = 16;

  /// Section separation.
  static const double xl = 24;

  /// Major content separation.
  static const double xxl = 32;

  /// Large section spacing.
  static const double xxxl = 40;

  /// Screen-level spacing.
  static const double screen = 48;
}

/// Border-radius scale — SENTRI_DESIGN_SYSTEM_V1.1.md §5. Radius
/// communicates component hierarchy; don't make every component
/// pill-shaped or heavily rounded.
class SentriRadius {
  const SentriRadius._();

  /// Inputs / compact controls.
  static const double sm = 10;

  /// Buttons / standard controls.
  static const double md = 12;

  /// Cards / containers.
  static const double lg = 16;

  /// Bottom sheets / large surfaces.
  static const double xl = 24;

  /// Status pills / tags.
  static const double pill = 999;
}
