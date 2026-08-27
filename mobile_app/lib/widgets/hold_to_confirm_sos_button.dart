import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';
import 'sos_particle_field.dart';

/// Visual/interaction phase driven by the parent screen once the hold
/// gesture itself completes — everything before completion (idle, the
/// hold progress itself) is this widget's own internal state, since the
/// parent has no reason to know about in-progress touch state.
enum SosButtonPhase { idle, sending, sent }

const _diameter = 220.0;
const _discRadius = _diameter / 2;

/// Holding for [holdDuration] fires [onHoldComplete]; releasing early
/// reverses the animation and fires nothing. Progress during the hold is
/// communicated entirely by [SosParticleFieldPainter]'s emission-based
/// particle field. The button's size and position never change across
/// phases — only the color (on confirmation) and the center content
/// change. (An earlier version of this widget shrank the disc into a small
/// pulsing dot during the sending phase; that concept was a misreading of
/// the actual request and has been fully removed — the button stays fixed
/// size/position always.)
class HoldToConfirmSosButton extends StatefulWidget {
  final SosButtonPhase phase;
  final VoidCallback onHoldComplete;
  final Duration holdDuration;

  /// Duration of the full "sent" success transition (disc + particle field
  /// crossfading to green, checkmark entrance). Exposed so callers that
  /// chain further navigation after a successful send can wait for this
  /// exact duration rather than guessing a disconnected magic number.
  static const Duration sentAnimationDuration = Duration(milliseconds: 650);

  const HoldToConfirmSosButton({
    super.key,
    required this.phase,
    required this.onHoldComplete,
    this.holdDuration = const Duration(milliseconds: 2500),
  });

  @override
  State<HoldToConfirmSosButton> createState() => _HoldToConfirmSosButtonState();
}

class _HoldToConfirmSosButtonState extends State<HoldToConfirmSosButton>
    with TickerProviderStateMixin {
  late final AnimationController _holdController;
  late final AnimationController _sentBurstController;
  late final List<SosParticle> _particles;

  @override
  void initState() {
    super.initState();

    _holdController = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener(_handleHoldStatusChanged);

    _sentBurstController = AnimationController(
      vsync: this,
      duration: HoldToConfirmSosButton.sentAnimationDuration,
    );

    _particles = generateSosParticles();
  }

  void _handleHoldStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onHoldComplete();
    }
  }

  @override
  void didUpdateWidget(HoldToConfirmSosButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == SosButtonPhase.sent && oldWidget.phase != SosButtonPhase.sent) {
      _sentBurstController.forward(from: 0);
    }
    if (widget.phase == SosButtonPhase.idle && oldWidget.phase != SosButtonPhase.idle) {
      _holdController.value = 0;
      _sentBurstController.value = 0;
    }
  }

  @override
  void dispose() {
    _holdController.dispose();
    _sentBurstController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (widget.phase != SosButtonPhase.idle) {
      return;
    }
    _holdController.forward();
  }

  void _onPointerUp(PointerEvent _) {
    if (_holdController.status == AnimationStatus.forward) {
      _holdController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Listener + raw pointer events, not GestureDetector's onTap* — the
    // tap gesture arena applies touch-slop cancellation meant for quick
    // taps, and a real 2.5s hold (finger micro-tremor, or even adb's
    // synthetic swipe sampling) drifts past that slop well before
    // completion, silently cancelling the whole gesture mid-hold. A
    // sustained hold needs to track the pointer directly instead.
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: SizedBox(
        width: _diameter + 140,
        height: _diameter + 140,
        child: AnimatedBuilder(
          animation: Listenable.merge([_holdController, _sentBurstController]),
          builder: (context, _) {
            final phase = widget.phase;
            final sentBurst = _sentBurstController.value;
            final confirmProgress =
                phase == SosButtonPhase.sent ? Curves.easeInOut.transform((sentBurst / 0.6).clamp(0.0, 1.0)) : 0.0;

            return CustomPaint(
              painter: _SosButtonPainter(
                holdProgress: _holdController.value,
                confirmProgress: confirmProgress,
                phase: phase,
                particles: _particles,
                reduceMotion: reduceMotion,
              ),
              child: Center(
                child: SizedBox(
                  width: _diameter,
                  height: _diameter,
                  child: Center(
                    child: _ButtonLabel(
                      phase: phase,
                      holdProgress: _holdController.value,
                      sentBurst: sentBurst,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  final SosButtonPhase phase;
  final double holdProgress;
  final double sentBurst;

  const _ButtonLabel({
    required this.phase,
    required this.holdProgress,
    required this.sentBurst,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case SosButtonPhase.sending:
        // Replaces the old spinner in place, at the button's normal
        // size — no resize, no separate loading indicator. The cycling
        // subtext's own cross-fade is the only motion here.
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sending your\nalert...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.25),
              ),
              SizedBox(height: 8),
              _CyclingSubtext(
                phrases: ['Reaching emergency\nresponders', 'Confirming your\nlocation'],
              ),
            ],
          ),
        );
      case SosButtonPhase.sent:
        // Enters 65ms into the 650ms success burst, over ~228ms — icon and
        // text arrive together as one unit, since the red->green color
        // change alone must not be the only signal that this succeeded.
        final labelT = Curves.easeOutCubic.transform(((sentBurst - 0.1) / 0.35).clamp(0.0, 1.0));
        return Opacity(
          opacity: labelT,
          child: Transform.scale(
            scale: 0.85 + labelT * 0.15,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, color: Colors.white, size: 28),
                SizedBox(height: 6),
                Text(
                  'SOS SENT',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
        );
      case SosButtonPhase.idle:
        return Text(
          holdProgress > 0.02 ? 'HOLD…' : 'HOLD TO\nSEND SOS',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        );
    }
  }
}

/// Cycles through short atmospheric phrases while genuinely waiting on the
/// backend — a `Timer` + `AnimatedSwitcher` crossfade, not a restart of the
/// button's own animation tree just to swap text. Purely atmospheric: there
/// is no partial-progress data from a single SOS submission, so this never
/// implies a real step count. Lives inside the button (not the surrounding
/// screen) since the sending-phase content renders in place of the old
/// spinner, at the button's own size.
class _CyclingSubtext extends StatefulWidget {
  final List<String> phrases;

  const _CyclingSubtext({required this.phrases});

  @override
  State<_CyclingSubtext> createState() => _CyclingSubtextState();
}

class _CyclingSubtextState extends State<_CyclingSubtext> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1350), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _index = (_index + 1) % widget.phrases.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        widget.phrases[_index],
        key: ValueKey(_index),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
      ),
    );
  }
}

class _SosButtonPainter extends CustomPainter {
  final double holdProgress;
  final double confirmProgress;
  final SosButtonPhase phase;
  final List<SosParticle> particles;
  final bool reduceMotion;

  _SosButtonPainter({
    required this.holdProgress,
    required this.confirmProgress,
    required this.phase,
    required this.particles,
    required this.reduceMotion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = _discRadius;

    // Soft halo behind the disc, always visible — the same layered-glow
    // treatment as before, crossfading to green on confirmation (same
    // shortest-arc hue path as the disc/particles, so nothing red-toned is
    // left behind once the disc has turned).
    final glowOuter = confirmProgress <= 0
        ? SentriColors.glowOuter
        : lerpWarmToSafeColor(SentriColors.glowOuter, SentriColors.success.withValues(alpha: 0.08), confirmProgress);
    final glowInner = confirmProgress <= 0
        ? SentriColors.glowInner
        : lerpWarmToSafeColor(SentriColors.glowInner, SentriColors.success.withValues(alpha: 0.16), confirmProgress);
    canvas.drawCircle(center, radius + 50, Paint()..color = glowOuter);
    canvas.drawCircle(center, radius + 25, Paint()..color = glowInner);

    // The disc is a precise, undistorted circle in every phase — shape,
    // size, and position never change, only color. `lerpWarmToSafeColor`
    // (a hand-rolled shortest-arc hue interpolation, not the built-in
    // `HSVColor.lerp` — see sos_particle_field.dart's doc comment for why)
    // sweeps through orange/yellow at the midpoint instead of the muddy
    // brown a direct RGB lerp gives, or the teal/cyan `HSVColor.lerp`
    // itself gives — both confirmed by rendering, not assumed.
    final discColor = confirmProgress <= 0
        ? SentriColors.primaryRed
        : lerpWarmToSafeColor(SentriColors.primaryRed, SentriColors.success, confirmProgress);
    canvas.drawCircle(center, radius, Paint()..color = discColor);

    SosParticleFieldPainter(
      particles: particles,
      holdProgress: holdProgress,
      confirmProgress: confirmProgress,
      discRadius: radius,
      reduceMotion: reduceMotion,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _SosButtonPainter oldDelegate) {
    return oldDelegate.holdProgress != holdProgress ||
        oldDelegate.confirmProgress != confirmProgress ||
        oldDelegate.phase != phase ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
