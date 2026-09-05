import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mobile_app/controllers/sos_controller.dart';
import 'package:mobile_app/services/incident_status_store.dart';
import 'package:mobile_app/services/sentri_api_client.dart';
import 'package:mobile_app/widgets/hold_to_confirm_sos_button.dart'
    show SosButtonPhase;

/// Exercises the SOS post-send lifecycle fix: idle -> sending -> sent ->
/// resolvedAcknowledgement -> idle. Uses `submitWithKnownPosition` rather
/// than `fireManualSos` throughout so these are plain Dart unit tests with
/// no `Geolocator` platform channel involved — only the HTTP boundary
/// (faked via `http`'s `MockClient`) and the two real `ChangeNotifier`s
/// under test.
void main() {
  group('SosController + IncidentStatusStore terminal lifecycle', () {
    test(
      'a full lifecycle (dashboard_alerted -> dispatcher_reviewing -> '
      'dispatched -> resolved) auto-returns to idle and allows a second, '
      'distinct incident',
      () async {
        var incidentCounter = 0;
        final sequenceByIncident = <String, List<String>>{};
        final pollIndexByIncident = <String, int>{};

        final client = MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.pathSegments.last == 'manual-sos') {
            incidentCounter += 1;
            final id = 'incident-$incidentCounter';
            // First incident walks the full lifecycle to resolved; a
            // second incident (created after the first completes) only
            // needs to prove it's tracked independently.
            sequenceByIncident[id] = incidentCounter == 1
                ? ['dashboard_alerted', 'dispatcher_reviewing', 'dispatched', 'resolved']
                : ['dashboard_alerted'];
            pollIndexByIncident[id] = 0;
            return http.Response(jsonEncode({'incident_id': id}), 201);
          }
          if (request.method == 'GET') {
            final id = request.url.pathSegments.last;
            final sequence = sequenceByIncident[id]!;
            final idx = pollIndexByIncident[id]!;
            final status = sequence[idx < sequence.length ? idx : sequence.length - 1];
            if (idx < sequence.length - 1) {
              pollIndexByIncident[id] = idx + 1;
            }
            return http.Response(jsonEncode({'status': status}), 200);
          }
          return http.Response('not found', 404);
        });

        final apiClient = SentriApiClient(client: client);
        final store = IncidentStatusStore(apiClient: apiClient);
        final controller = SosController(apiClient, store);
        addTearDown(controller.dispose);
        addTearDown(store.dispose);

        expect(controller.phase, SosButtonPhase.idle);

        // ── send ──
        await controller.submitWithKnownPosition(
          token: 't',
          latitude: 7.4478,
          longitude: 125.8078,
        );
        expect(controller.phase, SosButtonPhase.sent);
        expect(controller.sosSentAt, isNotNull);
        expect(store.incidentId, 'incident-1');

        // startTracking's immediate poll (dashboard_alerted) settling.
        await Future<void>.delayed(Duration.zero);
        expect(store.status, IncidentLifecycle.dashboardAlerted);
        expect(controller.phase, SosButtonPhase.sent, reason: 'sent state remains usable/displayed while non-terminal');

        // A new SOS must be rejected outright while the previous incident
        // is still non-terminal — no new incident, no phase change.
        await controller.submitWithKnownPosition(token: 't', latitude: 0, longitude: 0);
        expect(controller.phase, SosButtonPhase.sent);
        expect(store.incidentId, 'incident-1', reason: 'a second send while non-terminal must not create a new incident');
        expect(incidentCounter, 1);

        // dispatcher_reviewing
        await store.debugPollOnceForTest();
        expect(store.status, IncidentLifecycle.dispatcherReviewing);
        expect(store.dispatcherIsReviewing, isTrue);
        expect(controller.phase, SosButtonPhase.sent);

        // dispatched
        await store.debugPollOnceForTest();
        expect(store.status, IncidentLifecycle.dispatched);
        expect(store.dispatcherIsReviewing, isTrue);
        expect(controller.phase, SosButtonPhase.sent);

        // resolved — terminal, must flip the SOS phase.
        await store.debugPollOnceForTest();
        expect(store.status, IncidentLifecycle.resolved);
        expect(controller.phase, SosButtonPhase.resolvedAcknowledgement);
        expect(controller.terminalStatus, IncidentLifecycle.resolved);
        // Not yet cleared — only after the acknowledgement completes.
        expect(controller.sosSentAt, isNotNull);
        expect(store.incidentId, 'incident-1');

        // Auto-return to idle after the acknowledgement window, with no
        // "Done" tap.
        await Future<void>.delayed(SosController.terminalAcknowledgementDuration);
        await Future<void>.delayed(Duration.zero);
        expect(controller.phase, SosButtonPhase.idle);
        expect(controller.terminalStatus, isNull);
        expect(controller.sosSentAt, isNull);
        expect(store.incidentId, isNull, reason: 'tracked incident cleared once acknowledgement completes');

        // ── SOS button becomes usable again: a second, distinct incident ──
        await controller.submitWithKnownPosition(
          token: 't',
          latitude: 7.45,
          longitude: 125.81,
        );
        expect(controller.phase, SosButtonPhase.sent);
        expect(
          store.incidentId,
          'incident-2',
          reason: 'a new SOS must create a new incident, never reuse the resolved one',
        );

        // Let incident-2's own immediate poll settle before teardown disposes
        // the store/controller — otherwise that still-pending Future resolves
        // after disposal and trips ChangeNotifier's "used after dispose" assert.
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'false_alarm and cancelled are distinguished, never shown as resolved',
      () async {
        for (final entry in {
          'false_alarm': IncidentLifecycle.falseAlarm,
          'cancelled': IncidentLifecycle.cancelled,
        }.entries) {
          final client = MockClient((request) async {
            if (request.method == 'POST') {
              return http.Response(jsonEncode({'incident_id': 'incident-x'}), 201);
            }
            return http.Response(jsonEncode({'status': entry.key}), 200);
          });
          final apiClient = SentriApiClient(client: client);
          final store = IncidentStatusStore(apiClient: apiClient);
          final controller = SosController(apiClient, store);
          addTearDown(controller.dispose);
          addTearDown(store.dispose);

          await controller.submitWithKnownPosition(token: 't', latitude: 1, longitude: 1);
          await Future<void>.delayed(Duration.zero);

          expect(controller.phase, SosButtonPhase.resolvedAcknowledgement);
          expect(
            controller.terminalStatus,
            entry.value,
            reason: '${entry.key} must render its own outcome, not a generic "resolved"',
          );
        }
      },
    );

    test(
      'a stale late response for a superseded incident cannot affect the newly-tracked one',
      () async {
        final incidentACompleter = Completer<http.Response>();
        var sawIncidentARequest = false;

        final client = MockClient((request) async {
          if (request.url.pathSegments.last == 'incident-A') {
            sawIncidentARequest = true;
            return incidentACompleter.future;
          }
          if (request.url.pathSegments.last == 'incident-B') {
            return http.Response(jsonEncode({'status': 'dispatched'}), 200);
          }
          return http.Response('not found', 404);
        });

        final store = IncidentStatusStore(apiClient: SentriApiClient(client: client));
        addTearDown(store.dispose);

        store.startTracking(incidentId: 'incident-A', token: 't');
        await Future<void>.delayed(Duration.zero);
        expect(sawIncidentARequest, isTrue);

        // Retarget before A's response arrives — a second SOS superseding
        // the first while its poll was still in flight.
        store.startTracking(incidentId: 'incident-B', token: 't');
        await Future<void>.delayed(Duration.zero);
        expect(store.incidentId, 'incident-B');
        expect(store.status, IncidentLifecycle.dispatched);

        // A's stale response now finally arrives.
        incidentACompleter.complete(http.Response(jsonEncode({'status': 'resolved'}), 200));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(store.incidentId, 'incident-B', reason: 'must not be reset by the stale incident-A response');
        expect(store.status, IncidentLifecycle.dispatched, reason: 'must not be overwritten by incident-A\'s stale "resolved"');
      },
    );

    test('a failing status poll never crashes and leaves prior state in place', () async {
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'incident_id': 'incident-err'}), 201);
        }
        return http.Response(jsonEncode({'message': 'Server error'}), 500);
      });
      final apiClient = SentriApiClient(client: client);
      final store = IncidentStatusStore(apiClient: apiClient);
      final controller = SosController(apiClient, store);
      addTearDown(controller.dispose);
      addTearDown(store.dispose);

      await controller.submitWithKnownPosition(token: 't', latitude: 1, longitude: 1);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No crash getting here is itself the assertion; these just confirm
      // the failure was absorbed rather than silently corrupting state.
      expect(controller.phase, SosButtonPhase.sent);
      expect(store.lastError, isNotNull);
      expect(store.status, IncidentLifecycle.unknown);
    });
  });
}
