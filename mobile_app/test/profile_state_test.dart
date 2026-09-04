import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/services/emergency_contacts_store.dart';
import 'package:mobile_app/services/sentri_api_client.dart';

void main() {
  group('AuthProvider.login / logout', () {
    AuthProvider buildAuth() {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/auth/login');
        return http.Response(
          jsonEncode({
            'token': '1|testtoken',
            'user': {
              'user_id': 'u-1',
              'email': 'civilian@example.test',
              'full_name': 'Test Civilian',
              'role': 'civilian',
              'status': 'active',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      return AuthProvider(apiClient: SentriApiClient(client: mockClient));
    }

    test('login populates token and the user record from the response',
        () async {
      final auth = buildAuth();

      final ok = await auth.login(
        email: 'civilian@example.test',
        password: 'CorrectHorse123',
      );

      expect(ok, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.token, '1|testtoken');
      expect(auth.user?.fullName, 'Test Civilian');
      expect(auth.user?.email, 'civilian@example.test');
    });

    test('logout clears token, user and status', () async {
      final auth = buildAuth();
      await auth.login(
        email: 'civilian@example.test',
        password: 'CorrectHorse123',
      );

      auth.logout();

      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.user, isNull);
    });
  });

  group('EmergencyContactsStore', () {
    test('add appends with a 1-based priority_order', () {
      final store = EmergencyContactsStore();

      store.add(contactName: 'Ana', contactPhone: '0917');
      store.add(
        contactName: 'Ben',
        contactPhone: '0918',
        relationship: 'Brother',
      );

      expect(store.contacts, hasLength(2));
      expect(store.contacts[0].priorityOrder, 1);
      expect(store.contacts[1].priorityOrder, 2);
      expect(store.contacts[1].relationship, 'Brother');
    });

    test('blank relationship is stored as null', () {
      final store = EmergencyContactsStore();
      store.add(contactName: 'Ana', contactPhone: '0917', relationship: '   ');
      expect(store.contacts.single.relationship, isNull);
    });

    test('removeAt drops the entry and renumbers the rest', () {
      final store = EmergencyContactsStore();
      store.add(contactName: 'Ana', contactPhone: '0917');
      store.add(contactName: 'Ben', contactPhone: '0918');
      store.add(contactName: 'Cy', contactPhone: '0919');

      store.removeAt(0);

      expect(store.contacts.map((c) => c.contactName), ['Ben', 'Cy']);
      expect(store.contacts.map((c) => c.priorityOrder), [1, 2]);
    });

    test('removeAt with an out-of-range index is a no-op', () {
      final store = EmergencyContactsStore();
      store.add(contactName: 'Ana', contactPhone: '0917');

      store.removeAt(5);

      expect(store.contacts, hasLength(1));
    });
  });
}
