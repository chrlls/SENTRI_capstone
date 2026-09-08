import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';
import '../theme/sentri_tokens.dart';

/// The app's one "grouped information" surface — white fill, a visible
/// 1px border, radius `lg` (16). Replaces the `surface` + `circular(14)`
/// (or 16, depending on the screen) recipe that used to be hand-rolled
/// independently in `profile_screen.dart`, `emergency_contacts_screen.dart`,
/// `setting_toggle_tile.dart`, `home_screen.dart` and elsewhere.
///
/// Pass [onTap] for the same `Material`+`InkWell` tap treatment Profile's
/// rows and Home's tappable cards already used; omit it for a purely
/// informational card. [color]/[borderColor] let a caller apply a semantic
/// tint (e.g. a success- or caution-tinted status card) without
/// reimplementing the shape.
class SentriCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  const SentriCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(SentriSpacing.lg),
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SentriRadius.lg),
      side: BorderSide(color: borderColor ?? SentriColors.border),
    );
    final content = Padding(padding: padding, child: child);

    return Material(
      color: color ?? SentriColors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
