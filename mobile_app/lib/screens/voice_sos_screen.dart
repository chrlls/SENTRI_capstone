import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/sentri_api_client.dart';
import '../theme/sentri_colors.dart';
import '../theme/sentri_text.dart';
import '../theme/sentri_tokens.dart';

enum _VoiceStage { intro, micBlocked, recording, uploading, completed, inconclusive, error }

/// Reached immediately after a manual SOS successfully sends (Phase 3 of
/// the SOS button polish task). **Two real architectural facts this must
/// respect:**
///
/// 1. Manual SOS and voice-assisted SOS are two separate backend
///    incidents (two `POST` calls, two `incidents` rows) — this screen
///    does not merge them. `latitude`/`longitude` are passed in from the
///    manual-SOS fix that was just acquired, reused here rather than
///    prompting for location again, but `ai-assisted-sos` still creates
///    its own independent row server-side.
/// 2. The manual SOS already succeeded before this screen ever opens.
///    Skipping/cancelling here must never read as undoing that — there
///    is deliberately no "are you sure?" confirmation on exit.
///
/// Visually this is a supporting, evidence-capture flow, not a second SOS
/// trigger (design doc §12, Voice Message) — the record control uses the
/// app's non-emergency accent (Cosmos Blue), not Crimson Blaze, so it
/// never reads as another way to fire an emergency.
class VoiceSosScreen extends StatefulWidget {
  final String token;
  final double latitude;
  final double longitude;

  const VoiceSosScreen({
    super.key,
    required this.token,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<VoiceSosScreen> createState() => _VoiceSosScreenState();
}

class _VoiceSosScreenState extends State<VoiceSosScreen> {
  final _recorder = AudioRecorder();
  _VoiceStage _stage = _VoiceStage.intro;
  String? _errorMessage;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _stage = _VoiceStage.micBlocked);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/sentri_voice_sos_${DateTime.now().millisecondsSinceEpoch}.wav';

    // AudioEncoder.wav, not aacLc: verified during testing that a real
    // AAC/M4A recording from this package is a genuinely valid audio-only
    // MP4 file, but PHP's fileinfo (what ai-assisted-sos's `mimes:`
    // validation actually checks server-side, not the client's declared
    // Content-Type) detects audio-only MP4 containers as video/mp4 — a
    // real libmagic limitation, not fixable from the client side without
    // touching backend validation, which is out of scope here. WAV's
    // header is unambiguous and correctly detected as audio/wav.
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);

    _elapsed = Duration.zero;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });

    setState(() => _stage = _VoiceStage.recording);
  }

  Future<void> _stopAndUpload() async {
    _elapsedTimer?.cancel();
    final path = await _recorder.stop();

    if (path == null) {
      setState(() {
        _stage = _VoiceStage.error;
        _errorMessage = 'Recording could not be saved. You can try again, or skip — your SOS was already sent.';
      });
      return;
    }

    setState(() => _stage = _VoiceStage.uploading);

    try {
      final client = SentriApiClient();
      final response = await client.aiAssistedSos(
        token: widget.token,
        latitude: widget.latitude,
        longitude: widget.longitude,
        audioFilePath: path,
      );

      final status = (response['ai_classification'] as Map<String, dynamic>?)?['status'] as String?;

      if (!mounted) {
        return;
      }
      setState(() {
        // Per API_CONTRACTS.md / Decisions #5 & #13: "completed" and
        // "inconclusive" are both real successes for the user — the AI
        // outcome never blocks or delays the incident, so neither is
        // presented as an error here.
        _stage = status == 'completed' ? _VoiceStage.completed : _VoiceStage.inconclusive;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _VoiceStage.error;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _VoiceStage.error;
        _errorMessage = 'Unable to reach the server. Your SOS was already sent — you can retry the voice message or skip.';
      });
    }
  }

  void _exit() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Voice message'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SentriSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Sent regardless of anything on this screen — never framed
              // as conditional on what happens below (architectural fact
              // #2 above).
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.circleCheck, color: SentriColors.success, size: 20),
                  const SizedBox(width: SentriSpacing.sm),
                  Flexible(
                    child: Text(
                      'SOS sent. Help is on the way.',
                      style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SentriSpacing.xxxl),
              Expanded(child: Center(child: _buildStageContent(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent(BuildContext context) {
    switch (_stage) {
      case _VoiceStage.intro:
        return _IntroContent(onRecord: _startRecording, onSkip: _exit);
      case _VoiceStage.micBlocked:
        return _MicBlockedContent(
          onOpenSettings: Geolocator.openAppSettings,
          onSkip: _exit,
        );
      case _VoiceStage.recording:
        return _RecordingContent(elapsed: _elapsed, onStop: _stopAndUpload);
      case _VoiceStage.uploading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: SentriSpacing.lg),
            Text('Sending voice message…', style: SentriText.bodySmall.copyWith(color: SentriColors.textMuted)),
          ],
        );
      case _VoiceStage.completed:
      case _VoiceStage.inconclusive:
        return _ResultContent(
          // Both branches read as the same reassuring outcome to the
          // user — the distinction is internal telemetry, not a
          // user-facing success/failure split (Decisions #5/#13).
          message: 'Voice message received.',
          onDone: _exit,
        );
      case _VoiceStage.error:
        return _ErrorContent(
          message: _errorMessage ?? 'Something went wrong sending the voice message.',
          onRetry: _startRecording,
          onSkip: _exit,
        );
    }
  }
}

class _IntroContent extends StatelessWidget {
  final VoidCallback onRecord;
  final VoidCallback onSkip;

  const _IntroContent({required this.onRecord, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You can also record a short voice message for responders. This is optional.',
          textAlign: TextAlign.center,
          style: SentriText.bodySmall.copyWith(color: SentriColors.textMuted),
        ),
        const SizedBox(height: SentriSpacing.xxl),
        SizedBox(
          width: 96,
          height: 96,
          child: FilledButton(
            onPressed: onRecord,
            // Cosmos Blue, not the emergency red — this is a supporting
            // evidence-capture action, not another SOS trigger (design
            // doc §12).
            style: FilledButton.styleFrom(
              backgroundColor: SentriColors.info,
              shape: const CircleBorder(),
            ),
            child: const Icon(LucideIcons.mic, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: SentriSpacing.xl + SentriSpacing.xs),
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip', style: TextStyle(color: SentriColors.textMuted)),
        ),
      ],
    );
  }
}

class _MicBlockedContent extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onSkip;

  const _MicBlockedContent({required this.onOpenSettings, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.micOff, color: SentriColors.textMuted, size: 40),
        const SizedBox(height: SentriSpacing.lg),
        Text(
          'SENTRI needs microphone access to record a voice message. Your SOS was already sent either way.',
          textAlign: TextAlign.center,
          style: SentriText.bodySmall,
        ),
        const SizedBox(height: SentriSpacing.xl),
        // Themed `OutlinedButton` (white fill, ink-300 border) — the
        // app-wide secondary-button treatment, replacing a hand-styled
        // filled/surfaceMuted button.
        OutlinedButton(
          onPressed: onOpenSettings,
          child: const Text('Open Settings'),
        ),
        const SizedBox(height: SentriSpacing.md),
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip', style: TextStyle(color: SentriColors.textMuted)),
        ),
      ],
    );
  }
}

class _RecordingContent extends StatelessWidget {
  final Duration elapsed;
  final VoidCallback onStop;

  const _RecordingContent({required this.elapsed, required this.onStop});

  String get _label {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A plain dot rather than a Material icon substitute: this is the
        // low-key active-recording indicator SENTRI_DESIGN_SYSTEM_V1.1.md
        // §12 (Voice Message → Recording) describes literally — no icon
        // family, Lucide included, ships a plain filled-circle glyph.
        // Stays Crimson Blaze: a small solid recording dot is a universal
        // "recording" convention independent of SENTRI's own emergency
        // semantics, unlike the large record button above.
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: SentriColors.primaryRed,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: SentriSpacing.md),
        // w500, not the original w300 — SENTRI's typography direction
        // avoids excessively thin weights even for a numeric readout.
        Text(_label, style: SentriText.h1.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: SentriSpacing.xl + SentriSpacing.xs),
        SizedBox(
          width: 96,
          height: 96,
          child: FilledButton(
            onPressed: onStop,
            style: FilledButton.styleFrom(
              backgroundColor: SentriColors.surfaceMuted,
              foregroundColor: SentriColors.textPrimary,
              shape: const CircleBorder(),
            ),
            child: const Icon(LucideIcons.square, size: 32),
          ),
        ),
      ],
    );
  }
}

class _ResultContent extends StatelessWidget {
  final String message;
  final VoidCallback onDone;

  const _ResultContent({required this.message, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.circleCheck, color: SentriColors.success, size: 56),
        const SizedBox(height: SentriSpacing.lg),
        Text(message, style: SentriText.body),
        const SizedBox(height: SentriSpacing.xl + SentriSpacing.xs),
        OutlinedButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const _ErrorContent({required this.message, required this.onRetry, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: SentriText.bodySmall.copyWith(color: SentriColors.caution),
        ),
        const SizedBox(height: SentriSpacing.xl),
        // No local color override — retrying a voice-message upload isn't
        // itself an emergency action (the manual SOS already succeeded),
        // so it takes the app's ordinary primary-button treatment.
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
        const SizedBox(height: SentriSpacing.md),
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip', style: TextStyle(color: SentriColors.textMuted)),
        ),
      ],
    );
  }
}
