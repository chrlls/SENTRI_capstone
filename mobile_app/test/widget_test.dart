import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/controllers/sos_controller.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/screens/app_shell.dart';
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

    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Idle SOS label on the nested button.
    expect(find.text('SOS'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(find.text('You are signed in'), findsOneWidget);
  });
}
