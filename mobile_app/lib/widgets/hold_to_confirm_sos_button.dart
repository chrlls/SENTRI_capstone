import 'dart:math' show cos, pi;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/sentri_colors.dart';
import 'sos_particle_field.dart';

/// Visual/interaction phase driven by the parent screen once the hold
/// gesture itself completes — everything before completion (idle, the
/// hold progress itself) is this widget's own internal state, since the
/// parent has no reason to know about in-progress touch state.
enum SosButtonPhase { idle, sending, sent }

const _diameter = 220.0;
const _discRadius = _diameter / 2;

/// Holding for the real elapsed [holdDuration] fires [onHoldComplete];
/// releasing early cancels and fires nothing. The hold is gated by a
/// `Stopwatch` + `Ticker` ([_HoldToConfirmSosButtonState._holdWatch] /
/// `_holdProgress`), never an `AnimationController` — an `AnimationController`
/// completes instantly under the OS "remove animations" setting, which
/// would let a tap fire an SOS with no hold at all (Decision 31 Open
/// Item A / mobile UI audit item 1.7).
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

  /// Reports the real (Stopwatch-derived) hold fraction 0..1 as it changes,
  /// and `0` the instant a hold is cancelled or reset. Lets the parent
  /// screen show its own "Release to cancel" affordance alongside the
  /// percentage the button paints in its centre. Never fed back into the
  /// gate.
  final ValueChanged<double>? onHoldProgress;

  final Duration holdDuration;

  /// Idle-state centre label. Defaults to the full SOS screen's wording;
  /// the app-shell nav-bar button overrides it with a short "SOS" so the
  /// same widget (same hold gate) can be reused at a smaller footprint
  /// without the multi-line label becoming illegible once scaled down.
  /// Only the idle, not-yet-holding label is affected — the holding /
  /// sending / sent labels are unchanged.
  final String idleLabel;

  /// Optional style override for [idleLabel] (again for the smaller
  /// nav-bar reuse, where the default 18px reads too small after the
  /// scale-down). Null keeps the default idle style.
  final TextStyle? idleLabelStyle;

  /// The soft radial halo rings behind the disc. On by default (the full
  /// SOS screen). The app-shell nav-bar button turns them off: nested in
  /// the pill's notch the halo would read as a "glow" around the SOS
  /// circle and defeat the separation-ring illusion. The particle field
  /// and every phase behaviour are unaffected.
  final bool showHalo;

  /// Duration of the full "sent" success transition (disc + particle field
  /// crossfading to green, checkmark entrance). Exposed so callers that
  /// chain further navigation after a successful send can wait for this
  /// exact duration rather than guessing a disconnected magic number.
  static const Duration sentAnimationDuration = Duration(milliseconds: 650);

  const HoldToConfirmSosButton({
    super.key,
    required this.phase,
    required this.onHoldComplete,
    this.onHoldProgress,
    this.holdDuration = const Duration(milliseconds: 2500),
    this.idleLabel = 'HOLD TO\nSEND SOS',
    this.idleLabelStyle,
    this.showHalo = true,
  });

  @override
  State<HoldToConfirmSosButton> createState() => _HoldToConfirmSosButtonState();
}

class _HoldToConfirmSosButtonState extends State<HoldToConfirmSosButton>
    with TickerProviderStateMixin {
  /// The hold gate's single source of truth: real elapsed wall-clock time,
  /// immune to animation scale. Decision 31 Open Item A.
  final Stopwatch _holdWatch = Stopwatch();

  /// Schedules a per-frame rebuild while a hold is in progress so [build]
  /// re-reads [_holdProgress], and is where completion is detected. A
  /// `Ticker` keeps firing regardless of the OS "remove animations"
  /// setting — only `AnimationController` durations are affected by it.
  late final Ticker _holdTicker;

  /// 0..1 fraction of [HoldToConfirmSosButton.holdDuration] actually held,
  /// derived from [_holdWatch]. This — never an animation value — is what
  /// the particle fill and any percentage readout read from.
  double _holdProgress = 0;

  /// True once [HoldToConfirmSosButton.onHoldComplete] has fired for the
  /// current press, so a stray already-queued tick can't fire it twice.
  /// Cleared on the next pointer-down.
  bool _holdCompleted = false;

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

  /// Purely decorative: on an early release, ramps the particle fill from
  /// its value at the moment of cancellation back down to empty over ~1s
  /// instead of snapping. Has **no** bearing on the hold gate — [_holdWatch]
  /// / [_holdProgress] / [onHoldComplete] never read it.
  late final AnimationController _cancelDecayController;

  /// The `emissionIntensity` captured when the current fade-back started;
  /// the decay interpolates this → 0. Zero when no fade-back is running.
  double _cancelFillFrom = 0;

  late final List<SosParticle> _particles;

  /// Hold-progress fractions at which a light detent tick fires, so the
  /// 2.5s hold has an escalating physical ramp toward the commit. Reset to
  /// -1 on each new press ([_onPointerDown]) so a second hold re-ticks.
  static const List<double> _hapticMilestones = [0.3, 0.6, 0.85];
  int _lastHapticMilestone = -1;

  @override
  void initState() {
    super.initState();

    _holdTicker = createTicker(_onHoldTick);

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

    _cancelDecayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener(_handleCancelDecayStatus);

    _particles = generateSosParticles();

    // Constructed already in the `sent` phase (e.g. an SOS was fired from
    // the app-shell nav button, and the full SOS screen is opened
    // afterward): there's no idle→sent transition for `didUpdateWidget` to
    // catch, so settle straight into the confirmed look with no burst.
    if (widget.phase == SosButtonPhase.sent) {
      _sentBurstController.value = 1.0;
    }
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
      // Don't leave a decorative fade-back running once the OS asks for
      // no animation — jump it to empty.
      if (_cancelDecayController.isAnimating) {
        _cancelDecayController.stop();
        _cancelDecayController.value = 0;
        _cancelFillFrom = 0;
        _emissionController.value = 0;
      }
    } else {
      if (!_idleController.isAnimating) {
        _idleController.repeat(reverse: true);
      }
      final emitting = _isTransmitting || _holdWatch.isRunning;
      if (emitting && !_emissionController.isAnimating) {
        _emissionController.repeat();
      }
    }
  }

  bool get _isTransmitting =>
      widget.phase == SosButtonPhase.sending ||
      widget.phase == SosButtonPhase.sent;

  /// Runs every frame while [_holdWatch] is running. Reads real elapsed
  /// time (not an animation value), fires the escalating detent haptics,
  /// and completes the gate once the full [HoldToConfirmSosButton.holdDuration]
  /// has genuinely elapsed.
  void _onHoldTick(Duration _) {
    if (!_holdWatch.isRunning) {
      return;
    }
    final progress =
        (_holdWatch.elapsed.inMicroseconds / widget.holdDuration.inMicroseconds)
            .clamp(0.0, 1.0);

    _fireHoldMilestoneHaptics(progress);

    if (progress >= 1.0) {
      _completeHold();
      return;
    }
    _setHoldProgress(progress);
  }

  /// Single place the hold fraction is written — keeps the parent's
  /// [HoldToConfirmSosButton.onHoldProgress] mirror in lockstep with the
  /// value the button paints.
  void _setHoldProgress(double value) {
    setState(() => _holdProgress = value);
    widget.onHoldProgress?.call(value);
  }

  /// When the decorative fade-back finishes, park the emission clock and
  /// clear the captured value. Skipped if a fresh hold started meanwhile
  /// (that hold owns the field now).
  void _handleCancelDecayStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _holdWatch.isRunning) {
      return;
    }
    _emissionController.stop();
    _emissionController.value = 0;
    setState(() => _cancelFillFrom = 0);
  }

  void _completeHold() {
    if (_holdCompleted) {
      return;
    }
    _holdCompleted = true;
    _holdWatch
      ..stop()
      ..reset();
    _holdTicker.stop();
    HapticFeedback.heavyImpact();
    _pressController.reverse();
    _setHoldProgress(1.0);
    widget.onHoldComplete();
  }

  /// Fires a detent tick when the real hold crosses the next
  /// [_hapticMilestones] threshold. [_lastHapticMilestone] is a per-press
  /// high-water mark, so releasing and re-holding re-ticks and a stalled
  /// hold doesn't repeat.
  void _fireHoldMilestoneHaptics(double progress) {
    var reached = -1;
    for (var i = 0; i < _hapticMilestones.length; i++) {
      if (progress >= _hapticMilestones[i]) {
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

    if (widget.phase == SosButtonPhase.sent &&
        oldWidget.phase != SosButtonPhase.sent) {
      _sentBurstController.forward(from: 0);
      // Emission clock keeps running from `sending` into `sent` — the
      // stream and halo pulse just crossfade to green via `confirmProgress`.
    }

    if (widget.phase == SosButtonPhase.idle &&
        oldWidget.phase != SosButtonPhase.idle) {
      _holdWatch
        ..stop()
        ..reset();
      _holdTicker.stop();
      _holdProgress = 0;
      _holdCompleted = false;
      widget.onHoldProgress?.call(0);
      _sentBurstController.value = 0;
      _emissionController.stop();
      _emissionController.value = 0;
      _cancelDecayController.stop();
      _cancelDecayController.value = 0;
      _cancelFillFrom = 0;
    }
  }

  @override
  void dispose() {
    _holdTicker.dispose();
    _sentBurstController.dispose();
    _pressController.dispose();
    _idleController.dispose();
    _emissionController.dispose();
    _cancelDecayController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    // A pointer event can still be routed here after this State is torn
    // down — the framework delivers up/cancel to the original down-target
    // even once it's off-screen. Touching a disposed AnimationController
    // then asserts.
    if (!mounted) {
      return;
    }
    // Ignore a second finger while a hold is already running, and any
    // touch once the gesture is out of the idle phase.
    if (widget.phase != SosButtonPhase.idle || _holdWatch.isRunning) {
      return;
    }
    _lastHapticMilestone = -1;
    _holdCompleted = false;
    // Abandon any decorative fade-back still running from a previous
    // cancel — this new hold owns the field now.
    _cancelDecayController.stop();
    _cancelDecayController.value = 0;
    _cancelFillFrom = 0;
    HapticFeedback.selectionClick();
    _pressController.forward();
    // Start the real elapsed-time gate — a Stopwatch measured against
    // wall-clock time, ticked per frame. Neither the Stopwatch nor the
    // Ticker is affected by the OS "remove animations" setting, so the
    // full hold duration is always required (Decision 31 Open Item A).
    _holdWatch
      ..reset()
      ..start();
    _holdTicker.start();
    // The particle emission clock runs for the whole gesture, not just
    // sending — so the hold field is already a live stream that simply
    // keeps flowing when the SOS fires.
    if (!MediaQuery.of(context).disableAnimations) {
      _emissionController.repeat();
    }
  }

  void _onPointerUp(PointerEvent _) {
    // See _onPointerDown: a queued up/cancel can arrive after disposal.
    if (!mounted) {
      return;
    }
    if (_holdWatch.isRunning) {
      // Released before the full duration elapsed — cancel. A soft
      // "nothing sent" tap, distinct from the heavy impact a real send
      // fires. If the hold already completed, [_holdWatch] is stopped and
      // this branch is skipped — the send has fired and is not undone.
      HapticFeedback.lightImpact();
      final fillAtCancel = _holdProgress * _holdProgress;
      _holdWatch
        ..stop()
        ..reset();
      _holdTicker.stop();
      _lastHapticMilestone = -1;

      if (MediaQuery.of(context).disableAnimations) {
        // OS asked for no animation — clear the fill immediately.
        _emissionController.stop();
        _emissionController.value = 0;
        _cancelFillFrom = 0;
      } else {
        // Decorative only: let the particle fill drift and fade out over
        // ~1s. The hold is already cancelled above; this controller has no
        // influence on the gate. The emission clock keeps looping so the
        // particles keep moving while they fade — it is parked in
        // [_handleCancelDecayStatus] once the decay finishes.
        _cancelFillFrom = fillAtCancel;
        _cancelDecayController.forward(from: 0);
      }
      _setHoldProgress(0);
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
          // Hold progress no longer lives in an animation — [_onHoldTick]
          // calls setState each frame while a hold is in progress.
          animation: Listenable.merge([
            _sentBurstController,
            _pressController,
            _idleController,
            _emissionController,
            _cancelDecayController,
          ]),
          builder: (context, _) {
            final phase = widget.phase;
            final sentBurst = _sentBurstController.value;
            final confirmProgress = phase == SosButtonPhase.sent
                ? Curves.easeInOut.transform((sentBurst / 0.6).clamp(0.0, 1.0))
                : 0.0;

            // Whole button (disc, halo, label) dips to 0.97 while pressed —
            // instant touch acknowledgement ahead of the particle ramp.
            final pressScale = reduceMotion
                ? 1.0
                : 1.0 - 0.03 * Curves.easeOut.transform(_pressController.value);
            final idlePulse = reduceMotion ? 0.0 : _idleController.value;

            // One emission model for hold + sending + sent. Intensity is
            // the only phase-dependent input: `_holdProgress²` (the real
            // Stopwatch-derived hold fraction) while holding — an
            // accelerating fill that IS the progress read — pinned at 1
            // once transmitting. The clock is frozen under reduced motion
            // so particles hold static positions and just appear by
            // intensity.
            final holdFill = _isTransmitting
                ? 1.0
                : _holdProgress * _holdProgress;
            // Decorative fade-back after an early release: `_cancelFillFrom`
            // eases to 0 as `_cancelDecayController` runs. Purely visual —
            // it never feeds the gate. `max` so a fresh hold overtakes it.
            final decayFill = reduceMotion
                ? 0.0
                : _cancelFillFrom *
                      (1.0 -
                          Curves.easeOut.transform(
                            _cancelDecayController.value,
                          ));
            final emissionIntensity = holdFill > decayFill
                ? holdFill
                : decayFill;
            final emissionClock = reduceMotion
                ? 0.0
                : _emissionController.value;

            // Halo transmit-pulse: only while sending/sent, only with
            // motion on. A faster, slightly bigger version of the idle
            // "armed" breath. `(1 - cos)/2` gives one clean swell per clock
            // cycle.
            final transmitting = _isTransmitting && !reduceMotion;
            final transmitPulse = transmitting
                ? (1 - cos(_emissionController.value * 2 * pi)) / 2
                : 0.0;

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
                  showHalo: widget.showHalo,
                ),
                child: Center(
                  child: SizedBox(
                    width: _diameter,
                    height: _diameter,
                    child: Center(
                      child: _ButtonLabel(
                        phase: phase,
                        holdProgress: _holdProgress,
                        sentBurst: sentBurst,
                        idleLabel: widget.idleLabel,
                        idleLabelStyle: widget.idleLabelStyle,
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
  final String idleLabel;
  final TextStyle? idleLabelStyle;

  const _ButtonLabel({
    required this.phase,
    required this.holdProgress,
    required this.sentBurst,
    required this.idleLabel,
    required this.idleLabelStyle,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case SosButtonPhase.sending:
        // Screen 3 (Decision 31): a truthful "sending" state — no rotating
        // atmospheric phrases (those implied progress that wasn't measured
        // and kept reassuring during a stalled send; audit 1.6/R2). The
        // GPS/Network/Alert row below the button carries the real detail.
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.send, color: Colors.white, size: 24),
              SizedBox(height: 6),
              Text(
                'SENDING SOS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Sharing your location\nwith responders',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );
      case SosButtonPhase.sent:
        // Screen 4 — persists. Enters 65ms into the 650ms success burst so
        // the icon and text arrive as one unit, since the red->green
        // colour change alone must not be the only "it worked" signal.
        final labelT = Curves.easeOutCubic.transform(
          ((sentBurst - 0.1) / 0.35).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: labelT,
          child: Transform.scale(
            scale: 0.85 + labelT * 0.15,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.check, color: Colors.white, size: 26),
                  SizedBox(height: 6),
                  Text(
                    'SOS CONFIRMED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your emergency alert\nhas been received.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case SosButtonPhase.idle:
        if (holdProgress > 0.02) {
          // Screen 2 — the readout is the real Stopwatch-derived fraction,
          // not an animation value.
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'KEEP HOLDING',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(holdProgress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }
        return Text(
          idleLabel,
          textAlign: TextAlign.center,
          style: idleLabelStyle ??
              const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
        );
    }
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

  /// When false, [_paintHalo] is skipped entirely (app-shell nav-bar use).
  final bool showHalo;

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
    required this.showHalo,
  });

  bool get _atRest => emissionIntensity == 0 && confirmProgress <= 0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = _discRadius;

    if (showHalo) {
      _paintHalo(canvas, center, radius);
    }

    // The disc is a precise, undistorted circle in every phase — shape,
    // size, and position never change, only color. `lerpWarmToSafeColor`
    // (a hand-rolled shortest-arc hue interpolation, not the built-in
    // `HSVColor.lerp` — see sos_particle_field.dart's doc comment for why)
    // sweeps through orange/yellow at the midpoint instead of the muddy
    // brown a direct RGB lerp gives, or the teal/cyan `HSVColor.lerp`
    // itself gives — both confirmed by rendering, not assumed.
    final discColor = confirmProgress <= 0
        ? SentriColors.primaryRed
        : lerpWarmToSafeColor(
            SentriColors.primaryRed,
            SentriColors.success,
            confirmProgress,
          );
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
      alphaMult = (_atRest && !reduceMotion)
          ? 0.94 + 0.06 * Curves.easeInOut.transform(idlePulse)
          : 1.0;
    }

    final glowOuter = confirmProgress <= 0
        ? _scaleAlpha(SentriColors.glowOuter, alphaMult)
        : lerpWarmToSafeColor(
            SentriColors.glowOuter,
            SentriColors.success.withValues(alpha: 0.08),
            confirmProgress,
          );
    final glowInner = confirmProgress <= 0
        ? _scaleAlpha(SentriColors.glowInner, alphaMult)
        : lerpWarmToSafeColor(
            SentriColors.glowInner,
            SentriColors.success.withValues(alpha: 0.16),
            confirmProgress,
          );
    canvas.drawCircle(
      center,
      radius + 50 + radiusBoostOuter,
      Paint()..color = glowOuter,
    );
    canvas.drawCircle(
      center,
      radius + 25 + radiusBoostInner,
      Paint()..color = glowInner,
    );
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
        oldDelegate.transmitPulse != transmitPulse ||
        oldDelegate.showHalo != showHalo;
  }
}

Color _scaleAlpha(Color color, double factor) =>
    color.withValues(alpha: (color.a * factor).clamp(0.0, 1.0));
