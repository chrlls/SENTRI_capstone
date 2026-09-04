import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';

/// One on/off preference row, shared by the Notifications and
/// Privacy & Security preview screens. Visual match for the Profile
/// tab's other rows (surface fill, 14px radius). The switch's "on"
/// colour comes from the theme's `colorScheme.primary`
/// (`SentriColors.primaryRed`), so it needs no explicit override.
class SettingToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // A `Material` (not a plain `Container`) so the wrapped `SwitchListTile`
    // has a same-colour Material ancestor — otherwise Flutter warns that
    // its ink splashes may be invisible — and so the ripple clips to the
    // rounded corners. Mirrors `_ProfileRow` in `profile_screen.dart`.
    return Material(
      color: SentriColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: SentriColors.textPrimary,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: SentriColors.textMuted,
                ),
              ),
      ),
    );
  }
}
