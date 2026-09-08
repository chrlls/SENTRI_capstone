import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/controllers/sos_controller.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/screens/alert_history_screen.dart';
import 'package:mobile_app/screens/emergency_contacts_screen.dart';
import 'package:mobile_app/screens/home_screen.dart';
import 'package:mobile_app/screens/login_screen.dart';
import 'package:mobile_app/screens/notifications_screen.dart';
import 'package:mobile_app/screens/privacy_security_screen.dart';
import 'package:mobile_app/screens/profile_screen.dart';
import 'package:mobile_app/screens/register_screen.dart';
import 'package:mobile_app/screens/voice_sos_screen.dart';
import 'package:mobile_app/services/emergency_contacts_store.dart';
import 'package:mobile_app/services/incident_status_store.dart';
import 'package:mobile_app/services/notification_preferences_store.dart';
import 'package:mobile_app/services/privacy_preferences_store.dart';
import 'package:mobile_app/theme/sentri_theme.dart';

/// Screens migrated onto the new design tokens/theme, wrapped with every
/// provider any of them might read. A bare `Scaffold`/screen tree, not the
/// full `SentriApp` — these tests are about layout surviving the new,
/// larger type scale and card padding at real device sizes, not about
/// app-level routing.
Widget _appWith(Widget screen) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => IncidentStatusStore()),
      ChangeNotifierProvider(create: (_) => EmergencyContactsStore()),
      ChangeNotifierProvider(create: (_) => NotificationPreferencesStore()),
      ChangeNotifierProvider(create: (_) => PrivacyPreferencesStore()),
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
    child: MaterialApp(theme: SentriTheme.light(), home: screen),
  );
}

/// Every screen touched by the design-system migration, named for the
/// failure message. `voice_sos_screen.dart` needs constructor args rather
/// than reading a provider.
final _screens = <String, Widget Function()>{
  'LoginScreen': () => const LoginScreen(),
  'RegisterScreen': () => const RegisterScreen(),
  'HomeScreen': () => const HomeScreen(),
  'ProfileScreen': () => const ProfileScreen(),
  'EmergencyContactsScreen': () => const EmergencyContactsScreen(),
  'NotificationsScreen': () => const NotificationsScreen(),
  'PrivacySecurityScreen': () => const PrivacySecurityScreen(),
  'AlertHistoryScreen': () => const AlertHistoryScreen(),
  'VoiceSosScreen': () => const VoiceSosScreen(
        token: 't',
        latitude: 7.4478,
        longitude: 125.8078,
      ),
};

/// Realistic device sizes to pump each screen at — a small older phone and
/// a typical modern one. The new type scale / card padding introduced by
/// this migration is exactly what could overflow on the smaller one if a
/// screen wasn't actually checked at that width (this is what caught a
/// real overflow bug during the earlier SOS-button redesign).
const _sizes = {
  'small phone (320x568)': Size(320, 568),
  'typical phone (390x844)': Size(390, 844),
};

void main() {
  for (final screenEntry in _screens.entries) {
    for (final sizeEntry in _sizes.entries) {
      testWidgets(
        '${screenEntry.key} has no layout overflow on ${sizeEntry.key}',
        (tester) async {
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_appWith(screenEntry.value()));
          // Not pumpAndSettle: `HomeScreen`/`AlertHistoryScreen` kick off
          // real platform-channel calls (Geolocator, HTTP) that never
          // resolve in a widget test — one frame is enough to lay out the
          // screen in its initial (loading) state, which is what a real
          // device also renders first.
          await tester.pump();
        },
      );
    }

    testWidgets(
      '${screenEntry.key} has no layout overflow at 1.3x text scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(_appWith(screenEntry.value()));
        await tester.pump();
      },
    );
  }
}
