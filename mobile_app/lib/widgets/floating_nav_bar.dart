import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';
import 'hold_to_confirm_sos_button.dart';

// ── Layout constants ───────────────────────────────────────────────────
// The app has no spacing scale yet (still an open gap). These inline
// literals are grouped and named here rather than scattered as magic
// numbers so a later spacing-token pass can find and replace them in one
// place.
const double _barHeight = 68;
const double _barHorizontalMargin = 28;
const double _barBottomMargin = 14;
const double _barCornerRadius = 34;
const double _barBorderWidth = 1;

/// Visible red disc diameter of the integrated SOS button.
const double _sosDiscDiameter = 74;

/// [HoldToConfirmSosButton]'s intrinsic canvas is `220` disc + `140` halo
/// padding = `360`. To land a `_sosDiscDiameter` disc on screen the
/// FittedBox target is that same ratio.
const double _sosCanvasSize = _sosDiscDiameter * 360 / 220;

/// Thin page-coloured separation ring around the red disc (bound to the
/// scaffold background, never a literal).
const double _sosRingGap = 5;

const double _sosRingRadius = _sosDiscDiameter / 2 + _sosRingGap;

// ── Seating geometry ──────────────────────────────────────────────────
// The SOS disc sits *down inside* the bar rather than hovering over it:
// its centre is below the pill's flat top edge, so most of the disc is
// within the bar's body and only a shallow crown rises above the edge.
// That is what makes the assembly read as one component instead of a
// navbar with a floating action button parked on top.

/// How far the SOS centre sits **below** the pill's flat top edge.
/// Bounded above by `_barHeight - _sosRingRadius` (= 24): any deeper and
/// the separation ring would break through the pill's bottom edge.
const double _sosCenterFromFlatTop = 22;

/// Height of the crown that still rises above the flat top edge, measured
/// to the outside of the separation ring.
const double _sosCrownAboveFlatTop = _sosRingRadius - _sosCenterFromFlatTop;

// ── Socket geometry ───────────────────────────────────────────────────
// Where the flat top edge reaches the disc it sweeps up into the ring on
// a fillet arc. The fillet is tangent to the flat edge at one end and
// tangent to the separation ring at the other, so the edge leaves the
// flat run at zero slope and lands on the circle with a matching tangent
// — no plateau outside the ring, no cusp where they meet, no valley
// between them. The painter solves the arc from these two radii and the
// seat depth rather than approximating it with hand-placed control
// points, which is what left a visible step in the previous version.

/// Radius of that fillet — the only knob for the sweep. Larger carries
/// the edge further up the disc's flank: at this value it hands off 33°
/// around from the top, so the rise wraps the disc's upper-left and
/// upper-right rather than running into its side. Much larger swells the
/// whole top edge into a dome and eats the flat run past the tabs.
const double _socketFilletRadius = 80;

/// How high the fillet lifts the edge above the flat sides before it
/// meets the ring. Solved, not chosen: `F·(R − d) / (R + F)` for the
/// tangency above, so the painter's box always reserves exactly the room
/// the sweep needs.
const double _shoulderHeight = _socketFilletRadius *
    (_sosRingRadius - _sosCenterFromFlatTop) /
    (_sosRingRadius + _socketFilletRadius);

/// Soft-shadow tuning — deliberately light (subtle floating shadow, no
/// heavy shadows, no gradients). Unchanged elevation treatment.
const double _pillShadowBlur = 18;
const Offset _pillShadowOffset = Offset(0, 6);

/// Vertical space the floating bar assembly occupies measured up from the
/// screen's bottom edge — its bottom margin, the pill, and the SOS
/// button's crown above the pill's top edge (the highest point a
/// scrollable screen's last item must clear). Consumers add the device
/// safe-area inset themselves via [floatingNavBarContentInset].
const double kFloatingNavBarReservedSpace =
    _barBottomMargin + _barHeight + _sosCrownAboveFlatTop;

/// Bottom padding a scrollable screen under the app shell should leave so
/// its last item clears the whole floating bar assembly: reserved space +
/// safe-area inset + a little breathing room.
double floatingNavBarContentInset(BuildContext context) =>
    kFloatingNavBarReservedSpace + MediaQuery.of(context).padding.bottom + 12;

/// One floating navigation component with three integrated controls —
/// Home, SOS (centre), Profile. The SOS button is structurally part of the
/// pill: the pill's top edge lifts into a rounded socket that wraps the
/// button. It is not a separate floating action button.
///
/// The SOS disc reuses [HoldToConfirmSosButton] directly — same
/// `Stopwatch` + `Ticker` + `Listener` hold gate (reduced-motion-safe,
/// Decision 31 Open Item A), same `holdDuration` default (2500ms), same
/// milestone haptics and progress fill; only the idle centre label is
/// overridden to "SOS" and the decorative halo is turned off. An outer
/// [Listener] adds the tap-vs-hold split: a short press that never became
/// a hold opens the SOS screen; a completed hold fires an SOS in place.
class FloatingNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final SosButtonPhase sosPhase;

  /// Quick tap on the SOS button → open the full SOS screen.
  final VoidCallback onSosTap;

  /// Press-and-hold past the threshold on the SOS button → fire an SOS
  /// from the current screen, no navigation.
  final VoidCallback onSosHoldComplete;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.sosPhase,
    required this.onSosTap,
    required this.onSosHoldComplete,
  });

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> {
  /// A press shorter than this that never completed a hold counts as a
  /// quick tap. Well under the first hold-milestone haptic (0.3 × 2500ms =
  /// 750ms), so a deliberate tap never registers hold progress.
  static const Duration _tapMaxDuration = Duration(milliseconds: 220);

  DateTime? _sosPressStart;
  bool _sosHoldFired = false;

  void _onSosPointerDown(PointerDownEvent _) {
    _sosPressStart = DateTime.now();
    _sosHoldFired = false;
  }

  void _onSosHoldComplete() {
    _sosHoldFired = true;
    widget.onSosHoldComplete();
  }

  void _onSosPointerUp(PointerEvent _) {
    final start = _sosPressStart;
    _sosPressStart = null;
    if (_sosHoldFired) {
      return; // a full hold completed — already handled
    }
    if (start == null) {
      return;
    }
    if (DateTime.now().difference(start) <= _tapMaxDuration) {
      widget.onSosTap(); // quick tap → open the SOS screen
    }
    // Anything longer that didn't complete: a hold was started and
    // released early. Do nothing — matches the SOS screen's own
    // "release early = nothing sent".
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final pillBottom = safeBottom + _barBottomMargin;
    // Painter box spans the flat bar plus the shoulder rise; its own top
    // is the shoulder-peak level, and the flat side edges sit
    // `_shoulderHeight` down from that.
    final painterHeight = _barHeight + _shoulderHeight;
    // Measured down from the flat top edge, not up from it: the disc is
    // seated inside the bar's body.
    final sosCenterFromBottom =
        pillBottom + _barHeight - _sosCenterFromFlatTop;
    final totalHeight = sosCenterFromBottom + _sosCanvasSize / 2;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── The pill (flat sides + raised centre socket) ─────────
          Positioned(
            left: _barHorizontalMargin,
            right: _barHorizontalMargin,
            bottom: pillBottom,
            height: painterHeight,
            child: CustomPaint(
              painter: _SocketedPillPainter(
                fill: SentriColors.background,
                border: SentriColors.textMuted.withValues(alpha: 0.14),
                borderWidth: _barBorderWidth,
                shadow: SentriColors.textPrimary.withValues(alpha: 0.12),
                shadowBlur: _pillShadowBlur,
                shadowOffset: _pillShadowOffset,
                cornerRadius: _barCornerRadius,
                shoulderHeight: _shoulderHeight,
                filletRadius: _socketFilletRadius,
                ringRadius: _sosRingRadius,
                ringCenterFromFlatTop: _sosCenterFromFlatTop,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: _shoulderHeight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _NavTab(
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home,
                        label: 'Home',
                        selected: widget.currentIndex == 0,
                        onTap: () => widget.onSelect(0),
                      ),
                    ),
                    const SizedBox(width: _sosDiscDiameter + 60),
                    Expanded(
                      child: _NavTab(
                        icon: Icons.person_outline,
                        activeIcon: Icons.person,
                        label: 'Profile',
                        selected: widget.currentIndex == 1,
                        onTap: () => widget.onSelect(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Thin separation ring ─────────────────────────────────
          // A disc of the exact page background colour with its own soft
          // shadow, so the red circle reads as a distinct raised layer of
          // the same component — not a colour halo. Bound to the theme's
          // scaffold background, never a literal white. (Unchanged.)
          Positioned(
            left: 0,
            right: 0,
            bottom: sosCenterFromBottom - _sosRingRadius,
            child: Center(
              child: Container(
                width: _sosRingRadius * 2,
                height: _sosRingRadius * 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SentriColors.textPrimary.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── The SOS control ──────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: sosCenterFromBottom - _sosCanvasSize / 2,
            child: Center(
              child: Semantics(
                button: true,
                label:
                    'SOS. Tap to open the SOS screen, or press and hold to send an SOS now.',
                child: Listener(
                  onPointerDown: _onSosPointerDown,
                  onPointerUp: _onSosPointerUp,
                  onPointerCancel: (_) => _sosPressStart = null,
                  child: SizedBox(
                    width: _sosCanvasSize,
                    height: _sosCanvasSize,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: HoldToConfirmSosButton(
                        phase: widget.sosPhase,
                        idleLabel: 'SOS',
                        idleLabelStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                        showHalo: false,
                        onHoldComplete: _onSosHoldComplete,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? SentriColors.textPrimary : SentriColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_barCornerRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the one-piece floating pill. The side portions of the top edge
/// are flat; where they reach the SOS they sweep up on a fillet arc and
/// run around the seated disc, so the bar's material wraps the button
/// instead of stopping at it. Elevation is a single soft shadow plus a
/// hairline border (unchanged).
class _SocketedPillPainter extends CustomPainter {
  final Color fill;
  final Color border;
  final double borderWidth;
  final Color shadow;
  final double shadowBlur;
  final Offset shadowOffset;
  final double cornerRadius;
  final double shoulderHeight;
  final double filletRadius;
  final double ringRadius;
  final double ringCenterFromFlatTop;

  _SocketedPillPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.shadow,
    required this.shadowBlur,
    required this.shadowOffset,
    required this.cornerRadius,
    required this.shoulderHeight,
    required this.filletRadius,
    required this.ringRadius,
    required this.ringCenterFromFlatTop,
  });

  /// How far the socket's span is pulled inside the ring's outline, so the
  /// separation ring covers the border stroke along that stretch and the
  /// bar shows no hairline arc around the top of the disc.
  static const double _socketTuck = 1;

  Path _flatToppedPath(double w, double h, double topY, double r) =>
      Path()..addRRect(RRect.fromLTRBR(0, topY, w, h, Radius.circular(r)));

  Path _buildPath(Size size) {
    final w = size.width;
    final h = size.height;
    // The flat side edge sits `shoulderHeight` below the box top; the box
    // top line (y = 0) is where the fillet tops out.
    final topY = shoulderHeight;
    final r = math.min(cornerRadius, math.min((h - topY) / 2, w / 2));
    final cx = w / 2;

    final f = filletRadius;
    final ring = ringRadius;
    final depth = ringCenterFromFlatTop;
    final ringCenter = Offset(cx, topY + depth);

    // Fillet circle: tangent to the flat edge from above (centre one
    // radius up from it) and externally tangent to the ring (centres
    // `ring + f` apart). Both conditions fix its horizontal offset.
    final footOffset = math.sqrt(
      math.max(0, (ring + f) * (ring + f) - (depth + f) * (depth + f)),
    );
    // Where the fillet hands off to the ring, on the line joining the two
    // centres — the shared tangent point.
    final rise = f * (ring - depth) / (ring + f);
    final tangentOffset = footOffset * ring / (ring + f);

    // A bar too narrow to fit the sweep falls back to a plain flat edge
    // rather than folding the fillet through the rounded ends.
    if (cx - footOffset <= r) {
      return _flatToppedPath(w, h, topY, r);
    }

    final leftFillet = Rect.fromCircle(
      center: Offset(cx - footOffset, topY - f),
      radius: f,
    );
    final rightFillet = Rect.fromCircle(
      center: Offset(cx + footOffset, topY - f),
      radius: f,
    );
    final socket = Rect.fromCircle(
      center: ringCenter,
      radius: ring - _socketTuck,
    );

    // Angles are Flutter's own convention: 0 along +x, growing towards
    // +y (downwards), so the top of a circle is at -pi/2.
    final leftHandoff = math.atan2(f - rise, footOffset - tangentOffset);
    final socketStart = math.atan2(-(depth + rise), -tangentOffset);
    final socketEnd = math.atan2(-(depth + rise), tangentOffset);
    final rightHandoff = math.atan2(f - rise, tangentOffset - footOffset);

    return Path()
      ..moveTo(r, topY)
      ..lineTo(cx - footOffset, topY)
      // up the left fillet, leaving the flat edge at zero slope
      ..arcTo(leftFillet, math.pi / 2, leftHandoff - math.pi / 2, false)
      // around the seated disc, just inside the ring (hidden behind it)
      ..arcTo(socket, socketStart, socketEnd - socketStart, false)
      // down the right fillet, rejoining the flat edge at zero slope
      ..arcTo(rightFillet, rightHandoff, math.pi / 2 - rightHandoff, false)
      ..lineTo(w - r, topY)
      ..arcToPoint(Offset(w, topY + r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, topY + r)
      ..arcToPoint(Offset(r, topY), radius: Radius.circular(r))
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    // Single soft drop shadow — the whole shape blurred and nudged down.
    canvas.drawPath(
      path.shift(shadowOffset),
      Paint()
        ..color = shadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur / 2),
    );

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _SocketedPillPainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.shadow != shadow ||
      old.shadowBlur != shadowBlur ||
      old.shadowOffset != shadowOffset ||
      old.cornerRadius != cornerRadius ||
      old.shoulderHeight != shoulderHeight ||
      old.filletRadius != filletRadius ||
      old.ringRadius != ringRadius ||
      old.ringCenterFromFlatTop != ringCenterFromFlatTop;
}
