import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../services/incident_status_store.dart';
import '../services/location_service.dart';
import '../services/sentri_api_client.dart';
import '../widgets/hold_to_confirm_sos_button.dart' show SosButtonPhase;

/// Test-only failure injector, toggled with `--dart-define`, for the
/// network leg of a submission:
///   --dart-define=FAIL_NETWORK=true  → the manual-sos request never
///                                      reaches the server
/// Compiles to `false` in any build that doesn't define it. Exists to
/// exercise audit item 1.1 (a GPS failure and a network failure must
/// produce visibly different outcomes); see docs/decisions/31. The GPS-side
/// injector (`FAIL_GPS`) now lives in `location_service.dart`, shared with
/// the Home tab's ambient location card.
const bool _simulateNetworkFailure = bool.fromEnvironment('FAIL_NETWORK');

/// Thrown only by the injector above, to reach the same catch/branch a
/// genuine transport fault would. Never thrown in normal use.
class _SimulatedFailure implements Exception {
  final String kind;
  const _SimulatedFailure(this.kind);
}

/// One sub-step of the sending sequence (the SOS screen's GPS / Network /
/// Alert row). `idle` = not started this attempt; `working` = in progress;
/// `ok`/`failed` = settled. Kept separate per step so a GPS failure and a
/// network failure produce visibly different outcomes (audit item 1.1).
enum StepStatus { idle, working, ok, failed }

/// Owns the manual-SOS submission flow — GPS acquisition, the `manual-sos`
/// request, and handing the new `incident_id` to [IncidentStatusStore] —
/// so the full [SosScreen] and the app shell's nav-bar SOS button fire the
/// *same* logic instead of holding two copies of the submission call
/// (task Resolution D). Screen-specific pre-send UI (the location-blocked
/// panel, the GPS pill, the location-status lifecycle) stays in
/// `SosScreen`; this covers only the send itself.
///
/// Decision 05 / Decision 28 point 5: this path has zero dependency on the
/// AI pipeline or on network availability, and nothing here is awaited
/// before a hold gesture can begin — the gesture lives entirely in
/// [HoldToConfirmSosButton]; this is only invoked once that gesture has
/// already completed.
class SosController extends ChangeNotifier {
  SosController(this._apiClient, this._statusStore) {
    // IncidentStatusStore stays the sole source of truth for backend
    // incident status (per its own class doc) — this controller only
    // *reacts* to it to drive the SOS-interaction phase, it never keeps
    // an independent copy of incident status that could drift from it.
    _statusStore.addListener(_onIncidentStatusChanged);
  }

  final SentriApiClient _apiClient;
  final IncidentStatusStore _statusStore;

  /// How long the terminal-acknowledgement phase stays on screen before
  /// auto-returning to idle — long enough to read a one-line message,
  /// short enough not to leave the screen stuck for someone who has
  /// already put the phone down (Decision 31's whole rationale for
  /// keeping everything after "sent" low-friction).
  static const Duration terminalAcknowledgementDuration = Duration(
    seconds: 3,
  );

  SosButtonPhase _phase = SosButtonPhase.idle;
  String? _errorMessage;
  StepStatus _gpsStep = StepStatus.idle;
  StepStatus _networkStep = StepStatus.idle;
  StepStatus _alertStep = StepStatus.idle;
  DateTime? _sosSentAt;
  double? _lastSosLatitude;
  double? _lastSosLongitude;
  bool _inFlight = false;

  /// Which terminal status ended the tracked incident, captured the
  /// instant [_onIncidentStatusChanged] detects one — read by the screen
  /// to render the correct one of "Incident resolved" / "Alert closed" /
  /// "Alert cancelled" during [SosButtonPhase.resolvedAcknowledgement].
  /// `null` outside that phase.
  IncidentLifecycle? _terminalStatus;
  Timer? _terminalAckTimer;

  SosButtonPhase get phase => _phase;
  String? get errorMessage => _errorMessage;
  StepStatus get gpsStep => _gpsStep;
  StepStatus get networkStep => _networkStep;
  StepStatus get alertStep => _alertStep;
  IncidentLifecycle? get terminalStatus => _terminalStatus;

  /// Non-null once a manual SOS has succeeded this session. Drives the SOS
  /// screen's persistent "SOS sent" status card; nothing clears it
  /// (Decision 31 screen 4 — no navigation, no timer-based dismissal).
  DateTime? get sosSentAt => _sosSentAt;

  /// Coordinates the last successful SOS was sent with, reused if the
  /// civilian later opens the optional voice-message flow.
  double? get lastSosLatitude => _lastSosLatitude;
  double? get lastSosLongitude => _lastSosLongitude;

  /// Acquire a device fix, then submit. Both the SOS screen's hold gesture
  /// and the app shell's nav-bar hold gesture call exactly this.
  Future<void> fireManualSos({required String? token}) async {
    if (_inFlight || _phase != SosButtonPhase.idle) {
      return;
    }
    _inFlight = true;
    _phase = SosButtonPhase.sending;
    _errorMessage = null;
    _gpsStep = StepStatus.working;
    _networkStep = StepStatus.idle;
    _alertStep = StepStatus.idle;
    notifyListeners();

    final Position position;
    try {
      position = await acquireCurrentLocation();
    } on LocationUnavailableException catch (e) {
      // GPS failed — visibly distinct from a network/server failure. The
      // send never left the device; the phase returns to idle so the
      // civilian can retry.
      _gpsStep = StepStatus.failed;
      _phase = SosButtonPhase.idle;
      _errorMessage = e.message;
      _inFlight = false;
      notifyListeners();
      return;
    }
    _gpsStep = StepStatus.ok;
    _networkStep = StepStatus.working;
    _alertStep = StepStatus.working;
    notifyListeners();

    try {
      await _submit(
        token: token,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      _handleSubmitFailure(e);
    }
    _inFlight = false;
  }

  /// Submit against an already-known fix — the SOS screen's "send with
  /// last known location" path, used when live location is blocked.
  Future<void> submitWithKnownPosition({
    required String? token,
    required double latitude,
    required double longitude,
  }) async {
    if (_inFlight || _phase != SosButtonPhase.idle) {
      return;
    }
    _inFlight = true;
    _phase = SosButtonPhase.sending;
    _errorMessage = null;
    _gpsStep = StepStatus.ok; // using a stored last-known fix
    _networkStep = StepStatus.working;
    _alertStep = StepStatus.working;
    notifyListeners();

    try {
      await _submit(token: token, latitude: latitude, longitude: longitude);
    } catch (e) {
      _handleSubmitFailure(e);
    }
    _inFlight = false;
  }

  /// Clears a settled error so a dismissed shell banner stays dismissed.
  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Fires the `manual-sos` request. On `201`, records the send and hands
  /// the `incident_id` to [IncidentStatusStore] to start polling. Verbatim
  /// logic from the former `_SosScreenState._submitManualSos`, minus the
  /// widget `mounted` guards (a [ChangeNotifier] has no such lifecycle).
  Future<void> _submit({
    required String? token,
    required double latitude,
    required double longitude,
  }) async {
    if (token == null) {
      throw ApiException(401, 'You are not logged in. Please log in again.');
    }

    if (_simulateNetworkFailure) {
      // Reaches `_handleSubmitFailure` as a non-ApiException, exactly as a
      // real socket/DNS/timeout failure would — its server-unreachable
      // branch then runs.
      throw const _SimulatedFailure('network');
    }

    final result = await _apiClient.manualSos(
      token: token,
      latitude: latitude,
      longitude: longitude,
    );

    _phase = SosButtonPhase.sent;
    _sosSentAt = DateTime.now();
    _lastSosLatitude = latitude;
    _lastSosLongitude = longitude;
    _networkStep = StepStatus.ok;
    _alertStep = StepStatus.ok;

    final incidentId = result['incident_id'] as String?;
    if (incidentId != null) {
      _statusStore.startTracking(incidentId: incidentId, token: token);
    }
    notifyListeners();
  }

  /// Verbatim branching from the former `_SosScreenState._handleSubmitFailure`.
  void _handleSubmitFailure(Object error) {
    _phase = SosButtonPhase.idle;
    _alertStep = StepStatus.failed;
    if (error is ApiException) {
      // The request reached the server — it rejected it. Show the server's
      // own message (auth expired / validation / 500).
      _networkStep = StepStatus.ok;
      _errorMessage = error.message;
    } else {
      // Socket / timeout / DNS — the request never reached the server.
      _networkStep = StepStatus.failed;
      _errorMessage =
          'Couldn\'t reach the server. Check your connection and try again.';
    }
    notifyListeners();
  }

  /// [IncidentStatusStore] listener — the only place this controller reads
  /// backend incident status, and only to decide *when* to move the SOS
  /// phase, never to store a second copy of that status. Fires on every
  /// poll tick, so most calls are a no-op via the phase guard below.
  void _onIncidentStatusChanged() {
    if (_phase != SosButtonPhase.sent) {
      // Only the post-send confirmation phase is waiting on this. In
      // particular, once `resolvedAcknowledgement` has already started,
      // further store notifications (e.g. `stopTracking`'s own
      // `notifyListeners`) must not restart the countdown or re-fire it.
      return;
    }
    final status = _statusStore.status;
    if (!isTerminalIncidentStatus(status)) {
      return;
    }
    _terminalAckTimer?.cancel();
    _phase = SosButtonPhase.resolvedAcknowledgement;
    _terminalStatus = status;
    notifyListeners();
    _terminalAckTimer = Timer(
      terminalAcknowledgementDuration,
      _completeTerminalAcknowledgement,
    );
  }

  /// Ends the terminal-acknowledgement phase automatically — never a user
  /// "Done" tap (the civilian may already have put the phone down).
  /// Clears the tracked incident *here*, not the moment the terminal
  /// status was first observed, so the acknowledgement text has something
  /// to read from for its full on-screen duration.
  void _completeTerminalAcknowledgement() {
    _terminalAckTimer = null;
    _phase = SosButtonPhase.idle;
    _terminalStatus = null;
    _sosSentAt = null;
    _lastSosLatitude = null;
    _lastSosLongitude = null;
    _statusStore.stopTracking();
    notifyListeners();
  }

  @override
  void dispose() {
    _terminalAckTimer?.cancel();
    _statusStore.removeListener(_onIncidentStatusChanged);
    super.dispose();
  }
}
