import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/screens/profile_screen.dart';
import 'package:mobile_app/services/emergency_contacts_store.dart';
import 'package:mobile_app/services/notification_preferences_store.dart';
import 'package:mobile_app/services/privacy_preferences_store.dart';
import 'package:mobile_app/services/sentri_api_client.dart';

Future<AuthProvider> _authWithStatus(String status) async {
  final mockClient = MockClient((request) async {
    return http.Response(
      jsonEncode({
        'token': '1|testtoken',
        'user': {
          'user_id': 'u-1',
          'email': 'civ@example.test',
          'full_name': 'Test Civilian',
          'role': 'civilian',
          'status': status,
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final auth = AuthProvider(apiClient: SentriApiClient(client: mockClient));
  await auth.login(email: 'civ@example.test', password: 'x');
  return auth;
}

Widget _profileUnder(AuthProvider auth) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ChangeNotifierProvider(create: (_) => EmergencyContactsStore()),
  ],
  child: const MaterialApp(home: ProfileScreen()),
);

void main() {
  group('Profile status badge', () {
    testWidgets('active -> "Verified", never any other label', (tester) async {
      await tester.pumpWidget(_profileUnder(await _authWithStatus('active')));
      await tester.pump();

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Pending verification'), findsNothing);
      expect(find.text('Account suspended'), findsNothing);
      expect(find.text('Status unknown'), findsNothing);
    });

    testWidgets('pending_verification -> amber label, not "Verified"',
        (tester) async {
      await tester.pumpWidget(
        _profileUnder(await _authWithStatus('pending_verification')),
      );
      await tester.pump();

      expect(find.text('Pending verification'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('suspended -> literal label, not "Verified"', (tester) async {
      await tester.pumpWidget(
        _profileUnder(await _authWithStatus('suspended')),
      );
      await tester.pump();

      expect(find.text('Account suspended'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('unrecognised status -> "Status unknown", not "Verified"',
        (tester) async {
      await tester.pumpWidget(
        _profileUnder(await _authWithStatus('some_future_state')),
      );
      await tester.pump();

      expect(find.text('Status unknown'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });
  });

  group('NotificationPreferencesStore', () {
    test('defaults, then a setter flips state and notifies once', () {
      final store = NotificationPreferencesStore();
      expect(store.incidentStatusUpdates, isTrue);
      expect(store.emergencyContactAlerts, isTrue);
      expect(store.systemAnnouncements, isFalse);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.systemAnnouncements = true;
      expect(store.systemAnnouncements, isTrue);
      expect(notifications, 1);

      // Same value again is a no-op — no extra notification.
      store.systemAnnouncements = true;
      expect(notifications, 1);
    });
  });

  group('PrivacyPreferencesStore', () {
    test('defaults, then a setter flips state and notifies once', () {
      final store = PrivacyPreferencesStore();
      expect(store.sharePreciseLocationWithResponders, isTrue);
      expect(store.allowDiagnosticsReports, isFalse);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.sharePreciseLocationWithResponders = false;
      expect(store.sharePreciseLocationWithResponders, isFalse);
      expect(notifications, 1);

      store.sharePreciseLocationWithResponders = false;
      expect(notifications, 1);
    });
  });
}
