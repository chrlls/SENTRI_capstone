import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/sentri_colors.dart';
import '../hold_to_confirm_sos_button.dart' show kSosHoldDuration;
import 'sos_reveal_geometry.dart';
import 'sos_reveal_host.dart';

/// The full-screen decorative layer inserted into the root [Overlay] while
/// a hold is expanding, holding, committing, or dissolving into the
/// Sending screen. Wrapped in [AbsorbPointer] so a second finger can't
/// reach Home/Profile through it — this cannot steal the *in-flight* hold
/// gesture, since Flutter's gesture binding routes a pointer's later events
/// to whatever hit-tested the original pointer-down, not to whatever is on
/// top when a later event arrives.
class SosRevealLayer extends StatelessWidget {
  const SosRevealLayer({super.key, required this.host});

  final SosRevealHostState host;

  @override
  Widget build(BuildContext context) {
    // `Positioned` must be the outermost widget an `OverlayEntry.builder`
    // returns — the Overlay's internal Stack-like RenderObject looks for
    // `StackParentData` on its *immediate* child, so `AbsorbPointer`/
    // `RepaintBoundary` have to nest inside it, not wrap it.
    return Positioned.fill(
      child: AbsorbPointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              host.cover,
              host.pop,
              host.handoff,
              host.holdProgress,
            ]),
            builder: (context, _) {
              final anchor = host.anchor;
              if (anchor == null) {
                return const SizedBox.shrink();
              }
              return CustomPaint(
                size: MediaQuery.sizeOf(context),
                painter: _SosRevealPainter(
                  anchor: anchor,
                  coverValue: host.cover.value,
                  popValue: host.pop.value,
                  handoffValue: host.handoff.value,
                  holdProgress: host.holdProgress.value,
                  reduceMotion: host.reduceMotion,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The disc's fixed fraction of its own radius the "SOS" label sits at —
/// derived from the real button's intrinsic-canvas values (a 54px label on
/// a 110px disc radius, both call sites), so this overlay's label lands at
/// the same relative size as the real button underneath.
const double _kLabelToDiscRadiusRatio = 54.0 / 110.0;

class _SosRevealPainter extends CustomPainter {
  final SosRevealAnchor anchor;
  final double coverValue;
  final double popValue;
  final double handoffValue;
  final double holdProgress;
  final bool reduceMotion;

  _SosRevealPainter({
    required this.anchor,
    required this.coverValue,
    required this.popValue,
    required this.handoffValue,
    required this.holdProgress,
    required this.reduceMotion,
  });

  static final Animatable<double> _popScaleSequence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.94).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.94, end: 1.03).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.03, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    // `radiusT` is pinned to 1 under reduced motion — the takeover is
    // immediate, never a slow-motion growth — while `entryT` still ramps
    // (over a much shorter, explicitly-overridden duration; see the host)
    // so there is at least a soft fade rather than a hard cut, without
    // ever depending on Flutter to auto-scale this controller for us.
    final radiusT = reduceMotion ? 1.0 : Curves.easeOutCubic.transform(coverValue);
    final entryT = reduceMotion ? coverValue : 1.0;
    final handoffT = reduceMotion ? handoffValue : Curves.easeInOut.transform(handoffValue);
    final fade = entryT * (1.0 - handoffT);
    if (fade <= 0.001) {
      return;
    }

    final center = anchor.center;
    final fieldRadius = lerpDoubleClamped(
      anchor.discRadius * 0.92,
      lerpDoubleClamped(anchor.coverRadius, anchor.discRadius * 0.6, handoffT),
      radiusT,
    );

    // 1. The emergency field itself.
    canvas.drawCircle(
      center,
      fieldRadius,
      Paint()
        ..isAntiAlias = true
        ..color = SentriColors.emergencyDeep.withValues(alpha: fade),
    );

    // 2. The white disc, at the real button's fixed on-screen radius (it
    //    does not grow with the field — only its color/content change),
    //    plus the completion "pop" once the hold threshold is reached.
    //    +0.75px kills the antialiasing fringe against the field behind it.
    final popScale = _popScaleSequence.transform(popValue);
    final discRadius = (anchor.discRadius + 0.75) * popScale;
    // Crosses from the idle red disc to the white holding disc over the
    // back half of the expansion, and — because this is a pure function of
    // `radiusT` — reverses through the same states automatically on an
    // early release, with no separate "reverse" branch needed.
    final confirmedT = ((radiusT - 0.7) / 0.3).clamp(0.0, 1.0);
    final discColor = Color.lerp(SentriColors.primaryRed, Colors.white, confirmedT)!;
    final labelColor = Color.lerp(Colors.white, SentriColors.emergencyDeep, confirmedT)!;
    canvas.drawCircle(
      center,
      discRadius,
      Paint()
        ..isAntiAlias = true
        ..color = discColor.withValues(alpha: fade),
    );

    // 3. The progress track + arc, inside the disc edge (outside it would
    //    sit on top of the same-color field and be invisible).
    final strokeWidth = discRadius * 0.11;
    final ringRadius = discRadius - strokeWidth / 2 - discRadius * 0.06;
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = labelColor.withValues(alpha: 0.16 * fade * confirmedT),
    );
    if (holdProgress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        2 * math.pi * holdProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = labelColor.withValues(alpha: fade * confirmedT),
      );
    }

    // 4. "SOS" label — same intrinsic size ratio the real button uses.
    final labelOpacity = fade * confirmedT;
    if (labelOpacity > 0.01) {
      _paintCenteredText(
        canvas,
        text: 'SOS',
        center: center,
        color: labelColor.withValues(alpha: labelOpacity),
        fontSize: anchor.discRadius * _kLabelToDiscRadiusRatio,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      );
    }

    // 5. Countdown, fading in with the field and placed on whichever side
    //    of the disc has room — above it when the disc sits low on screen
    //    (the nav-bar anchor), below it otherwise (the SosScreen anchor).
    final textOpacity = fade * radiusT;
    if (textOpacity > 0.01) {
      final remainingMs =
          (kSosHoldDuration.inMilliseconds * (1.0 - holdProgress)).clamp(
        0,
        kSosHoldDuration.inMilliseconds,
      );
      final remainingSeconds = (remainingMs / 1000).toStringAsFixed(1);
      final anchorInLowerScreen = center.dy > size.height * 0.6;
      final textCenterY = anchorInLowerScreen
          ? center.dy - (discRadius + 56)
          : center.dy + discRadius + 56;

      _paintCenteredText(
        canvas,
        text: 'Keep holding… ${remainingSeconds}s',
        center: Offset(center.dx, textCenterY),
        color: SentriColors.highlight.withValues(alpha: textOpacity),
        fontSize: 17,
        fontWeight: FontWeight.w600,
      );
      _paintCenteredText(
        canvas,
        text: 'Release to cancel',
        center: Offset(center.dx, textCenterY + 24),
        color: Colors.white.withValues(alpha: textOpacity * 0.75),
        fontSize: 13,
        fontWeight: FontWeight.w400,
      );
    }
  }

  void _paintCenteredText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SosRevealPainter oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.coverValue != coverValue ||
        oldDelegate.popValue != popValue ||
        oldDelegate.handoffValue != handoffValue ||
        oldDelegate.holdProgress != holdProgress ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

double lerpDoubleClamped(double a, double b, double t) =>
    a + (b - a) * t.clamp(0.0, 1.0);
