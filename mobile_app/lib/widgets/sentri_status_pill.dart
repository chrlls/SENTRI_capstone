import 'package:flutter/material.dart';

import '../theme/sentri_tokens.dart';

/// A tinted status indicator — color + label, optionally with a leading
/// icon. Replaces two independently hand-rolled `_StatusBadge` widgets
/// (`profile_screen.dart`, `alert_history_screen.dart`) that used
/// different pill radii (999 vs 20) and inconsistent icon presence.
///
/// Never the only signal for a state (design doc §11: "never communicate
/// important status through color alone") — [label] is required, and
/// [icon] is encouraged wherever the status has an obvious one.
class SentriStatusPill extends StatelessWidget {
  final Color color;
  final String label;
  final IconData? icon;

  const SentriStatusPill({
    super.key,
    required this.color,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SentriSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SentriRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
