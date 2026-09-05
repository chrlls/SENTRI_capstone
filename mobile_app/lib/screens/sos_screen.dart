import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/sos_controller.dart';
import '../providers/auth_provider.dart';
import '../services/incident_status_store.dart';
import '../theme/sentri_colors.dart';
import '../widgets/hold_to_confirm_sos_button.dart';
import 'voice_sos_screen.dart';

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
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _LocationStatus { checking, ready, notYetRequested, blocked }

enum _LocationBlockReason { serviceDisabled, permissionDenied }

class _SosScreenState extends State<SosScreen> with WidgetsBindingObserver {
  _LocationStatus _locationStatus = _LocationStatus.checking;
  _LocationBlockReason? _blockReason;
  Position? _lastKnownPosition;

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
        sos.phase != SosButtonPhase.sent;

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
      // No bottom navigation here: the app shell owns navigation now, and
      // the SOS screen is a pushed destination reached by tapping the
      // shell's SOS button — not a tab. (The former no-op `_HomeBottomNav`
      // placeholder was removed with this change.)
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
                        phase: sos.phase,
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
                LucideIcons.shield,
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
        dot = SentriColors.textMuted;
        word = 'Waiting';
      case StepStatus.working:
        dot = SentriColors.caution;
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
                color: step == StepStatus.idle
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
                iconColor: SentriColors.textPrimary,
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
