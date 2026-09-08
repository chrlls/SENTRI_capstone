import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/sentri_colors.dart';

/// Visual/interaction phase driven by the parent screen once the hold
/// gesture itself completes — everything before completion (idle, the
/// hold progress itself) is this widget's own internal state, since the
/// parent has no reason to know about in-progress touch state.
/// [resolvedAcknowledgement]: the tracked incident reached a terminal
/// backend status (resolved / false_alarm / cancelled) while this screen
/// was showing `sent`. Visually a continuation of `sent` (still the
/// confirmed green disc, still transmitting) — [SosController] auto-drives
/// this back to `idle` after a few seconds; nothing in this widget times it.
enum SosButtonPhase { idle, sending, sent, resolvedAcknowledgement }

const _diameter = 220.0;
const _discRadius = _diameter / 2;

/// The real hold threshold, also read by the emergency reveal layer's
/// countdown readout so both are always describing the same underlying
/// gate — never two independently-maintained numbers that could drift
/// apart.
const Duration kSosHoldDuration = Duration(milliseconds: 2500);

/// Holding for the real elapsed [holdDuration] fires [onHoldComplete];
/// releasing early cancels and fires nothing. The hold is gated by a
/// `Stopwatch` + `Ticker` ([_HoldToConfirmSosButtonState._holdWatch] /
/// `_holdProgress`), never an `AnimationController` — an `AnimationController`
/// completes instantly under the OS "remove animations" setting, which
/// would let a tap fire an SOS with no hold at all (Decision 31 Open
/// Item A / mobile UI audit item 1.7).
///
/// The disc itself never changes size or position in any phase — only its
/// color (on confirmation) and center content.
class HoldToConfirmSosButton extends StatefulWidget {
  final SosButtonPhase phase;
  final VoidCallback onHoldComplete;

  /// Reports the real (Stopwatch-derived) hold fraction 0..1 as it changes,
  /// and `0` the instant a hold is cancelled or reset. Lets the parent
  /// screen show its own "Release to cancel" affordance alongside the
  /// percentage the button paints in its centre. Never fed back into the
  /// gate.
  final ValueChanged<double>? onHoldProgress;

  /// Fires once, right as the real hold gate starts (end of pointer-down).
  /// Purely a notification for decorative UI outside this widget (the
  /// emergency reveal layer) — nothing here reads it back.
  final VoidCallback? onHoldStart;

  /// Fires once on a genuine early release — a hold that started but was
  /// let go before [holdDuration] elapsed. Distinct from
  /// `onHoldProgress(0)`, which also fires on other phase resets (e.g. a
  /// failed send) that are not a cancellation of an in-progress hold.
  final VoidCallback? onHoldCancel;

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

  const HoldToConfirmSosButton({
    super.key,
    required this.phase,
    required this.onHoldComplete,
    this.onHoldProgress,
    this.onHoldStart,
    this.onHoldCancel,
    this.holdDuration = kSosHoldDuration,
    this.idleLabel = 'HOLD TO\nSEND SOS',
    this.idleLabelStyle,
  });

  @override
  State<HoldToConfirmSosButton> createState() => _HoldToConfirmSosButtonState();
}

class _HoldToConfirmSosButtonState extends State<HoldToConfirmSosButton>
    with SingleTickerProviderStateMixin {
  /// The hold gate's single source of truth: real elapsed wall-clock time,
  /// immune to animation scale. Decision 31 Open Item A.
  final Stopwatch _holdWatch = Stopwatch();

  /// Schedules a per-frame rebuild while a hold is in progress so [build]
  /// re-reads [_holdProgress], and is where completion is detected.
  late final Ticker _holdTicker;

  /// 0..1 fraction of [HoldToConfirmSosButton.holdDuration] actually held,
  /// derived from [_holdWatch]. Drives the percentage readout painted in
  /// the button's centre.
  double _holdProgress = 0;

  /// True once [HoldToConfirmSosButton.onHoldComplete] has fired for the
  /// current press, so a stray already-queued tick can't fire it twice.
  /// Cleared on the next pointer-down.
  bool _holdCompleted = false;

  /// Hold-progress fractions at which a light detent tick fires, so the
  /// 2.5s hold has an escalating physical ramp toward the commit. Reset to
  /// -1 on each new press ([_onPointerDown]) so a second hold re-ticks.
  static const List<double> _hapticMilestones = [0.3, 0.6, 0.85];
  int _lastHapticMilestone = -1;

  @override
  void initState() {
    super.initState();
    _holdTicker = createTicker(_onHoldTick);
  }

  bool get _isTransmitting =>
      widget.phase == SosButtonPhase.sending ||
      widget.phase == SosButtonPhase.sent ||
      widget.phase == SosButtonPhase.resolvedAcknowledgement;

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

    if (widget.phase == SosButtonPhase.idle &&
        oldWidget.phase != SosButtonPhase.idle) {
      _holdWatch
        ..stop()
        ..reset();
      _holdTicker.stop();
      _holdProgress = 0;
      _holdCompleted = false;
      widget.onHoldProgress?.call(0);
    }
  }

  @override
  void dispose() {
    _holdTicker.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    // A pointer event can still be routed here after this State is torn
    // down — the framework delivers up/cancel to the original down-target
    // even once it's off-screen.
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
    HapticFeedback.selectionClick();
    // Start the real elapsed-time gate — a Stopwatch measured against
    // wall-clock time, ticked per frame. Neither the Stopwatch nor the
    // Ticker is affected by the OS "remove animations" setting, so the
    // full hold duration is always required (Decision 31 Open Item A).
    _holdWatch
      ..reset()
      ..start();
    _holdTicker.start();
    widget.onHoldStart?.call();
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
      _holdWatch
        ..stop()
        ..reset();
      _holdTicker.stop();
      _lastHapticMilestone = -1;
      widget.onHoldCancel?.call();
      _setHoldProgress(0);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: CustomPaint(
          painter: _SosButtonPainter(
            confirmed: _isTransmitting &&
                (widget.phase == SosButtonPhase.sent ||
                    widget.phase == SosButtonPhase.resolvedAcknowledgement),
          ),
          child: Center(
            child: SizedBox(
              width: _diameter,
              height: _diameter,
              child: Center(
                child: _ButtonLabel(
                  phase: widget.phase,
                  holdProgress: _holdProgress,
                  idleLabel: widget.idleLabel,
                  idleLabelStyle: widget.idleLabelStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  final SosButtonPhase phase;
  final double holdProgress;
  final String idleLabel;
  final TextStyle? idleLabelStyle;

  const _ButtonLabel({
    required this.phase,
    required this.holdProgress,
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SendingToSentIndicator(phase: phase),
              const SizedBox(height: 6),
              const Text(
                'SENDING SOS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
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
        // Screen 4 — persists.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SendingToSentIndicator(phase: phase),
              const SizedBox(height: 6),
              const Text(
                'SOS CONFIRMED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
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
        );
      case SosButtonPhase.resolvedAcknowledgement:
        // The specific terminal wording (resolved / false alarm /
        // cancelled) renders in the screen's card below the button, not
        // here — this label stays generic since it's shared across all
        // three terminal outcomes.
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.check, color: Colors.white, size: 26),
              SizedBox(height: 6),
              Text(
                'ALERT CLOSED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
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

/// Paints a single, clean, dominant disc — no decorative rings, gradients,
/// or glow. Its color snaps between the alarm and confirmed colors rather
/// than crossfading; the only elevation cue is a restrained functional
/// drop shadow, not an ambient halo.
class _SosButtonPainter extends CustomPainter {
  final bool confirmed;

  _SosButtonPainter({required this.confirmed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = _discRadius;
    final discPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

    // A single, subtle drop shadow — just enough to lift the disc off the
    // white background. This is Flutter's physical-elevation shadow model
    // (directional, feathered toward the light), not a uniform blurred
    // circle, so it reads as functional depth rather than a glow.
    canvas.drawShadow(discPath, Colors.black, 4, false);

    final discColor =
        confirmed ? SentriColors.success : SentriColors.primaryRed;
    canvas.drawPath(discPath, Paint()..color = discColor);
  }

  @override
  bool shouldRepaint(covariant _SosButtonPainter oldDelegate) {
    return oldDelegate.confirmed != confirmed;
  }
}

/// The Sending→Sent icon: an indeterminate spinner that resolves into a
/// drawn-on checkmark once the request succeeds, rather than the two
/// states simply swapping. Self-contained (owns its own tickers) and
/// entirely decorative — it has no bearing on [SosButtonPhase] itself,
/// which the caller still drives independent of whatever this widget is
/// animating.
///
/// Reconciled across the sending→sent transition by ordinary widget
/// identity: both [_ButtonLabel] cases place this at the same position in
/// an otherwise structurally identical `Column`, so Flutter preserves this
/// widget's `State` (and therefore lets [didUpdateWidget] observe the
/// phase change) rather than tearing it down and rebuilding fresh.
class _SendingToSentIndicator extends StatefulWidget {
  final SosButtonPhase phase;

  const _SendingToSentIndicator({required this.phase});

  @override
  State<_SendingToSentIndicator> createState() =>
      _SendingToSentIndicatorState();
}

class _SendingToSentIndicatorState extends State<_SendingToSentIndicator>
    with TickerProviderStateMixin {
  /// Continuous spin while sending. Turned off outright under reduced
  /// motion ([_syncSpin]) rather than left running at some scaled-down
  /// rate — a `repeat()`'d controller isn't affected by the accessibility
  /// time-scale the way a one-shot `forward()` can be, so this has to be
  /// gated explicitly.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Fades the spinner out and draws the checkmark on. Runs once, forward
  /// only, the instant `sending` gives way to `sent`.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    if (widget.phase != SosButtonPhase.sending) {
      // Constructed already past sending (e.g. this screen was opened
      // after the SOS had already been confirmed elsewhere) — settle
      // straight into the checkmark, no morph to play.
      _morph.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(_SendingToSentIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != SosButtonPhase.sending &&
        oldWidget.phase == SosButtonPhase.sending) {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      _morph.duration = reduceMotion
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 520);
      _morph.forward(from: 0);
    }
    _syncSpin();
  }

  void _syncSpin() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shouldSpin = widget.phase == SosButtonPhase.sending && !reduceMotion;
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _morph]),
        builder: (context, _) {
          return CustomPaint(
            painter: _SendingToSentPainter(
              spinValue: _spin.value,
              morphValue: _morph.value,
            ),
          );
        },
      ),
    );
  }
}

class _SendingToSentPainter extends CustomPainter {
  final double spinValue;
  final double morphValue;

  _SendingToSentPainter({required this.spinValue, required this.morphValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 2;

    // The spinner fades out over the morph's first 40%...
    final spinnerOpacity = 1.0 - (morphValue / 0.4).clamp(0.0, 1.0);
    if (spinnerOpacity > 0.01) {
      const sweep = 1.6 * math.pi; // ~290°, a conventional indeterminate arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        spinValue * 2 * math.pi,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: spinnerOpacity),
      );
    }

    // ...while the checkmark draws on over the morph's last 70%, so the
    // two overlap briefly rather than there being a dead gap between them.
    final checkT = ((morphValue - 0.3) / 0.7).clamp(0.0, 1.0);
    if (checkT > 0.01) {
      final path = Path()
        ..moveTo(size.width * 0.20, size.height * 0.52)
        ..lineTo(size.width * 0.42, size.height * 0.72)
        ..lineTo(size.width * 0.80, size.height * 0.28);
      final metric = path.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * checkT);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SendingToSentPainter oldDelegate) {
    return oldDelegate.spinValue != spinValue ||
        oldDelegate.morphValue != morphValue;
  }
}
