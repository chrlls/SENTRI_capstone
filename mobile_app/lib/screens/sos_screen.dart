import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/incident_status_store.dart';
import '../services/sentri_api_client.dart';
import '../theme/sentri_colors.dart';
import '../widgets/hold_to_confirm_sos_button.dart';
import 'voice_sos_screen.dart';

/// Thrown by [SosScreen._acquireLocation] — kept local to this screen
/// rather than in the shared API client, since it's a device-permission
/// concept, not an API error.
class LocationUnavailableException implements Exception {
  final String message;
  LocationUnavailableException(this.message);
}

/// Test-only failure injectors, toggled with `--dart-define`. Each drives
/// the matching real failure path without needing a broken device or an
/// unreachable server:
///   --dart-define=FAIL_GPS=true      → no location fix is obtainable
///   --dart-define=FAIL_NETWORK=true  → the manual-sos request never
///                                      reaches the server
/// Both compile to `false` in any build that doesn't define them. They
/// exist to exercise audit item 1.1 (a GPS failure and a network failure
/// must produce visibly different outcomes); see docs/decisions/31.
const bool _simulateGpsFailure = bool.fromEnvironment('FAIL_GPS');
const bool _simulateNetworkFailure = bool.fromEnvironment('FAIL_NETWORK');

/// Thrown only by the injectors above, to reach the same catch/branch a
/// genuine device or transport fault would. Never thrown in normal use.
class _SimulatedFailure implements Exception {
  final String kind;
  const _SimulatedFailure(this.kind);
}

enum _LocationStatus { checking, ready, notYetRequested, blocked }

enum _LocationBlockReason { serviceDisabled, permissionDenied }

/// One sub-step of the sending sequence (screen 3's GPS / Network / Alert
/// row). `idle` = not started this attempt; `working` = in progress;
/// `ok`/`failed` = settled. Kept separate per step so a GPS failure and a
/// network failure produce visibly different outcomes (audit item 1.1).
enum _StepStatus { idle, working, ok, failed }

/// docs/decisions/28-flutter-manual-sos-mvp.md, point 5: this screen must
/// not depend on or be gated by anything related to a future voice/AI
/// trigger path — manual SOS itself stays self-contained (Decision 05's
/// "manual SOS never gated" at the widget level). The voice-assisted flow
/// is a deliberately separate, second incident and is now only reached
/// when the civilian taps "Add a voice message" *after* a successful send
/// — the send itself never navigates anywhere or touches the voice/AI
/// path. See voice_sos_screen.dart's own docs for why that boundary
/// matters.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with WidgetsBindingObserver {
  SosButtonPhase _phase = SosButtonPhase.idle;
  String? _errorMessage;

  _LocationStatus _locationStatus = _LocationStatus.checking;
  _LocationBlockReason? _blockReason;
  Position? _lastKnownPosition;

  /// Non-null once a manual SOS has succeeded this session. Drives the
  /// persistent "SOS sent" status line and the "Add a voice message"
  /// button — both stay on screen from here on; nothing clears this.
  DateTime? _sosSentAt;

  /// Coordinates the last successful SOS was sent with, reused if the
  /// civilian later opens the optional voice-message flow (its own
  /// separate incident, sent against the same location).
  double? _lastSosLatitude;
  double? _lastSosLongitude;

  /// Mirror of the button's live hold fraction (0..1), reported via
  /// `onHoldProgress`. Only used to show the "Release to cancel" hint and
  /// the shield panel below the button while a hold is in progress
  /// (screen 2). Never fed back into the button or the gate.
  double _screenHoldProgress = 0;

  /// The three sending sub-steps (screen 3's GPS / Network / Alert row).
  _StepStatus _gpsStep = _StepStatus.idle;
  _StepStatus _networkStep = _StepStatus.idle;
  _StepStatus _alertStep = _StepStatus.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLocationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-checks after the app resumes — the only reliable way to notice a
  /// permission/service change made from the OS settings screen this
  /// screen's own "Open Settings" button launches, since neither
  /// `openLocationSettings()` nor `openAppSettings()` reports back when
  /// the user returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocationStatus();
    }
  }

  Future<void> _refreshLocationStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();

    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {
      lastKnown = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _lastKnownPosition = lastKnown;

      if (!serviceEnabled) {
        _locationStatus = _LocationStatus.blocked;
        _blockReason = _LocationBlockReason.serviceDisabled;
      } else if (permission == LocationPermission.deniedForever) {
        _locationStatus = _LocationStatus.blocked;
        _blockReason = _LocationBlockReason.permissionDenied;
      } else if (permission == LocationPermission.denied) {
        _locationStatus = _LocationStatus.notYetRequested;
        _blockReason = null;
      } else {
        _locationStatus = _LocationStatus.ready;
        _blockReason = null;
      }
    });
  }

  Future<Position> _acquireLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationUnavailableException(
        'Location services are turned off. Enable location and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationUnavailableException(
          'Location permission denied. SENTRI needs your location to send an SOS.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailableException(
        'Location permission is permanently denied. Enable it in system settings.',
      );
    }

    try {
      if (_simulateGpsFailure) {
        // Behaves like a device that can't produce a fix at all — the
        // real catch below then runs the fallback + throw path.
        throw const _SimulatedFailure('gps');
      }
      return await Geolocator.getCurrentPosition(
        // Bound the wait: without a limit `getCurrentPosition` blocks
        // until a fresh fix arrives, which can be never (weak signal,
        // indoors) — the civilian would sit on "SENDING SOS" forever with
        // no error. On timeout, fall back to the last known fix if there
        // is one rather than failing outright.
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      final lastKnown = _simulateGpsFailure
          ? null
          : await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      // A GPS fix timing out / failing is a location problem, not a server
      // one — classify it as such so the caller shows the right message
      // (audit 1.1: a GPS failure must not read as "couldn't reach the
      // server").
      throw LocationUnavailableException(
        'Couldn\'t get a location fix. Move to an open area and try again.',
      );
    }
  }

  Future<void> _handleHoldComplete() async {
    setState(() {
      _phase = SosButtonPhase.sending;
      _errorMessage = null;
      _screenHoldProgress = 0;
      _gpsStep = _StepStatus.working;
      _networkStep = _StepStatus.idle;
      _alertStep = _StepStatus.idle;
    });

    final Position position;
    try {
      position = await _acquireLocation();
    } on LocationUnavailableException catch (e) {
      if (!mounted) return;
      // GPS failed — visibly distinct from a network/server failure. The
      // send never left the device; the button returns to idle so the
      // civilian can retry.
      setState(() {
        _gpsStep = _StepStatus.failed;
        _phase = SosButtonPhase.idle;
        _errorMessage = e.message;
      });
      await _refreshLocationStatus();
      return;
    }
    if (!mounted) return;
    setState(() {
      _gpsStep = _StepStatus.ok;
      _networkStep = _StepStatus.working;
      _alertStep = _StepStatus.working;
    });

    try {
      await _submitManualSos(position.latitude, position.longitude);
    } catch (e) {
      _handleSubmitFailure(e);
    }
  }

  Future<void> _handleSendWithoutLocation() async {
    final position = _lastKnownPosition;
    if (position == null) {
      return;
    }

    setState(() {
      _phase = SosButtonPhase.sending;
      _errorMessage = null;
      _screenHoldProgress = 0;
      _gpsStep = _StepStatus.ok; // using a stored last-known fix
      _networkStep = _StepStatus.working;
      _alertStep = _StepStatus.working;
    });

    try {
      await _submitManualSos(position.latitude, position.longitude);
    } catch (e) {
      _handleSubmitFailure(e);
    }
  }

  /// Fires the `manual-sos` request. On `201`, records the send, hands the
  /// `incident_id` to [IncidentStatusStore] to start polling, and leaves
  /// the button in its persistent confirmed (green) state — Decision 31
  /// screen 4, no navigation, no timer-based dismissal.
  Future<void> _submitManualSos(double latitude, double longitude) async {
    final auth = context.read<AuthProvider>();
    final store = context.read<IncidentStatusStore>();
    final token = auth.token;
    if (token == null) {
      throw ApiException(401, 'You are not logged in. Please log in again.');
    }

    if (_simulateNetworkFailure) {
      // Reaches `_handleSubmitFailure` as a non-ApiException, exactly as a
      // real socket/DNS/timeout failure would — its server-unreachable
      // branch then runs.
      throw const _SimulatedFailure('network');
    }

    final result = await auth.apiClient.manualSos(
      token: token,
      latitude: latitude,
      longitude: longitude,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _phase = SosButtonPhase.sent;
      _sosSentAt = DateTime.now();
      _lastSosLatitude = latitude;
      _lastSosLongitude = longitude;
      _networkStep = _StepStatus.ok;
      _alertStep = _StepStatus.ok;
    });

    final incidentId = result['incident_id'] as String?;
    if (incidentId != null) {
      store.startTracking(incidentId: incidentId, token: token);
    }
  }

  void _openVoiceMessage() {
    final token = context.read<AuthProvider>().token;
    final latitude = _lastSosLatitude;
    final longitude = _lastSosLongitude;
    if (token == null || latitude == null || longitude == null) {
      setState(
        () => _errorMessage = 'Please log in again to add a voice message.',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceSosScreen(
          token: token,
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
  }

  void _handleSubmitFailure(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = SosButtonPhase.idle;
      _alertStep = _StepStatus.failed;
      if (error is ApiException) {
        // The request reached the server — it rejected it. Show the
        // server's own message (auth expired / validation / 500).
        _networkStep = _StepStatus.ok;
        _errorMessage = error.message;
      } else {
        // Socket / timeout / DNS — the request never reached the server.
        _networkStep = _StepStatus.failed;
        _errorMessage =
            'Couldn\'t reach the server. Check your connection and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read from the app-root store — Decision 31 §1: the incident poller
    // lives above navigation and is never gated on the current screen;
    // this screen just reads it.
    final incidentStore = context.watch<IncidentStatusStore>();
    final holding =
        _phase == SosButtonPhase.idle && _screenHoldProgress > 0.001;
    final blockedPanelShowing =
        _locationStatus == _LocationStatus.blocked &&
        _phase != SosButtonPhase.sent;

    return Scaffold(
      backgroundColor: SentriColors.background,
      appBar: AppBar(
        title: const Text('SENTRI'),
        backgroundColor: SentriColors.background,
        foregroundColor: SentriColors.textPrimary,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _GpsPill(status: _locationStatus)),
          ),
        ],
      ),
      bottomNavigationBar: const _HomeBottomNav(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          // `width: double.infinity` forces the Column to fill the content
          // width so its default `crossAxisAlignment: center` actually
          // centres the button — without it the Column shrink-wraps to its
          // widest child (the 240px button box) and pins left.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                // Fixed top gap so the SOS button sits in the upper-middle
                // of the screen and never shifts between phases.
                const SizedBox(height: 40),
                if (_errorMessage != null)
                  Padding(
                    key: const ValueKey('sos-error'),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: SentriColors.caution,
                        fontSize: 15,
                      ),
                    ),
                  ),
                if (blockedPanelShowing)
                  _LocationBlockedPanel(
                    reason: _blockReason!,
                    hasLastKnownPosition: _lastKnownPosition != null,
                    onOpenSettings: () {
                      if (_blockReason ==
                          _LocationBlockReason.serviceDisabled) {
                        Geolocator.openLocationSettings();
                      } else {
                        Geolocator.openAppSettings();
                      }
                    },
                    onSendWithoutLocation: _handleSendWithoutLocation,
                  )
                else
                  // Scaled from the widget's natural 360px footprint (220px
                  // disc) to a 240px box — ~147px disc — via FittedBox, so
                  // nothing inside the widget (hold gesture, haptics,
                  // particle field) had to change. Still ~3x the 48dp
                  // minimum touch target. Keyed so inserting the error
                  // message above it doesn't tear down the button's State
                  // (and its in-progress hold) mid-interaction.
                  SizedBox(
                    key: const ValueKey('sos-hold-button'),
                    width: 240,
                    height: 240,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: HoldToConfirmSosButton(
                        phase: _phase,
                        onHoldComplete: _handleHoldComplete,
                        onHoldProgress: (p) {
                          // Only rebuild when the "is holding" state flips —
                          // the button paints its own % readout; this
                          // screen just needs to show/hide the hint panel.
                          final wasHolding = _screenHoldProgress > 0.001;
                          final nowHolding = p > 0.001;
                          _screenHoldProgress = p;
                          if (wasHolding != nowHolding) setState(() {});
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // ── Per-phase content below the button ──
                if (_phase == SosButtonPhase.sending)
                  _SendStatusRow(
                    gps: _gpsStep,
                    network: _networkStep,
                    alert: _alertStep,
                  )
                else if (_phase == SosButtonPhase.sent &&
                    _sosSentAt != null) ...[
                  _ConfirmedStatusCard(
                    sentAt: _sosSentAt!,
                    dispatcherReviewing: incidentStore.dispatcherIsReviewing,
                    reviewingAt: incidentStore.dispatcherReviewingAt,
                  ),
                  const SizedBox(height: 20),
                  // Voice message is a pull, not a push — offered here,
                  // never navigated into automatically (Decision 31,
                  // audit 1.4/R1). The recording screen itself is Pass 3.
                  _VoiceMessageButton(onPressed: _openVoiceMessage),
                ] else if (blockedPanelShowing)
                  const SizedBox.shrink()
                else if (holding)
                  const _HoldingHintPanel()
                else
                  _LocationReadyRow(
                    status: _locationStatus,
                    position: _lastKnownPosition,
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationBlockedPanel extends StatelessWidget {
  final _LocationBlockReason reason;
  final bool hasLastKnownPosition;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSendWithoutLocation;

  const _LocationBlockedPanel({
    required this.reason,
    required this.hasLastKnownPosition,
    required this.onOpenSettings,
    required this.onSendWithoutLocation,
  });

  @override
  Widget build(BuildContext context) {
    final message = reason == _LocationBlockReason.serviceDisabled
        ? 'Location services are turned off. SENTRI needs this to tell responders where you are.'
        : 'SENTRI doesn\'t have permission to use your location. Enable it in settings so responders know where to go.';

    final settingsLabel = reason == _LocationBlockReason.serviceDisabled
        ? 'Open Location Settings'
        : 'Open App Settings';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.location_off_outlined,
          color: SentriColors.textMuted,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: SentriColors.textPrimary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onOpenSettings,
            style: FilledButton.styleFrom(
              backgroundColor: SentriColors.surfaceMuted,
              foregroundColor: SentriColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(settingsLabel),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: hasLastKnownPosition ? onSendWithoutLocation : null,
          child: Text(
            hasLastKnownPosition ? 'Send SOS with last known location' : 'Send SOS without location (unavailable — no location on file yet)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasLastKnownPosition
                  ? SentriColors.textMuted
                  : SentriColors.textMuted.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small filled circle — the status indicator used by the GPS pill, the
/// location row, and the sending sub-status row.
class _Dot extends StatelessWidget {
  final Color color;
  final double size;

  const _Dot(this.color, {this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Top-right of the shell: a dot + "GPS", green when a fix is ready, amber
/// while acquiring / not yet requested, red when location is blocked. This
/// is one of the places audit item 1.2 gets addressed — the three
/// not-ready states are no longer visually identical.
class _GpsPill extends StatelessWidget {
  final _LocationStatus status;

  const _GpsPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color dot;
    switch (status) {
      case _LocationStatus.ready:
        dot = SentriColors.success;
      case _LocationStatus.checking:
      case _LocationStatus.notYetRequested:
        dot = SentriColors.caution;
      case _LocationStatus.blocked:
        dot = SentriColors.primaryRed;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SentriColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(dot, size: 7),
          const SizedBox(width: 6),
          const Text(
            'GPS',
            style: TextStyle(
              color: SentriColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shell's bottom navigation. Home is the only built destination in
/// this pass; the other three tabs are present for shell consistency but
/// have nowhere to go yet (tapping them does nothing).
class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav();

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      type: BottomNavigationBarType.fixed,
      backgroundColor: SentriColors.background,
      selectedItemColor: SentriColors.primaryRed,
      unselectedItemColor: SentriColors.textMuted,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      onTap: (_) {},
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications_none),
          label: 'Alerts',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          label: 'Contacts',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    );
  }
}

/// Screen 1: the location status line under the button when idle and not
/// holding. Mock also shows a resolved place name ("Tagum City") — that
/// needs reverse geocoding (a geocoding package + network) which this MVP
/// doesn't have, so it's intentionally omitted rather than faked.
class _LocationReadyRow extends StatelessWidget {
  final _LocationStatus status;
  final Position? position;

  const _LocationReadyRow({required this.status, this.position});

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String label;
    String? sub;
    switch (status) {
      case _LocationStatus.ready:
        dot = SentriColors.success;
        label = 'Location ready';
        final acc = position?.accuracy;
        if (acc != null && acc > 0) sub = 'Accuracy: ±${acc.round()} m';
      case _LocationStatus.checking:
        dot = SentriColors.caution;
        label = 'Getting your location…';
      case _LocationStatus.notYetRequested:
        dot = SentriColors.caution;
        label = 'Location access needed';
        sub = 'You\'ll be asked when you send';
      case _LocationStatus.blocked:
        dot = SentriColors.primaryRed;
        label = 'Location unavailable';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(dot),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: SentriColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SentriColors.textMuted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Screen 2: shown below the button while a hold is in progress.
class _HoldingHintPanel extends StatelessWidget {
  const _HoldingHintPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Release to cancel',
          style: TextStyle(color: SentriColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: SentriColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: SentriColors.textMuted,
                size: 20,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "We'll notify responders and share your location.",
                  style: TextStyle(
                    color: SentriColors.textMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Screen 3: the GPS / Network / Alert sub-status row. Each column reflects
/// a real step (audit 1.1/1.2) — GPS acquisition, server reachability, and
/// the send request — never decoration.
class _SendStatusRow extends StatelessWidget {
  final _StepStatus gps;
  final _StepStatus network;
  final _StepStatus alert;

  const _SendStatusRow({
    required this.gps,
    required this.network,
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: SentriColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SendStatusColumn(
            label: 'GPS',
            step: gps,
            working: 'Acquiring',
            ok: 'Connected',
            failed: 'Off',
          ),
          _SendStatusColumn(
            label: 'Network',
            step: network,
            working: 'Connecting',
            ok: 'Connected',
            failed: 'No connection',
          ),
          _SendStatusColumn(
            label: 'Alert',
            step: alert,
            working: 'Sending',
            ok: 'Sent',
            failed: 'Failed',
          ),
        ],
      ),
    );
  }
}

class _SendStatusColumn extends StatelessWidget {
  final String label;
  final _StepStatus step;
  final String working;
  final String ok;
  final String failed;

  const _SendStatusColumn({
    required this.label,
    required this.step,
    required this.working,
    required this.ok,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String word;
    switch (step) {
      case _StepStatus.idle:
        dot = SentriColors.textMuted;
        word = 'Waiting';
      case _StepStatus.working:
        dot = SentriColors.caution;
        word = working;
      case _StepStatus.ok:
        dot = SentriColors.success;
        word = ok;
      case _StepStatus.failed:
        dot = SentriColors.primaryRed;
        word = failed;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SentriColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(dot, size: 7),
            const SizedBox(width: 6),
            Text(
              word,
              style: TextStyle(
                color: step == _StepStatus.idle
                    ? SentriColors.textMuted
                    : SentriColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Screen 4: the persistent itemised checklist below the confirmed button.
/// The third row is state-driven — it shows the neutral "Waiting for
/// dispatcher" until [IncidentStatusStore] confirms the backend reports a
/// real human dispatcher moved the incident into review (Decision 31 §4).
/// It is never optimistic and never derived from an AI signal.
class _ConfirmedStatusCard extends StatelessWidget {
  final DateTime sentAt;
  final bool dispatcherReviewing;
  final DateTime? reviewingAt;

  const _ConfirmedStatusCard({
    required this.sentAt,
    required this.dispatcherReviewing,
    this.reviewingAt,
  });

  @override
  Widget build(BuildContext context) {
    final sentTime = TimeOfDay.fromDateTime(sentAt).format(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SentriColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusRow(
              icon: Icons.check_circle,
              iconColor: SentriColors.success,
              label: 'Alert sent',
              trailing: sentTime,
            ),
            const SizedBox(height: 12),
            _StatusRow(
              icon: Icons.check_circle,
              iconColor: SentriColors.success,
              label: 'Location shared',
              trailing: sentTime,
            ),
            const SizedBox(height: 12),
            if (dispatcherReviewing)
              _StatusRow(
                icon: Icons.assignment_ind_outlined,
                iconColor: SentriColors.textPrimary,
                label: 'Dispatcher reviewing',
                trailing: reviewingAt != null
                    ? TimeOfDay.fromDateTime(reviewingAt!).format(context)
                    : null,
              )
            else
              const _StatusRow(
                icon: Icons.schedule,
                iconColor: SentriColors.textMuted,
                label: 'Waiting for dispatcher',
                trailing: 'Pending',
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? trailing;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: SentriColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(color: SentriColors.textMuted, fontSize: 13),
          ),
      ],
    );
  }
}

/// Optional secondary action, shown only after a successful send.
/// Deliberately not red and not circular — red + circular is this app's
/// SOS-send signifier; this must not be mistaken for it.
class _VoiceMessageButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _VoiceMessageButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.mic_none, size: 20),
        label: const Text('Add a voice message'),
        style: OutlinedButton.styleFrom(
          foregroundColor: SentriColors.textPrimary,
          side: const BorderSide(color: SentriColors.textMuted),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
