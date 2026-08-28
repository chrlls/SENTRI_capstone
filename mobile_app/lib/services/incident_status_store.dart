import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sentri_api_client.dart';

/// Backend-authoritative incident lifecycle status. Strings map to
/// `incidents.status` in API_CONTRACTS.md. Pass 2 only needs to tell
/// "no human dispatcher has touched this yet" apart from "a human
/// dispatcher moved it into review" (Decision 31 §4).
enum IncidentLifecycle {
  /// Freshly created; the create response always reports this.
  detected,

  /// System auto-transition right after the dashboard notification row is
  /// written (`changed_by NULL`). **Not** a human action — still "waiting".
  dashboardAlerted,

  /// A human dispatcher moved it here via `PATCH /incidents/{id}/status`
  /// (decision 27). This is the earliest state that may render
  /// dispatcher-facing copy (Decision 31 §4).
  dispatcherReviewing,

  /// A human dispatcher pressed Dispatch. Pass 3 renders this presentation.
  dispatched,

  resolved,
  falseAlarm,
  cancelled,

  /// An API `status` string this client doesn't recognise, or none yet.
  unknown,
}

IncidentLifecycle _parseLifecycle(String? raw) {
  switch (raw) {
    case 'detected':
      return IncidentLifecycle.detected;
    case 'dashboard_alerted':
      return IncidentLifecycle.dashboardAlerted;
    case 'dispatcher_reviewing':
      return IncidentLifecycle.dispatcherReviewing;
    case 'dispatched':
      return IncidentLifecycle.dispatched;
    case 'resolved':
      return IncidentLifecycle.resolved;
    case 'false_alarm':
      return IncidentLifecycle.falseAlarm;
    case 'cancelled':
      return IncidentLifecycle.cancelled;
    default:
      return IncidentLifecycle.unknown;
  }
}

bool _isTerminal(IncidentLifecycle l) =>
    l == IncidentLifecycle.resolved ||
    l == IncidentLifecycle.falseAlarm ||
    l == IncidentLifecycle.cancelled;

/// Tracks one active incident by **polling** `GET /api/incidents/{id}` on
/// an interval.
///
/// This is a polling stopgap, **not** a push channel — Decision 31 Open
/// Item B: no mobile-facing Reverb broadcast exists yet, only the
/// dashboard side has one. The screen-facing contract here (the getters
/// on this `ChangeNotifier`) is transport-agnostic, so a push-based
/// implementation can later replace [_poll] without touching any consumer.
///
/// Per Decision 31 §1 this store lives **above** screen navigation
/// (provided at the app root) and is **never** gated on which screen is
/// showing. It keeps polling for the whole life of the active incident,
/// regardless of where the user navigates. Screen 4 is the only reader in
/// Pass 2; Pass 3's screens read the same getters.
class IncidentStatusStore extends ChangeNotifier {
  IncidentStatusStore({SentriApiClient? apiClient})
    : _apiClient = apiClient ?? SentriApiClient();

  final SentriApiClient _apiClient;

  /// 5s: fast enough that a dispatcher picking the incident up feels
  /// near-real-time to the waiting civilian, slow enough to stay gentle on
  /// the server (~12 requests/min per active incident). Not a real-time
  /// guarantee — see the class doc; a Reverb channel would replace this.
  static const Duration pollInterval = Duration(seconds: 5);

  Timer? _timer;
  String? _incidentId;
  String? _token;

  IncidentLifecycle _status = IncidentLifecycle.unknown;
  DateTime? _dispatcherReviewingAt;
  DateTime? _lastPolledAt;
  Object? _lastError;

  String? get incidentId => _incidentId;
  IncidentLifecycle get status => _status;
  bool get isTracking => _incidentId != null;
  bool get isPolling => _timer?.isActive ?? false;
  DateTime? get lastPolledAt => _lastPolledAt;
  Object? get lastError => _lastError;

  /// When the backend first reported a state at or past
  /// [IncidentLifecycle.dispatcherReviewing], i.e. when a real human
  /// dispatcher first touched the incident. `null` until then.
  DateTime? get dispatcherReviewingAt => _dispatcherReviewingAt;

  /// True only once the backend reports a real human dispatcher moved the
  /// incident into review (or beyond). Decision 31 §4 — never optimistic,
  /// never derived from an AI signal.
  bool get dispatcherIsReviewing =>
      _status == IncidentLifecycle.dispatcherReviewing ||
      _status == IncidentLifecycle.dispatched ||
      _status == IncidentLifecycle.resolved;

  /// Begin polling for [incidentId]. Called from `SosScreen` on a `201`
  /// from `POST /incidents/manual-sos`. Calling again with the same id
  /// while already polling is a no-op; a different id retargets.
  void startTracking({required String incidentId, required String token}) {
    if (_incidentId == incidentId && _timer != null) {
      return;
    }
    _timer?.cancel();
    _incidentId = incidentId;
    _token = token;
    _status = IncidentLifecycle.unknown;
    _dispatcherReviewingAt = null;
    _lastPolledAt = null;
    _lastError = null;
    _timer = Timer.periodic(pollInterval, (_) => _poll());
    _poll(); // don't wait a full interval for the first read
    notifyListeners();
  }

  /// Stop tracking entirely (e.g. on logout — no such path exists yet).
  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _incidentId = null;
    _token = null;
    _status = IncidentLifecycle.unknown;
    _dispatcherReviewingAt = null;
    notifyListeners();
  }

  Future<void> _poll() async {
    final id = _incidentId;
    final token = _token;
    if (id == null || token == null) {
      return;
    }
    try {
      final data = await _apiClient.getIncident(token: token, incidentId: id);
      _lastPolledAt = DateTime.now();
      final hadError = _lastError != null;
      _lastError = null;

      final next = _parseLifecycle(data['status'] as String?);
      final statusChanged = next != _status;
      _status = next;

      if (dispatcherIsReviewing && _dispatcherReviewingAt == null) {
        _dispatcherReviewingAt = DateTime.now();
      }

      if (_isTerminal(next)) {
        _timer?.cancel();
        _timer = null;
      }

      if (statusChanged || hadError) {
        notifyListeners();
      }
    } on ApiException catch (e) {
      // 401 (token expired) or 404 (incident gone, or no longer visible).
      // Keep the last known status on screen; surface the error for
      // debugging but don't churn the UI. Polling continues — a transient
      // 404 during replication, or a token refreshed elsewhere, can
      // recover on a later tick.
      _lastPolledAt = DateTime.now();
      final wasClean = _lastError == null;
      _lastError = e;
      if (wasClean) {
        notifyListeners();
      }
    } catch (e) {
      // Network/socket/timeout — transient. Retry next tick, keep the last
      // known status.
      final wasClean = _lastError == null;
      _lastError = e;
      if (wasClean) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
