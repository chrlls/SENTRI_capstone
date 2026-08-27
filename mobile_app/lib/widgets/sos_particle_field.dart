import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';

/// One emitted particle. Fixed, precomputed identity (angle/size/opacity/
/// spawn point in the hold) — its *position* at any moment is derived live
/// from whatever progress value is driving the field, never stored.
class SosParticle {
  final double edgeAngle;
  final double spawnThreshold;
  final double size;
  final double opacityCeiling;

  const SosParticle({
    required this.edgeAngle,
    required this.spawnThreshold,
    required this.size,
    required this.opacityCeiling,
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
/// `spawnThreshold` is deliberately `pow(i / count, 1.6)`, not evenly spaced:
/// this is what makes spawn *rate* accelerate with hold progress (few
/// particles active early, most/all active by full progress) rather than a
/// steady drip. Random edge angle (not evenly-spaced points) per particle
/// gives the "randomized point on the edge" emission the mechanic calls for.
List<SosParticle> generateSosParticles({int seed = 11}) {
  final random = Random(seed);
  return List.generate(sosParticleCount, (i) {
    final spawnThreshold = pow(i / sosParticleCount, 1.6).toDouble() * 0.85;
    return SosParticle(
      edgeAngle: random.nextDouble() * 2 * pi,
      spawnThreshold: spawnThreshold,
      size: 3.0 + random.nextDouble() * 5.0,
      opacityCeiling: 0.28 + random.nextDouble() * 0.35,
    );
  });
}

/// Paints the emission-based particle field that IS the button's progress
/// indicator — there is no ring/arc alongside it.
///
/// Count and per-particle travel distance are both direct functions of
/// `holdProgress` (0..1). A particle becomes active once
/// `holdProgress >= spawnThreshold`, and its travel fraction is
/// `(holdProgress - spawnThreshold) / (1 - spawnThreshold)` — so it keeps
/// moving outward as progress keeps rising, not just at a fixed rate from
/// when it spawned. `holdProgress` stays pinned at 1.0 through the
/// `sending`/`sent` phases (it only resets to 0 back in `idle`), so the
/// field simply stays fully spread/visible once holding completes — no
/// separate sending-phase behavior of its own.
class SosParticleFieldPainter extends CustomPainter {
  final List<SosParticle> particles;
  final double holdProgress;
  final double confirmProgress; // 0 = red, 1 = green (HSV-lerped)
  final double discRadius;
  final double maxTravel;
  final bool reduceMotion;

  SosParticleFieldPainter({
    required this.particles,
    required this.holdProgress,
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
      if (holdProgress < particle.spawnThreshold) {
        continue; // not spawned yet
      }
      var travelFraction =
          ((holdProgress - particle.spawnThreshold) / (1 - particle.spawnThreshold)).clamp(0.0, 1.0);

      if (reduceMotion) {
        // Discrete steps, not smooth travel — progress still reads via
        // count/size/opacity, just without continuous outward motion.
        const steps = 4;
        travelFraction = (travelFraction * steps).floorToDouble() / steps;
      }

      final opacity = particle.opacityCeiling * Curves.easeOut.transform((travelFraction / 0.3).clamp(0.0, 1.0));

      if (opacity <= 0.001) {
        continue;
      }

      final distance = discRadius + maxTravel * Curves.easeOut.transform(travelFraction);
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
    return oldDelegate.holdProgress != holdProgress ||
        oldDelegate.confirmProgress != confirmProgress ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
