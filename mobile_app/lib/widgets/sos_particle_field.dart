import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';

/// One emitted particle. Fixed, precomputed identity (angle/size/opacity/
/// stagger) — its *position* at any moment is derived live from the
/// emission clock, never stored.
class SosParticle {
  final double edgeAngle;
  final double size;
  final double opacityCeiling;

  /// This particle's fixed 0..1 offset in the looping emission cycle. Does
  /// double duty: it staggers the continuous stream so particles don't
  /// pulse out in a clump, and it is the gate threshold for the hold ramp
  /// — a particle only emits once `emissionIntensity >= phaseOffset`, so a
  /// rising intensity brings more particles into the stream.
  final double phaseOffset;

  const SosParticle({
    required this.edgeAngle,
    required this.size,
    required this.opacityCeiling,
    required this.phaseOffset,
  });
}

const sosParticleCount = 18;

/// Interpolates red -> green via the *short* arc of the hue wheel (through
/// orange/yellow, ~120° of travel) rather than the long way through
/// blue/cyan (~240° of travel). This is NOT the same as `HSVColor.lerp`,
/// whose default hue interpolation is a plain linear lerp on the raw 0-360
/// hue values with no wraparound — verified by rendering: for this app's
/// red (hue ~359°) to green (hue ~137°), that plain lerp produces a
/// teal/cyan midpoint (going the long way down through blue), not the
/// "warm alert cooling into safe" orange/yellow story this transition
/// needs. Confirmed the fix by re-rendering the ~50% frame, not assumed.
Color lerpWarmToSafeColor(Color from, Color to, double t) {
  final a = HSVColor.fromColor(from);
  final b = HSVColor.fromColor(to);
  final diff = (b.hue - a.hue) % 360.0;
  final delta = (2 * diff) % 360.0 - diff;
  final hue = (a.hue + delta * t) % 360.0;
  return HSVColor.fromAHSV(
    a.alpha + (b.alpha - a.alpha) * t,
    hue,
    a.saturation + (b.saturation - a.saturation) * t,
    a.value + (b.value - a.value) * t,
  ).toColor();
}

/// Generated once (fixed seed) and reused for the lifetime of the button —
/// never regenerated per frame or per rebuild.
///
/// Random edge angle (not evenly-spaced points) per particle gives the
/// "randomized point on the edge" emission the mechanic calls for. The
/// acceleration of the hold ramp comes from squaring `holdProgress` at the
/// call site, not from the particle distribution.
List<SosParticle> generateSosParticles({int seed = 11}) {
  final random = Random(seed);
  return List.generate(sosParticleCount, (_) {
    return SosParticle(
      edgeAngle: random.nextDouble() * 2 * pi,
      size: 3.0 + random.nextDouble() * 5.0,
      opacityCeiling: 0.28 + random.nextDouble() * 0.35,
      phaseOffset: random.nextDouble(),
    );
  });
}

/// Paints the emission-based particle field that IS the button's progress
/// indicator — there is no ring/arc alongside it.
///
/// **One behaviour across hold, sending and sent.** Every particle is born
/// at the disc edge, travels out (`easeOut`) to `maxTravel`, fades on a
/// single hump, then loops — its life position is
/// `(emissionClock + phaseOffset) % 1`. The only thing that changes by
/// phase is [emissionIntensity] (0..1): a particle streams only while
/// `emissionIntensity >= phaseOffset`, so the field *fills* as intensity
/// rises (that is the hold's progress read), and its opacity is also
/// scaled a little by intensity so it *intensifies* too.
///
/// Because the caller pins `emissionIntensity == 1` from the moment the
/// hold completes and never stops [emissionClock], hold → sending is
/// seamless — the stream just keeps flowing, no crossfade needed.
///
/// Under reduced motion the caller passes `emissionClock == 0`, so
/// `p == phaseOffset` and every particle holds a static position; they
/// still appear one by one as `emissionIntensity` crosses each
/// `phaseOffset`, so progress stays legible without any travel.
class SosParticleFieldPainter extends CustomPainter {
  final List<SosParticle> particles;

  /// Continuous looping 0..1 emission clock (frozen at 0 under reduced
  /// motion).
  final double emissionClock;

  /// 0..1 — how much of the field is emitting: `holdProgress²` during the
  /// hold, `1.0` while sending/sent, `0` at rest.
  final double emissionIntensity;

  final double confirmProgress; // 0 = red, 1 = green (HSV-lerped)
  final double discRadius;
  final double maxTravel;
  final bool reduceMotion;

  SosParticleFieldPainter({
    required this.particles,
    required this.emissionClock,
    required this.emissionIntensity,
    required this.confirmProgress,
    required this.discRadius,
    required this.reduceMotion,
    this.maxTravel = 70.0,
  });

  Color get _particleColor {
    if (confirmProgress <= 0) {
      return SentriColors.sosAlarm;
    }
    return lerpWarmToSafeColor(SentriColors.sosAlarm, SentriColors.success, confirmProgress);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final color = _particleColor;

    for (final particle in particles) {
      // Gate: this particle has not joined the stream yet. During the hold
      // this is what makes the field fill as `emissionIntensity`
      // (holdProgress²) climbs; sending/sent pin intensity at 1 so every
      // particle is through the gate.
      if (particle.phaseOffset > emissionIntensity) {
        continue;
      }

      // Life position 0..1 along the born-at-edge → travel → fade → loop
      // cycle. `emissionClock` is 0 under reduced motion, so `p` collapses
      // to `phaseOffset` and the particle holds a fixed position.
      final p = (emissionClock + particle.phaseOffset) % 1.0;
      final fadeIn = Curves.easeOut.transform((p / 0.15).clamp(0.0, 1.0));
      final fadeOut = 1.0 - Curves.easeIn.transform(((p - 0.55) / 0.45).clamp(0.0, 1.0));
      final opacity =
          particle.opacityCeiling * fadeIn * fadeOut * (0.55 + 0.45 * emissionIntensity);

      if (opacity <= 0.001) {
        continue;
      }

      final distance = discRadius + maxTravel * Curves.easeOut.transform(p);
      final position = center + Offset(cos(particle.edgeAngle), sin(particle.edgeAngle)) * distance;

      // Sigma at 15% of the particle's own radius — a soft rim without
      // dissolving the circular shape (0.55 blurred particles into
      // shapeless blobs; confirmed by rendering both).
      canvas.drawCircle(
        position,
        particle.size,
        Paint()
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, particle.size * 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SosParticleFieldPainter oldDelegate) {
    return oldDelegate.emissionClock != emissionClock ||
        oldDelegate.emissionIntensity != emissionIntensity ||
        oldDelegate.confirmProgress != confirmProgress ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
