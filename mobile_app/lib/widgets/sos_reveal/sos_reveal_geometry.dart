import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// [HoldToConfirmSosButton]'s intrinsic canvas is a 220px disc centred in a
/// 360px square (220 disc + 140 halo padding either side — see that
/// widget's own `_diameter`/canvas-size constants). Both call sites
/// (`floating_nav_bar.dart`'s 121.09px box, `sos_screen.dart`'s 240px box)
/// scale that same intrinsic square down via `FittedBox`, so the on-screen
/// disc radius is always this fixed fraction of whatever box actually got
/// measured — one formula covers both without either widget having to
/// report its own scale.
const double kSosDiscToCanvasRatio = 220.0 / 360.0;

/// Where the reveal expands from and how far it must travel to fully cover
/// the screen, resolved once at the start of a hold from the *measured*
/// render box behind [key] — never assumed from layout constants, so it is
/// automatically correct for both call sites and for any future one.
class SosRevealAnchor {
  final Offset center;
  final double discRadius;
  final double coverRadius;

  const SosRevealAnchor({
    required this.center,
    required this.discRadius,
    required this.coverRadius,
  });
}

/// Resolves [key]'s current global position/size into a [SosRevealAnchor].
///
/// Returns `null` if the render box isn't available (not yet laid out,
/// detached, or — as in a widget test that never triggers a real layout
/// pass on this subtree — simply never built with one). A `null` result
/// means the decorative reveal is skipped entirely; it must never be
/// treated as a reason to also skip the SOS submission itself, which is
/// owned by the calling screen, not by this geometry helper.
SosRevealAnchor? resolveSosRevealAnchor(GlobalKey key, Size screenSize) {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderBox) {
    return null;
  }
  final box = renderObject;
  if (!box.attached || !box.hasSize) {
    return null;
  }

  final center = box.localToGlobal(box.size.center(Offset.zero));
  if (!center.dx.isFinite || !center.dy.isFinite) {
    return null;
  }

  final discRadius = box.size.shortestSide * kSosDiscToCanvasRatio / 2;

  double distanceTo(double x, double y) => (Offset(x, y) - center).distance;
  final coverRadius = [
    distanceTo(0, 0),
    distanceTo(screenSize.width, 0),
    distanceTo(0, screenSize.height),
    distanceTo(screenSize.width, screenSize.height),
  ].reduce(math.max);

  return SosRevealAnchor(
    center: center,
    discRadius: discRadius,
    // A couple of px of slack so the covering circle's edge is never
    // visible even after antialiasing.
    coverRadius: coverRadius + 2,
  );
}
