import 'dart:async';

import 'package:flutter/material.dart';

import 'sos_reveal_geometry.dart';
import 'sos_reveal_layer.dart';

/// Where the decorative emergency-takeover layer is in its lifecycle. This
/// never gates the SOS submission itself — see [SosRevealHostState]'s class
/// doc — it only decides what the overlay currently looks like.
enum SosRevealStage { idle, expanding, holding, committing, handoff, reversing }

/// Installed once, above the [Navigator], via `MaterialApp.builder`. Because
/// it lives above routing rather than inside any one screen's [State], the
/// reveal it drives can never be orphaned by a route push/pop mid-hold.
///
/// **This widget is purely decorative.** It does not call
/// [SosController.fireManualSos] and must not: [beginReveal] legitimately
/// no-ops when the held button's `RenderBox` isn't resolvable (not yet laid
/// out, detached, or — as in a widget test — simply not part of a real
/// layout pass), and if the SOS call lived here, that no-op would silently
/// swallow a real emergency request. `AppShell`/`SosScreen` keep owning the
/// call exactly as they did before this feature existed; this host only
/// starts/stops the animation around it.
class SosRevealHost extends StatefulWidget {
  const SosRevealHost({super.key, required this.child});

  final Widget child;

  static SosRevealHostState of(BuildContext context) {
    final state = context.findRootAncestorStateOfType<SosRevealHostState>();
    assert(
      state != null,
      'No SosRevealHost ancestor found — wrap MaterialApp.builder with one.',
    );
    return state!;
  }

  static SosRevealHostState? maybeOf(BuildContext context) =>
      context.findRootAncestorStateOfType<SosRevealHostState>();

  @override
  State<SosRevealHost> createState() => SosRevealHostState();
}

class SosRevealHostState extends State<SosRevealHost>
    with TickerProviderStateMixin {
  /// Radial expand (idle→holding) / contract (an early release reversing
  /// back to idle). One-shot, deliberately *not* tied to the real hold
  /// progress — see the plan doc for why: coverage must be a stable,
  /// already-complete state by the time Holding is legible, not something
  /// that only finishes at the exact instant of commit.
  late final AnimationController cover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 280),
  );

  /// The completion "pop" on the disc once the hold threshold is reached:
  /// 100% → ~94% → ~103% → 100%.
  late final AnimationController pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  /// Dissolves the whole layer once `SosScreen` is ready underneath it.
  late final AnimationController handoff = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );

  /// Mirrors the real (Stopwatch-derived) hold fraction reported by
  /// [HoldToConfirmSosButton.onHoldProgress], so the layer's progress ring
  /// and countdown read the same real elapsed-time value the button itself
  /// gates on — never a value derived from [cover].
  final ValueNotifier<double> holdProgress = ValueNotifier(0);

  SosRevealStage _stage = SosRevealStage.idle;
  SosRevealStage get stage => _stage;
  bool get isActive => _stage != SosRevealStage.idle;

  OverlayEntry? _entry;
  SosRevealAnchor? anchor;
  bool reduceMotion = false;
  Timer? _watchdog;

  /// Begins the reveal anchored on whichever button was held. No-ops if a
  /// reveal is already active, or if the button's on-screen position can't
  /// be resolved right now — in the latter case the hold gate and the SOS
  /// call proceed exactly as if this widget didn't exist.
  void beginReveal({
    required BuildContext anchorContext,
    required GlobalKey anchorKey,
  }) {
    if (isActive) {
      return;
    }
    final media = MediaQuery.of(anchorContext);
    final resolvedAnchor = resolveSosRevealAnchor(anchorKey, media.size);
    if (resolvedAnchor == null) {
      return;
    }

    anchor = resolvedAnchor;
    reduceMotion = media.disableAnimations;

    final overlay = Overlay.of(anchorContext, rootOverlay: true);
    holdProgress.value = 0;
    _stage = SosRevealStage.expanding;
    _entry = OverlayEntry(builder: (_) => SosRevealLayer(host: this));
    overlay.insert(_entry!);

    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 8), _forceReset);

    cover.duration = reduceMotion
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 420);
    cover.forward(from: 0).whenCompleteOrCancel(() {
      if (_stage == SosRevealStage.expanding) {
        _stage = SosRevealStage.holding;
      }
    });
  }

  /// Mirrors the button's live hold fraction. Guarded to only apply while
  /// a reveal is actually expanding/holding: [HoldToConfirmSosButton]'s
  /// `didUpdateWidget` fires `onHoldProgress(0)` on *any* phase→idle
  /// transition — including a failed send observed while this layer is
  /// already mid-handoff — and that stray zero must not tear the layer
  /// down out from under an in-progress dissolve.
  void updateHoldProgress(double p) {
    if (_stage != SosRevealStage.expanding && _stage != SosRevealStage.holding) {
      return;
    }
    if (p <= 0.0) {
      cancelReveal();
      return;
    }
    holdProgress.value = p;
  }

  /// An early release: reverse the expansion and settle back to idle. Same
  /// stage guard as [updateHoldProgress], for the same reason.
  void cancelReveal() {
    if (_stage != SosRevealStage.expanding && _stage != SosRevealStage.holding) {
      return;
    }
    _stage = SosRevealStage.reversing;
    holdProgress.value = 0;
    cover.reverseDuration = reduceMotion
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 280);
    cover.reverse().whenCompleteOrCancel(() {
      if (_stage == SosRevealStage.reversing) {
        _forceReset();
      }
    });
  }

  /// The hold threshold was reached. Purely decorative from here — the
  /// caller has already fired (or is about to fire) the real SOS request
  /// and pushed `SosScreen` before calling this. No-ops under the same
  /// stage guard so a stray or repeated call can never double-animate.
  void commit() {
    if (_stage != SosRevealStage.expanding && _stage != SosRevealStage.holding) {
      return;
    }
    _stage = SosRevealStage.committing;
    holdProgress.value = 1.0;
    cover.value = 1.0;

    if (reduceMotion) {
      _stage = SosRevealStage.handoff;
      handoff.duration = const Duration(milliseconds: 120);
      handoff.forward(from: 0).whenCompleteOrCancel(_forceReset);
      return;
    }

    pop.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || _stage != SosRevealStage.committing) {
        return;
      }
      _stage = SosRevealStage.handoff;
      handoff.duration = const Duration(milliseconds: 440);
      handoff.forward(from: 0).whenCompleteOrCancel(_forceReset);
    });
  }

  /// Last-resort guarantee that this layer never gets stuck covering the
  /// app: removes the overlay entry and resets every controller/stage,
  /// regardless of which step it was interrupted at.
  void _forceReset() {
    _watchdog?.cancel();
    _watchdog = null;
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    cover.stop();
    pop.stop();
    handoff.stop();
    cover.value = 0;
    pop.value = 0;
    handoff.value = 0;
    holdProgress.value = 0;
    anchor = null;
    _stage = SosRevealStage.idle;
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _watchdog?.cancel();
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    cover.dispose();
    pop.dispose();
    handoff.dispose();
    holdProgress.dispose();
    super.dispose();
  }
}
