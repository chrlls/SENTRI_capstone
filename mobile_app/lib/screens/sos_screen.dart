import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/sos_controller.dart';
import '../providers/auth_provider.dart';
import '../services/incident_status_store.dart';
import '../theme/sentri_colors.dart';
import '../widgets/hold_to_confirm_sos_button.dart';
import '../widgets/sos_reveal/sos_reveal_binding.dart';
import '../widgets/sos_reveal/sos_reveal_geometry.dart' show kSosDiscToCanvasRatio;
import 'voice_sos_screen.dart';

/// Target on-screen SOS-disc diameter, as a fraction of screen width
/// clamped to a sensible range — large and dominant (design direction:
/// ~200-220px on a typical phone) without hardcoding a pixel value that
/// would crowd a small screen or look undersized on a large one.
const double _kSosButtonMinDiameter = 170;
const double _kSosButtonMaxDiameter = 220;
const double _kSosButtonWidthFraction = 0.56;

/// The manual-SOS submission itself — GPS acquisition, the `manual-sos`
/// request, and the incident-status hand-off — lives in [SosController]
/// (app-root provider), shared with the app shell's nav-bar SOS button so
/// there is exactly one copy of that logic. The `--dart-define=FAIL_GPS` /
/// `FAIL_NETWORK` test injectors moved there with it and still cover both
/// entry points (see docs/decisions/31).
///
/// docs/decisions/28-flutter-manual-sos-mvp.md, point 5: this screen must
/// not depend on or be gated by anything related to a future voice/AI
/// trigger path — manual SOS itself stays self-contained (Decision 05's
/// "manual SOS never gated" at the widget level). The voice-assisted flow
/// is a deliberately separate, second incident and is now only reached
/// when the civilian taps "Add a voice message" *after* a successful send.
class SosScreen extends StatefulWidget {
  /// Name of the tab this screen was pushed from ("Home" or "Profile"),
  /// shown next to the back arrow in place of a static "SENTRI" wordmark
  /// — this screen is always a pushed destination, never a tab itself, so
  /// the header should read as a contextual back label, not a brand mark.
  final String backLabel;

  const SosScreen({super.key, required this.backLabel});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _LocationStatus { checking, ready, notYetRequested, blocked }

enum _LocationBlockReason { serviceDisabled, permissionDenied }

class _SosScreenState extends State<SosScreen> with WidgetsBindingObserver {
  _LocationStatus _locationStatus = _LocationStatus.checking;
  _LocationBlockReason? _blockReason;
  Position? _lastKnownPosition;

  /// Reverse-geocoded from [_lastKnownPosition], e.g. "Tagum City" —
  /// same best-effort `package:geocoding` pattern `home_screen.dart` uses
  /// (fire-and-forget, never surfaced as an error): the coordinates/
  /// accuracy already satisfy this row on their own, so a geocoding
  /// failure just leaves this `null` rather than blocking or faking a
  /// place name. Reset whenever the underlying position changes.
  String? _cityName;

  /// Local surface for the one screen-specific error that isn't a
  /// submission failure: opening the voice-message flow without the
  /// token/coords it needs. Shown in the same slot as
  /// [SosController.errorMessage].
  String? _voiceMessageError;

  /// Mirror of the button's live hold fraction (0..1), reported via
  /// `onHoldProgress`. Only used to show the "Release to cancel" hint and
  /// the shield panel below the button while a hold is in progress
  /// (screen 2). Never fed back into the button or the gate.
  double _screenHoldProgress = 0;

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

    // Only re-resolve the place name when the fix actually changed —
    // `_refreshLocationStatus` re-runs on every app resume, and re-geocoding
    // an unchanged position would just flash the city name blank and back.
    final previous = _lastKnownPosition;
    final positionChanged = lastKnown?.latitude != previous?.latitude ||
        lastKnown?.longitude != previous?.longitude;

    setState(() {
      _lastKnownPosition = lastKnown;
      if (positionChanged) {
        _cityName = null;
      }

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

    if (positionChanged && lastKnown != null) {
      // Fire-and-forget, same as the Home tab's location card: the
      // coordinates/accuracy already satisfy this row, so the city name
      // fills in when it arrives rather than delaying anything.
      unawaited(_reverseGeocode(lastKnown.latitude, lastKnown.longitude));
    }
  }

  /// Best-effort only — mirrors `home_screen.dart`'s `_reverseGeocode`
  /// exactly. A geocoding failure (offline, no result, plugin issue) must
  /// never surface as an error here: the coordinates this row already
  /// shows are correct and sufficient on their own.
  Future<void> _reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(latitude, longitude);
      if (!mounted || placemarks.isEmpty) return;
      final placemark = placemarks.first;
      final city = [
        placemark.locality,
        placemark.subAdministrativeArea,
        placemark.administrativeArea,
      ].firstWhere((candidate) => (candidate ?? '').trim().isNotEmpty, orElse: () => null);
      if (city == null) return;
      setState(() => _cityName = city);
    } catch (_) {
      // No connectivity, no geocoder on this device, no result — the row
      // already reads fine on coordinates/accuracy alone.
    }
  }

  Future<void> _handleHoldComplete() async {
    setState(() {
      _screenHoldProgress = 0;
      _voiceMessageError = null;
    });
    final sos = context.read<SosController>();
    await sos.fireManualSos(token: context.read<AuthProvider>().token);
    if (!mounted) {
      return;
    }
    // A GPS failure is the one outcome that changes what this screen shows
    // next (the location-status row / blocked panel), so re-read it — same
    // as before the submission logic moved into the controller.
    if (sos.gpsStep == StepStatus.failed) {
      await _refreshLocationStatus();
    }
  }

  Future<void> _handleSendWithoutLocation() async {
    final position = _lastKnownPosition;
    if (position == null) {
      return;
    }

    setState(() => _screenHoldProgress = 0);

    await context.read<SosController>().submitWithKnownPosition(
          token: context.read<AuthProvider>().token,
          latitude: position.latitude,
          longitude: position.longitude,
        );
  }

  void _openVoiceMessage() {
    final sos = context.read<SosController>();
    final token = context.read<AuthProvider>().token;
    final latitude = sos.lastSosLatitude;
    final longitude = sos.lastSosLongitude;
    if (token == null || latitude == null || longitude == null) {
      setState(
        () => _voiceMessageError = 'Please log in again to add a voice message.',
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

  @override
  Widget build(BuildContext context) {
    // Read from the app-root providers — Decision 31 §1: the incident
    // poller lives above navigation; the submission state now lives in the
    // shared [SosController]. This screen renders both, owns neither.
    final sos = context.watch<SosController>();
    final incidentStore = context.watch<IncidentStatusStore>();
    final displayedError = sos.errorMessage ?? _voiceMessageError;
    final holding =
        sos.phase == SosButtonPhase.idle && _screenHoldProgress > 0.001;
    final blockedPanelShowing = _locationStatus == _LocationStatus.blocked &&
        sos.phase != SosButtonPhase.sent &&
        sos.phase != SosButtonPhase.resolvedAcknowledgement;

    // The button itself (the red/white disc) is what should land at
    // ~200-220px — the surrounding box just needs to be big enough that
    // FittedBox scales the disc to that size, per `kSosDiscToCanvasRatio`.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sosDiscDiameter = (screenWidth * _kSosButtonWidthFraction).clamp(
      _kSosButtonMinDiameter,
      _kSosButtonMaxDiameter,
    );
    final sosButtonBoxSize = sosDiscDiameter / kSosDiscToCanvasRatio;

    return Scaffold(
      backgroundColor: SentriColors.background,
      appBar: AppBar(
        title: Text(widget.backLabel),
        centerTitle: false,
        backgroundColor: SentriColors.background,
        foregroundColor: SentriColors.textPrimary,
        elevation: 0,
      ),
      // No bottom navigation here: the app shell owns navigation now, and
      // the SOS screen is a pushed destination reached by tapping the
      // shell's SOS button — not a tab. (The former no-op `_HomeBottomNav`
      // placeholder was removed with this change.)
      body: SafeArea(
        child: SingleChildScrollView(
          // The button is now sized from screen width alone (see
          // `sosButtonBoxSize` above), so on a screen that's wide but
          // short (or with enlarged accessibility text) the column can
          // legitimately be taller than the viewport. Scrolling — rather
          // than a fixed height budget guessed per phase — is what keeps
          // this genuinely responsive instead of just "responsive on the
          // screen sizes it was checked on".
          padding: const EdgeInsets.all(24),
          // `width: double.infinity` forces the Column to fill the content
          // width so its default `crossAxisAlignment: center` actually
          // centres the button — without it the Column shrink-wraps to its
          // widest child (the button box) and pins left.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fixed top gap so the SOS button sits in the upper-middle
                // of the screen and never shifts between phases.
                const SizedBox(height: 40),
                if (displayedError != null)
                  Padding(
                    key: const ValueKey('sos-error'),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      displayedError,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: SentriColors.caution,
                        fontSize: 15,
                      ),
                    ),
                  ),
                if (sos.phase == SosButtonPhase.idle) ...[
                  const Text(
                    'Need help?',
                    style: TextStyle(
                      color: SentriColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Press and hold the button below to send an emergency alert.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SentriColors.textMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
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
                  // disc) via FittedBox — the box is sized so the disc
                  // itself lands at `sosDiscDiameter` (~200-220px on a
                  // typical phone, responsive on others), so nothing
                  // inside the widget (hold gesture, haptics) had to
                  // change. Keyed so inserting the error message above it
                  // doesn't tear down the button's State (and its
                  // in-progress hold) mid-interaction.
                  SosRevealBinding(
                    key: const ValueKey('sos-hold-button'),
                    // No tap affordance to protect here (unlike the nav
                    // bar) — this button only ever holds.
                    startDelay: Duration.zero,
                    onHoldComplete: _handleHoldComplete,
                    builder: (context, anchorKey, hooks) => SizedBox(
                      key: anchorKey,
                      width: sosButtonBoxSize,
                      height: sosButtonBoxSize,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: HoldToConfirmSosButton(
                          phase: sos.phase,
                          idleLabel: 'SOS',
                          idleLabelStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 54,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                          onHoldStart: hooks.onHoldStart,
                          onHoldCancel: hooks.onHoldCancel,
                          onHoldComplete: hooks.onHoldComplete,
                          onHoldProgress: (p) {
                            hooks.onHoldProgress(p);
                            // Only rebuild when the "is holding" state
                            // flips — the button paints its own % readout;
                            // this screen just needs to show/hide the hint
                            // panel.
                            final wasHolding = _screenHoldProgress > 0.001;
                            final nowHolding = p > 0.001;
                            _screenHoldProgress = p;
                            if (wasHolding != nowHolding) setState(() {});
                          },
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // ── Per-phase content below the button ──
                if (sos.phase == SosButtonPhase.sending)
                  _SendStatusRow(
                    gps: sos.gpsStep,
                    network: sos.networkStep,
                    alert: sos.alertStep,
                  )
                else if (sos.phase == SosButtonPhase.sent &&
                    sos.sosSentAt != null) ...[
                  _ConfirmedStatusCard(
                    sentAt: sos.sosSentAt!,
                    dispatcherReviewing: incidentStore.dispatcherIsReviewing,
                    reviewingAt: incidentStore.dispatcherReviewingAt,
                  ),
                  const SizedBox(height: 20),
                  // Voice message is a pull, not a push — offered here,
                  // never navigated into automatically (Decision 31,
                  // audit 1.4/R1).
                  _VoiceMessageButton(onPressed: _openVoiceMessage),
                ] else if (sos.phase == SosButtonPhase.resolvedAcknowledgement)
                  _TerminalAcknowledgementCard(status: sos.terminalStatus)
                else if (blockedPanelShowing)
                  const SizedBox.shrink()
                else if (holding)
                  const _HoldingHintPanel()
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _HelpReassuranceRow(),
                      const SizedBox(height: 20),
                      _LocationReadyRow(
                        status: _locationStatus,
                        position: _lastKnownPosition,
                        cityName: _cityName,
                      ),
                    ],
                  ),
                // A `Spacer` doesn't work once the column can scroll (it
                // needs a bounded height to divide); a fixed gap gives the
                // same bottom breathing room the button already has above.
                const SizedBox(height: 40),
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
          LucideIcons.mapPinOff,
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

/// Screen 1: the location status line under the button when idle and not
/// holding. When [cityName] has resolved (same best-effort reverse-geocode
/// `home_screen.dart`'s location card uses), it leads in place of the
/// generic "Location ready" label; the accuracy line stays either way, and
/// a `null` city (still resolving, or geocoding failed) falls back to the
/// generic label rather than showing nothing or a fake place name.
class _LocationReadyRow extends StatelessWidget {
  final _LocationStatus status;
  final Position? position;
  final String? cityName;

  const _LocationReadyRow({required this.status, this.position, this.cityName});

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String label;
    String? sub;
    switch (status) {
      case _LocationStatus.ready:
        dot = SentriColors.success;
        label = cityName ?? 'Location ready';
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
            // `Flexible`, not a bare `Text` — on a narrow screen the
            // longer status strings (e.g. "Getting your location…") can
            // exceed the row's available width; this lets it ellipsize
            // instead of overflowing.
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SentriColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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

/// Screen 2: shown below the button while a hold is in progress. Only
/// "Release to cancel" — the reassurance line ("help will be sent...")
/// now lives once on the idle screen ([_HelpReassuranceRow]), read
/// moments earlier; repeating a near-identical sentence again here as
/// the hold starts would just be the same message twice in a few
/// seconds, not new information.
class _HoldingHintPanel extends StatelessWidget {
  const _HoldingHintPanel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Release to cancel',
      style: TextStyle(color: SentriColors.textMuted, fontSize: 13),
    );
  }
}

/// The idle screen's standing reassurance line, shown only while at rest
/// (not holding, not location-blocked). Deliberately the only place this
/// message renders (see [_HoldingHintPanel]) and plain text only — no
/// icon, so it doesn't compete with the shield glyph already used
/// elsewhere on this screen (`_LocationBlockedPanel`'s map-off icon,
/// `_ConfirmedStatusCard`'s status icons) for meaning.
class _HelpReassuranceRow extends StatelessWidget {
  const _HelpReassuranceRow();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Help will be sent to nearby responders and authorities.',
      textAlign: TextAlign.center,
      style: TextStyle(color: SentriColors.textMuted, fontSize: 13),
    );
  }
}

/// Screen 3: the GPS / Network / Alert sub-status row. Each column reflects
/// a real step (audit 1.1/1.2) — GPS acquisition, server reachability, and
/// the send request — never decoration.
class _SendStatusRow extends StatelessWidget {
  final StepStatus gps;
  final StepStatus network;
  final StepStatus alert;

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
        // Varden — a subtle contextual surface for the one card the app
        // shows while actively transmitting, distinguishing it from the
        // plain neutral cards used elsewhere on this screen.
        color: SentriColors.highlight,
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
  final StepStatus step;
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
      case StepStatus.idle:
        dot = SentriColors.textSecondary;
        word = 'Waiting';
      case StepStatus.working:
        // Cosmos Blue — this is a neutral "in progress" signal, not a
        // warning, so it takes the system/informational color rather than
        // caution amber.
        dot = SentriColors.info;
        word = working;
      case StepStatus.ok:
        dot = SentriColors.success;
        word = ok;
      case StepStatus.failed:
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
                // `textSecondary`, not `textMuted`: this card now sits on
                // the Varden highlight surface, where `textMuted` no
                // longer clears the minimum text contrast.
                color: step == StepStatus.idle
                    ? SentriColors.textSecondary
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
          // Same Varden surface as the Sending card — one continuous
          // "system is actively handling this" visual language across
          // both screens.
          color: SentriColors.highlight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusRow(
              icon: LucideIcons.circleCheck,
              iconColor: SentriColors.success,
              label: 'Alert sent',
              trailing: sentTime,
            ),
            const SizedBox(height: 12),
            _StatusRow(
              icon: LucideIcons.circleCheck,
              iconColor: SentriColors.success,
              label: 'Location shared',
              trailing: sentTime,
            ),
            const SizedBox(height: 12),
            if (dispatcherReviewing)
              _StatusRow(
                icon: LucideIcons.userCheck,
                // Cosmos Blue: a real human dispatcher action, confirmed
                // by the backend (Decision 31 §4) — the "trust/system"
                // color, not a plain neutral.
                iconColor: SentriColors.info,
                label: 'Dispatcher reviewing',
                trailing: reviewingAt != null
                    ? TimeOfDay.fromDateTime(reviewingAt!).format(context)
                    : null,
              )
            else
              const _StatusRow(
                icon: LucideIcons.clock,
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
            // `textSecondary`, not `textMuted` — this row only ever sits on
            // the Varden `_ConfirmedStatusCard` surface, where `textMuted`
            // no longer clears the minimum text contrast.
            style: const TextStyle(color: SentriColors.textSecondary, fontSize: 13),
          ),
      ],
    );
  }
}

/// Shown for [SosController.terminalAcknowledgementDuration] once the
/// tracked incident reaches a terminal backend status, replacing the
/// checklist card while [SosController] counts down to an automatic
/// reset back to idle — never a "Done" button, since the civilian may
/// not be looking at the screen at this exact moment. States the actual
/// terminal outcome explicitly: `false_alarm`/`cancelled` must never read
/// as "resolved", they're different real-world outcomes.
class _TerminalAcknowledgementCard extends StatelessWidget {
  final IncidentLifecycle? status;

  const _TerminalAcknowledgementCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color iconColor;
    final String label;
    switch (status) {
      case IncidentLifecycle.resolved:
        icon = LucideIcons.circleCheck;
        iconColor = SentriColors.success;
        label = 'Incident resolved';
      case IncidentLifecycle.falseAlarm:
        icon = LucideIcons.circleAlert;
        iconColor = SentriColors.textMuted;
        label = 'Alert closed — marked as a false alarm';
      case IncidentLifecycle.cancelled:
        icon = LucideIcons.circleAlert;
        iconColor = SentriColors.textMuted;
        label = 'Alert cancelled';
      // Unreachable in practice — this card only renders while
      // SosController.phase is resolvedAcknowledgement, which it only
      // enters after observing one of the three cases above — but the
      // enum also has non-terminal values, so the switch still needs a
      // default to be exhaustive.
      default:
        icon = LucideIcons.circleCheck;
        iconColor = SentriColors.textMuted;
        label = 'Alert closed';
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: SentriColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SentriColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
        icon: const Icon(LucideIcons.mic, size: 20),
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
