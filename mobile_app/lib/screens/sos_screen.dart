import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
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

enum _LocationStatus { checking, ready, notYetRequested, blocked }

enum _LocationBlockReason { serviceDisabled, permissionDenied }

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

    return Geolocator.getCurrentPosition();
  }

  Future<void> _handleHoldComplete() async {
    setState(() {
      _phase = SosButtonPhase.sending;
      _errorMessage = null;
    });

    try {
      final position = await _acquireLocation();
      await _submitManualSos(position.latitude, position.longitude);
    } on LocationUnavailableException catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _phase = SosButtonPhase.idle);
      await _refreshLocationStatus();
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
    });

    try {
      await _submitManualSos(position.latitude, position.longitude);
    } catch (e) {
      _handleSubmitFailure(e);
    }
  }

  Future<void> _submitManualSos(double latitude, double longitude) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      throw ApiException(401, 'You are not logged in. Please log in again.');
    }

    await auth.apiClient.manualSos(
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
    });

    // Let the green checkmark / colour-crossfade success transition finish,
    // then re-arm the button. There is no navigation away from this screen:
    // the standing status line and the "Add a voice message" button below
    // are the lasting record that an SOS went out. Sourced from the
    // widget's own constant (+200ms) so this can't drift out of sync with
    // the animation it waits on.
    await Future.delayed(
      HoldToConfirmSosButton.sentAnimationDuration +
          const Duration(milliseconds: 200),
    );
    if (!mounted) {
      return;
    }
    setState(() => _phase = SosButtonPhase.idle);
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
      _errorMessage = error is ApiException
          ? error.message
          : 'Unable to reach the server. Check your connection and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SentriColors.background,
      appBar: AppBar(
        title: const Text('SENTRI'),
        backgroundColor: SentriColors.background,
        foregroundColor: SentriColors.textPrimary,
        elevation: 0,
      ),
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
                // of the screen (was vertically centred) and never shifts
                // between phases — the space below it is reserved for the
                // post-send status line and the voice-message button.
                const SizedBox(height: 40),
                if (_errorMessage != null)
                  Padding(
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
                if (_locationStatus == _LocationStatus.blocked)
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
                  // Scaled down from the button widget's natural 360px
                  // footprint (220px disc) to a 240px box — roughly a 147px
                  // disc — via FittedBox, so nothing inside the widget (hold
                  // gesture, haptics, particle field) had to change. Still
                  // about 3x the 48dp minimum touch target.
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: HoldToConfirmSosButton(
                        phase: _phase,
                        onHoldComplete: _handleHoldComplete,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_sosSentAt != null)
                  _SosSentStatusLine(sentAt: _sosSentAt!)
                else if (_locationStatus == _LocationStatus.ready)
                  const Text(
                    'Location ready',
                    style: TextStyle(
                      color: SentriColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                // Voice message is a pull, not a push: offered only after a
                // successful send, hidden again during a re-send, and it
                // stays available — it never navigates automatically.
                if (_sosSentAt != null && _phase != SosButtonPhase.sending) ...[
                  const SizedBox(height: 28),
                  _VoiceMessageButton(onPressed: _openVoiceMessage),
                ],
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

/// Persistent confirmation after a successful send — stays on screen, does
/// not fade. Replaces the sub-second "✓ SOS SENT" flash on the button.
class _SosSentStatusLine extends StatelessWidget {
  final DateTime sentAt;

  const _SosSentStatusLine({required this.sentAt});

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(sentAt).format(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: SentriColors.success, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'SOS sent — help is on the way',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: SentriColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sent at $time',
            style: const TextStyle(color: SentriColors.textMuted, fontSize: 13),
          ),
        ],
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
