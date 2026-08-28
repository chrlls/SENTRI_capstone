import 'dart:async';
import 'dart:math' show cos, pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

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
/// reverses the animation and fires nothing.
///
/// **One particle behaviour across every phase** (see
/// [SosParticleFieldPainter]): particles are born at the disc edge, drift
/// out, fade, and loop on a single continuous [_emissionController] clock.
/// The only thing that changes by phase is the emission *intensity* —
/// `holdProgress²` while holding (so the field fills as a progress read),
/// then pinned at `1.0` through sending/sent. Because the clock never
/// stops and intensity is already full when the hold completes, the
/// hold→sending hand-off has no seam.
///
/// The disc itself never changes size or position in any phase — only its
/// color (on confirmation) and center content. The halo rings do a faster
/// "transmit" swell while sending/sent (a more urgent version of the idle
/// "armed" breath). (An earlier version shrank the disc into a small
/// pulsing dot during sending; that was a misread and is fully gone.)
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

  /// Quick disc "press" acknowledgement (scale to 0.97) the instant the
  /// finger lands — the particle field takes ~750ms to visibly ramp, so
  /// without this the first beat of a hold has no response at all. Held
  /// down for the whole gesture, released on completion or early release.
  late final AnimationController _pressController;

  /// Slow ambient breathing on the halo rings only (never the disc or its
  /// label) while the button sits idle and untouched — a state cue that
  /// the control is armed, not a static graphic. Stopped under reduced
  /// motion (see [didChangeDependencies]).
  late final AnimationController _idleController;

  /// The single looping clock every particle rides, plus the halo
  /// transmit-pulse. Started on pointer-down, kept running through
  /// sending/sent, stopped on idle or an early release. Off under reduced
  /// motion (see [didChangeDependencies]).
  late final AnimationController _emissionController;

  late final List<SosParticle> _particles;

  /// Hold-progress fractions at which a light detent tick fires, so the
  /// 2.5s hold has an escalating physical ramp toward the commit. Reset to
  /// -1 on each new press ([_onPointerDown]) so a second hold re-ticks.
  static const List<double> _hapticMilestones = [0.3, 0.6, 0.85];
  int _lastHapticMilestone = -1;

  @override
  void initState() {
    super.initState();

    _holdController = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener(_handleHoldStatusChanged)
      ..addListener(_fireHoldMilestoneHaptics);

    _sentBurstController = AnimationController(
      vsync: this,
      duration: HoldToConfirmSosButton.sentAnimationDuration,
    );

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      reverseDuration: const Duration(milliseconds: 160),
    );

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _emissionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _particles = generateSosParticles();
  }

  /// Continuous motion (idle breath, particle emission clock) runs only
  /// when the OS "remove animations" setting is off — checked here rather
  /// than in `initState` because `MediaQuery` isn't available yet there,
  /// and re-checked if the setting is toggled while this screen is open.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _idleController.stop();
      _emissionController.stop();
    } else {
      if (!_idleController.isAnimating) {
        _idleController.repeat(reverse: true);
      }
      final emitting = _isTransmitting || _holdController.value > 0;
      if (emitting && !_emissionController.isAnimating) {
        _emissionController.repeat();
      }
    }
  }

  bool get _isTransmitting =>
      widget.phase == SosButtonPhase.sending || widget.phase == SosButtonPhase.sent;

  void _handleHoldStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      HapticFeedback.heavyImpact();
      _pressController.reverse();
      widget.onHoldComplete();
    } else if (status == AnimationStatus.dismissed) {
      // Early release has fully reversed — the field has emptied itself
      // (emissionIntensity rode holdProgress back to 0), so park the clock.
      _emissionController.stop();
      _emissionController.value = 0;
    }
  }

  /// Fires a detent tick when the hold crosses the next [_hapticMilestones]
  /// threshold. Gated to `forward` so reversing past a threshold on an
  /// early release stays silent.
  void _fireHoldMilestoneHaptics() {
    if (_holdController.status != AnimationStatus.forward) {
      return;
    }
    var reached = -1;
    for (var i = 0; i < _hapticMilestones.length; i++) {
      if (_holdController.value >= _hapticMilestones[i]) {
        reached = i;
      }
    }
    if (reached > _lastHapticMilestone) {
      HapticFeedback.selectionClick();
    }
    _lastHapticMilestone = reached;
  }

  @override
  void didUpdateWidget(HoldToConfirmSosButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The clock is normally already running (started on pointer-down and
    // kept alive through the hold). This is just a safety net for a
    // `sending` phase that somehow arrives without a preceding hold.
    if (widget.phase == SosButtonPhase.sending &&
        oldWidget.phase != SosButtonPhase.sending &&
        !_emissionController.isAnimating &&
        !MediaQuery.of(context).disableAnimations) {
      _emissionController.repeat();
    }

    if (widget.phase == SosButtonPhase.sent && oldWidget.phase != SosButtonPhase.sent) {
      _sentBurstController.forward(from: 0);
      // Emission clock keeps running from `sending` into `sent` — the
      // stream and halo pulse just crossfade to green via `confirmProgress`.
    }

    if (widget.phase == SosButtonPhase.idle && oldWidget.phase != SosButtonPhase.idle) {
      _holdController.value = 0;
      _sentBurstController.value = 0;
      _emissionController.stop();
      _emissionController.value = 0;
    }
  }

  @override
  void dispose() {
    _holdController.dispose();
    _sentBurstController.dispose();
    _pressController.dispose();
    _idleController.dispose();
    _emissionController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (widget.phase != SosButtonPhase.idle) {
      return;
    }
    _lastHapticMilestone = -1;
    HapticFeedback.selectionClick();
    _pressController.forward();
    _holdController.forward();
    // The particle emission clock runs for the whole gesture, not just
    // sending — so the hold field is already a live stream that simply
    // keeps flowing when the SOS fires.
    if (!MediaQuery.of(context).disableAnimations) {
      _emissionController.repeat();
    }
  }

  void _onPointerUp(PointerEvent _) {
    if (_holdController.status == AnimationStatus.forward) {
      // Released before completion — a soft "nothing sent" tap, distinct
      // from the heavy impact a real send fires.
      HapticFeedback.lightImpact();
      _holdController.reverse();
    }
    _pressController.reverse();
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
          animation: Listenable.merge([
            _holdController,
            _sentBurstController,
            _pressController,
            _idleController,
            _emissionController,
          ]),
          builder: (context, _) {
            final phase = widget.phase;
            final sentBurst = _sentBurstController.value;
            final confirmProgress =
                phase == SosButtonPhase.sent ? Curves.easeInOut.transform((sentBurst / 0.6).clamp(0.0, 1.0)) : 0.0;

            // Whole button (disc, halo, label) dips to 0.97 while pressed —
            // instant touch acknowledgement ahead of the particle ramp.
            final pressScale =
                reduceMotion ? 1.0 : 1.0 - 0.03 * Curves.easeOut.transform(_pressController.value);
            final idlePulse = reduceMotion ? 0.0 : _idleController.value;

            // One emission model for hold + sending + sent. Intensity is
            // the only phase-dependent input: holdProgress² while holding
            // (an accelerating fill = the progress read), pinned at 1 once
            // transmitting. The clock is frozen under reduced motion so
            // particles hold static positions and just appear by intensity.
            final hold = _holdController.value;
            final emissionIntensity = _isTransmitting ? 1.0 : hold * hold;
            final emissionClock = reduceMotion ? 0.0 : _emissionController.value;

            // Halo transmit-pulse: only while sending/sent, only with
            // motion on. A faster, slightly bigger version of the idle
            // "armed" breath. `(1 - cos)/2` gives one clean swell per clock
            // cycle.
            final transmitting = _isTransmitting && !reduceMotion;
            final transmitPulse =
                transmitting ? (1 - cos(_emissionController.value * 2 * pi)) / 2 : 0.0;

            return Transform.scale(
              scale: pressScale,
              child: CustomPaint(
                painter: _SosButtonPainter(
                  emissionClock: emissionClock,
                  emissionIntensity: emissionIntensity,
                  confirmProgress: confirmProgress,
                  phase: phase,
                  particles: _particles,
                  reduceMotion: reduceMotion,
                  idlePulse: idlePulse,
                  transmitting: transmitting,
                  transmitPulse: transmitPulse,
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
  final double emissionClock;
  final double emissionIntensity;
  final double confirmProgress;
  final SosButtonPhase phase;
  final List<SosParticle> particles;
  final bool reduceMotion;

  /// 0..1 breathing phase for the idle "armed" halo pulse. Only has any
  /// effect while the button is genuinely at rest (see [_atRest]); pinned
  /// to 0 by the caller under reduced motion.
  final double idlePulse;

  /// True while sending/sent with motion allowed — the halo rings do a
  /// faster "transmit" swell instead of the idle breath.
  final bool transmitting;

  /// 0..1 swell value for that transmit pulse (one clean hump per emission
  /// clock cycle). 0 outside the transmit state.
  final double transmitPulse;

  _SosButtonPainter({
    required this.emissionClock,
    required this.emissionIntensity,
    required this.confirmProgress,
    required this.phase,
    required this.particles,
    required this.reduceMotion,
    required this.idlePulse,
    required this.transmitting,
    required this.transmitPulse,
  });

  bool get _atRest => emissionIntensity == 0 && confirmProgress <= 0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = _discRadius;

    _paintHalo(canvas, center, radius);

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
      emissionClock: emissionClock,
      emissionIntensity: emissionIntensity,
      confirmProgress: confirmProgress,
      discRadius: radius,
      reduceMotion: reduceMotion,
    ).paint(canvas, size);
  }

  /// The two soft filled halo rings behind the disc.
  ///
  /// - **idle / hold**: alpha swells ±6% on the slow `idlePulse` "armed"
  ///   breath while genuinely at rest; flat otherwise / under reduced
  ///   motion. No size change.
  /// - **transmit** (sending/sent): the same rings, but each frame's
  ///   `transmitPulse` grows the radius a few px and lifts the alpha — a
  ///   faster, slightly bigger version of the same breath.
  ///
  /// Both crossfade to green with `confirmProgress` (same shortest-arc hue
  /// path as the disc/particles).
  void _paintHalo(Canvas canvas, Offset center, double radius) {
    final double radiusBoostOuter;
    final double radiusBoostInner;
    final double alphaMult;

    if (transmitting) {
      final swell = Curves.easeInOut.transform(transmitPulse);
      radiusBoostOuter = 4.0 * swell;
      radiusBoostInner = 3.0 * swell;
      alphaMult = 0.85 + 0.30 * swell;
    } else {
      radiusBoostOuter = 0;
      radiusBoostInner = 0;
      alphaMult =
          (_atRest && !reduceMotion) ? 0.94 + 0.06 * Curves.easeInOut.transform(idlePulse) : 1.0;
    }

    final glowOuter = confirmProgress <= 0
        ? _scaleAlpha(SentriColors.glowOuter, alphaMult)
        : lerpWarmToSafeColor(SentriColors.glowOuter, SentriColors.success.withValues(alpha: 0.08), confirmProgress);
    final glowInner = confirmProgress <= 0
        ? _scaleAlpha(SentriColors.glowInner, alphaMult)
        : lerpWarmToSafeColor(SentriColors.glowInner, SentriColors.success.withValues(alpha: 0.16), confirmProgress);
    canvas.drawCircle(center, radius + 50 + radiusBoostOuter, Paint()..color = glowOuter);
    canvas.drawCircle(center, radius + 25 + radiusBoostInner, Paint()..color = glowInner);
  }

  @override
  bool shouldRepaint(covariant _SosButtonPainter oldDelegate) {
    return oldDelegate.emissionClock != emissionClock ||
        oldDelegate.emissionIntensity != emissionIntensity ||
        oldDelegate.confirmProgress != confirmProgress ||
        oldDelegate.phase != phase ||
        oldDelegate.reduceMotion != reduceMotion ||
        oldDelegate.idlePulse != idlePulse ||
        oldDelegate.transmitting != transmitting ||
        oldDelegate.transmitPulse != transmitPulse;
  }
}

Color _scaleAlpha(Color color, double factor) =>
    color.withValues(alpha: (color.a * factor).clamp(0.0, 1.0));
