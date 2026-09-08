import 'package:flutter/material.dart';

import '../theme/sentri_text.dart';
import 'sentri_card.dart';

/// One on/off preference row, shared by the Notifications and
/// Privacy & Security preview screens. Visual match for the Profile
/// tab's other rows via [SentriCard]. The switch's on/off colours and
/// non-colour "checked" icon come from the theme's `switchTheme`
/// (`theme/sentri_theme.dart`) — this widget needs no explicit override.
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
    // No `onTap` on the card itself — `SwitchListTile` already handles the
    // whole-row tap and its own ripple; `SentriCard` here only supplies
    // the shared surface/border/radius.
    return SentriCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title, style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w500)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: SentriText.caption),
      ),
    );
  }
}
