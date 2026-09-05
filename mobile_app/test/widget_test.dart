import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/controllers/sos_controller.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/screens/app_shell.dart';
import 'package:mobile_app/services/emergency_contacts_store.dart';
import 'package:mobile_app/services/incident_status_store.dart';

void main() {
  testWidgets('SentriApp launches on the login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SentriApp());

    expect(find.text('SENTRI Login'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('AppShell renders Home first with the floating nav bar and SOS '
      'button, and can switch to Profile', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => IncidentStatusStore()),
          ChangeNotifierProvider(create: (_) => EmergencyContactsStore()),
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
        child: const MaterialApp(home: AppShell()),
      ),
    );
    // Not pumpAndSettle: the SOS button runs a perpetual idle "breath"
    // animation, so the tree never fully settles.
    await tester.pump();

    // Home's real content (Decision 28's deferred scope), not the old
    // placeholder screen: the two-line greeting (no user record when not
    // logged in, so the name line falls back to "there" — deterministic,
    // unlike the time-of-day line above it) and the idle safety-status
    // card, which reads real `IncidentStatusStore` state rather than a
    // static string. Both render synchronously, unlike the location
    // card's async GPS fetch.
    expect(find.text('there'), findsOneWidget);
    expect(find.text('No nearby incidents'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Idle SOS label on the nested button.
    expect(find.text('SOS'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pump();

    // Profile tab content: the identity block (no user record when not
    // logged in, so the fallback label and an unknown-status badge), the
    // Emergency Contacts row with its empty-state subtitle, the two new
    // preview rows, and Sign Out.
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('Status unknown'), findsOneWidget);
    expect(find.text('Emergency Contacts'), findsOneWidget);
    expect(find.text('No contacts added yet'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Privacy & Security'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
