import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_preferences_store.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/setting_toggle_tile.dart';

/// In-memory Notifications preferences preview, reached from the Profile
/// tab. Pushed on top of the app shell, so the floating nav bar is
/// intentionally not shown here (same as `EmergencyContactsScreen`).
///
/// Nothing on this screen is persisted or sent anywhere — see
/// [NotificationPreferencesStore]. It is a real, working UI previewing a
/// feature whose backend endpoint does not exist yet, not a "coming
/// soon" placeholder.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<NotificationPreferencesStore>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SentriSpacing.xl),
          children: [
            SettingToggleTile(
              title: 'Incident status updates',
              subtitle: 'Alerts when a dispatcher acts on your SOS',
              value: prefs.incidentStatusUpdates,
              onChanged: (value) => prefs.incidentStatusUpdates = value,
            ),
            const SizedBox(height: SentriSpacing.md),
            SettingToggleTile(
              title: 'Emergency contact alerts',
              subtitle: 'Notify me when my emergency contacts are contacted',
              value: prefs.emergencyContactAlerts,
              onChanged: (value) => prefs.emergencyContactAlerts = value,
            ),
            const SizedBox(height: SentriSpacing.md),
            SettingToggleTile(
              title: 'System announcements',
              subtitle: 'Service updates and maintenance notices',
              value: prefs.systemAnnouncements,
              onChanged: (value) => prefs.systemAnnouncements = value,
            ),
          ],
        ),
      ),
    );
  }
}
