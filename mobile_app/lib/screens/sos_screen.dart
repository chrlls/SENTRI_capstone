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
/// not import, depend on, or be gated by anything related to a future
/// voice/AI trigger path — manual SOS itself stays self-contained
/// (Decision 05's "manual SOS never gated" at the widget level). The
/// voice-assisted flow this screen chains into afterward (Phase 3 of the
/// SOS button polish task) is a deliberately separate, second incident —
/// see voice_sos_screen.dart's own docs for why that boundary matters.
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
      await _submitManualSosAndProceed(position.latitude, position.longitude);
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
      await _submitManualSosAndProceed(position.latitude, position.longitude);
    } catch (e) {
      _handleSubmitFailure(e);
    }
  }

  Future<void> _submitManualSosAndProceed(double latitude, double longitude) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      throw ApiException(401, 'You are not logged in. Please log in again.');
    }

    await auth.apiClient.manualSos(token: token, latitude: latitude, longitude: longitude);

    if (!mounted) {
      return;
    }
    setState(() => _phase = SosButtonPhase.sent);

    // Lets the "sent" dot-burst actually play before immediately chaining
    // into the voice flow (Phase 3's "no intermediate menu" requirement,
    // balanced against not cutting the send-confirmation moment off mid-
    // animation).
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceSosScreen(token: token, latitude: latitude, longitude: longitude),
      ),
    );

    // The manual SOS above already succeeded regardless of what happens
    // in the voice screen (Phase 3, architectural fact #2) — returning
    // here just resets this screen for a possible future SOS, it does
    // not mean anything about the voice step's outcome.
    if (!mounted) {
      return;
    }
    setState(() => _phase = SosButtonPhase.idle);
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: SentriColors.caution, fontSize: 15),
                  ),
                ),
              if (_locationStatus == _LocationStatus.blocked)
                _LocationBlockedPanel(
                  reason: _blockReason!,
                  hasLastKnownPosition: _lastKnownPosition != null,
                  onOpenSettings: () {
                    if (_blockReason == _LocationBlockReason.serviceDisabled) {
                      Geolocator.openLocationSettings();
                    } else {
                      Geolocator.openAppSettings();
                    }
                  },
                  onSendWithoutLocation: _handleSendWithoutLocation,
                )
              else ...[
                HoldToConfirmSosButton(phase: _phase, onHoldComplete: _handleHoldComplete),
                const SizedBox(height: 20),
                if (_locationStatus == _LocationStatus.ready)
                  const Text(
                    'Location ready',
                    style: TextStyle(color: SentriColors.textMuted, fontSize: 13),
                  ),
              ],
            ],
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

    final settingsLabel =
        reason == _LocationBlockReason.serviceDisabled ? 'Open Location Settings' : 'Open App Settings';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.location_off_outlined, color: SentriColors.textMuted, size: 40),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: SentriColors.textPrimary, fontSize: 15, height: 1.4),
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
            hasLastKnownPosition
                ? 'Send SOS with last known location'
                : 'Send SOS without location (unavailable — no location on file yet)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasLastKnownPosition ? SentriColors.textMuted : SentriColors.textMuted.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
