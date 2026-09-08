import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/sos_controller.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'services/emergency_contacts_store.dart';
import 'services/incident_status_store.dart';
import 'services/notification_preferences_store.dart';
import 'services/privacy_preferences_store.dart';
import 'theme/sentri_theme.dart';
import 'widgets/sos_reveal/sos_reveal_host.dart';

void main() {
  runApp(const SentriApp());
}

/// docs/decisions/28-flutter-manual-sos-mvp.md: register/login/SOS, gated
/// purely by in-memory AuthProvider state — login/register push straight
/// to the next screen on success, so there is no separate route-guard
/// layer to build for a flow this small.
///
/// [IncidentStatusStore] is provided here, above all screens, on purpose:
/// Decision 31 §1 requires the incident-status poller to outlive screen
/// navigation and never be gated on the current screen.
class SentriApp extends StatelessWidget {
  const SentriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => IncidentStatusStore()),
        // Session-only, in-memory emergency contacts (no persistence, no
        // endpoint yet). Root-provided so the list outlives navigation
        // between the Profile tab and the Emergency Contacts screen; it
        // resets on app restart, on purpose.
        ChangeNotifierProvider(create: (_) => EmergencyContactsStore()),
        // Same non-persistence contract as EmergencyContactsStore — the
        // notification-preferences and privacy-preferences endpoints
        // don't exist yet. Root-provided so toggle state survives
        // navigation between the Profile tab and each screen; resets on
        // app restart.
        ChangeNotifierProvider(create: (_) => NotificationPreferencesStore()),
        ChangeNotifierProvider(create: (_) => PrivacyPreferencesStore()),
        // The manual-SOS submission flow, shared by the SOS screen and the
        // app shell's nav-bar SOS button (task Resolution D). Depends on
        // the two providers above; created once — its inputs are stable.
        ChangeNotifierProxyProvider2<AuthProvider, IncidentStatusStore,
            SosController>(
          create: (context) => SosController(
            context.read<AuthProvider>().apiClient,
            context.read<IncidentStatusStore>(),
          ),
          update: (context, auth, store, previous) =>
              previous ?? SosController(auth.apiClient, store),
        ),
      ],
      child: MaterialApp(
        title: 'SENTRI',
        debugShowCheckedModeBanner: false,
        // Hosts the SOS emergency-reveal overlay above the Navigator, so a
        // hold that started on one screen and hands off into `SosScreen`
        // can never be orphaned by the route push in between. Purely
        // decorative — see SosRevealHost's own doc comment.
        builder: (context, child) => SosRevealHost(child: child!),
        // Centralised in `theme/sentri_theme.dart` — see its own doc
        // comment for why `colorScheme.primary` is Cosmos Blue, not the
        // emergency red.
        theme: SentriTheme.light(),
        home: const LoginScreen(),
      ),
    );
  }
}
