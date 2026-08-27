import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';

/// Visual/interaction phase driven by the parent screen once the hold
/// gesture itself completes — everything before completion (idle, the
/// hold progress itself) is this widget's own internal state, since the
/// parent has no reason to know about in-progress touch state.
enum SosButtonPhase { idle, sending, sent }

const _diameter = 220.0;
const _dotCount = 26;

class _HaloDot {
  final double baseAngle;
  final double angularDrift;
  final double targetRadius;
  final double size;

  const _HaloDot({
    required this.baseAngle,
    required this.angularDrift,
    required this.targetRadius,
    required this.size,
  });
}

/// The reference design's hand-drawn "SOS in a scattered dot halo" is
/// reinterpreted per the project owner's confirmed direction: a precise
/// circle at rest (unambiguous tap target under stress), with the
/// reference's loose/organic energy expressed only through the
/// press-and-hold animation, not baked into the idle shape. Holding for
/// [holdDuration] fires [onHoldComplete]; releasing early reverses the
/// animation and fires nothing.
class HoldToConfirmSosButton extends StatefulWidget {
  final SosButtonPhase phase;
  final VoidCallback onHoldComplete;
  final Duration holdDuration;

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
  late final List<_HaloDot> _dots;

  @override
  void initState() {
    super.initState();

    _holdController = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener(_handleHoldStatusChanged);

    _sentBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Precomputed once, not per frame or per rebuild — a fixed seed keeps
    // the scatter pattern stable across rebuilds within the same press,
    // while still reading as organic/hand-scattered rather than a
    // perfectly even ring of dots.
    final random = Random(7);
    _dots = List.generate(_dotCount, (i) {
      final baseAngle = (2 * pi / _dotCount) * i;
      return _HaloDot(
        baseAngle: baseAngle,
        angularDrift: (random.nextDouble() - 0.5) * 0.6,
        targetRadius: _diameter / 2 + 18 + random.nextDouble() * 46,
        size: 2.5 + random.nextDouble() * 3.5,
      );
    });
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
            return CustomPaint(
              painter: _SosButtonPainter(
                holdProgress: _holdController.value,
                sentBurst: _sentBurstController.value,
                phase: widget.phase,
                dots: _dots,
                showDots: !reduceMotion,
              ),
              child: Center(
                child: SizedBox(
                  width: _diameter,
                  height: _diameter,
                  child: Center(
                    child: _ButtonLabel(phase: widget.phase, holdProgress: _holdController.value),
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

  const _ButtonLabel({required this.phase, required this.holdProgress});

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case SosButtonPhase.sending:
        return const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        );
      case SosButtonPhase.sent:
        return const Text(
          'SOS SENT',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        );
      case SosButtonPhase.idle:
        return Text(
          holdProgress > 0.02 ? 'HOLD…' : 'HOLD TO\nSEND SOS',
          textAlign: TextAlign.center,
          style: const TextStyle(
            // White, not textPrimary: the disc is solid primaryRed in
            // every phase now (idle included), so the label needs to
            // read against red, same as the sending/sent labels below.
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
  final double holdProgress;
  final double sentBurst;
  final SosButtonPhase phase;
  final List<_HaloDot> dots;
  final bool showDots;

  _SosButtonPainter({
    required this.holdProgress,
    required this.sentBurst,
    required this.phase,
    required this.dots,
    required this.showDots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = _diameter / 2;
    final eased = Curves.easeOutCubic.transform(holdProgress);

    // Soft halo behind the disc, always visible (not gated on phase or
    // hold progress) — the reference image's layered soft-glow-around-
    // a-solid-badge look. Drawn before the disc so only the portion
    // outside the disc's radius reads as a visible ring.
    canvas.drawCircle(center, radius + 50, Paint()..color = SentriColors.glowOuter);
    canvas.drawCircle(center, radius + 25, Paint()..color = SentriColors.glowInner);

    // The disc is solid primaryRed in every phase (idle included) per
    // the reference image — state is communicated by the ring/dots, not
    // by the disc itself changing color. Always a precise circle, never
    // distorted, so the tap target stays unambiguous.
    canvas.drawCircle(center, radius, Paint()..color = SentriColors.primaryRed);

    // Progress ring, filling in as the hold nears completion. A solid
    // primaryRed arc alone was tested against white and found to nearly
    // vanish — it's the same hue as both the disc it sits next to and
    // the glow ring underneath it, so "how much has filled in" wasn't
    // legible (confirmed by rendering, not assumed). A neutral gray
    // track underneath the red fill gives the ring real contrast
    // regardless of what's behind it, same convention as a typical
    // circular progress indicator.
    if (phase == SosButtonPhase.idle && holdProgress > 0) {
      final ringRect = Rect.fromCircle(center: center, radius: radius + 14);

      final trackPaint = Paint()
        ..color = const Color(0xFFE3E3E6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      canvas.drawCircle(center, radius + 14, trackPaint);

      final fillPaint = Paint()
        ..color = SentriColors.primaryRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ringRect, -pi / 2, 2 * pi * eased, false, fillPaint);
    }

    if (showDots) {
      _paintHalo(canvas, center, eased);
    }
  }

  void _paintHalo(Canvas canvas, Offset center, double eased) {
    final scatter = phase == SosButtonPhase.sent ? 1.0 + sentBurst * 0.35 : eased;
    if (scatter <= 0.001) {
      return;
    }

    final opacity = phase == SosButtonPhase.sent
        ? (1 - sentBurst * 0.6).clamp(0.0, 1.0)
        : (eased * 0.9).clamp(0.0, 1.0);

    for (final dot in dots) {
      final angle = dot.baseAngle + dot.angularDrift * scatter;
      final dist = (_diameter / 2) + (dot.targetRadius - _diameter / 2) * scatter;
      final position = center + Offset(cos(angle), sin(angle)) * dist;

      canvas.drawCircle(
        position,
        dot.size * ui.clampDouble(0.4 + scatter * 0.6, 0, 1),
        Paint()..color = SentriColors.sosAlarm.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SosButtonPainter oldDelegate) {
    return oldDelegate.holdProgress != holdProgress ||
        oldDelegate.sentBurst != sentBurst ||
        oldDelegate.phase != phase;
  }
}
