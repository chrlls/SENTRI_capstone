import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/privacy_preferences_store.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/setting_toggle_tile.dart';

/// In-memory Privacy & Security preferences preview, reached from the
/// Profile tab. Pushed on top of the app shell, so the floating nav bar
/// is intentionally not shown here (same as `EmergencyContactsScreen`).
///
/// Every toggle here is display-only this pass — see
/// [PrivacyPreferencesStore]. There is deliberately no "Change password"
/// row: no such endpoint exists (`API_CONTRACTS.md`), and a
/// visible-but-inert row would be a dead affordance (this app's
/// no-dead-links rule).
class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PrivacyPreferencesStore>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SentriSpacing.xl),
          children: [
            SettingToggleTile(
              title: 'Share precise location with responders',
              subtitle: 'Send your exact GPS fix, not an approximate area',
              value: prefs.sharePreciseLocationWithResponders,
              onChanged: (value) =>
                  prefs.sharePreciseLocationWithResponders = value,
            ),
            const SizedBox(height: SentriSpacing.md),
            SettingToggleTile(
              title: 'Allow diagnostics reports',
              subtitle: 'Share anonymous crash and performance data',
              value: prefs.allowDiagnosticsReports,
              onChanged: (value) => prefs.allowDiagnosticsReports = value,
            ),
          ],
        ),
      ),
    );
  }
}
