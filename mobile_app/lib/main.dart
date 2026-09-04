import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/sos_controller.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'services/emergency_contacts_store.dart';
import 'services/incident_status_store.dart';
import 'services/notification_preferences_store.dart';
import 'services/privacy_preferences_store.dart';
import 'theme/sentri_colors.dart';

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
        // Explicit ColorScheme/component themes, not just `colorSchemeSeed`:
        // Material 3's seed-derived tonal palette picks a muted, darkened
        // tone for `primary` in light mode rather than the literal accent
        // hex (confirmed by rendering it — the seed alone produced a dull
        // brownish button, not #EB1B1D), and would also tint the AppBar's
        // surface a pale pink instead of the intended near-white. Pinning
        // these explicitly is what actually makes "red as the sole accent
        // color" true on screen, not just in the seed value.
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: SentriColors.background,
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: SentriColors.primaryRed,
                brightness: Brightness.light,
              ).copyWith(
                primary: SentriColors.primaryRed,
                onPrimary: Colors.white,
                surface: SentriColors.background,
                onSurface: SentriColors.textPrimary,
                error: SentriColors.caution,
              ),
          appBarTheme: const AppBarTheme(
            backgroundColor: SentriColors.background,
            foregroundColor: SentriColors.textPrimary,
            elevation: 0,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: SentriColors.primaryRed,
              foregroundColor: Colors.white,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: SentriColors.primaryRed,
            ),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
