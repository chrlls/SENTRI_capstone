import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sos_reveal_host.dart';

/// Hold-gesture hooks a caller wires into [HoldToConfirmSosButton] to drive
/// the shared emergency reveal. `onHoldComplete` is the caller's own,
/// pre-existing hold-complete handler (the one that actually fires the SOS)
/// — [SosRevealBinding] calls it *before* animating anything, so the
/// decorative layer can never delay or gate the real request.
class SosHoldHooks {
  final VoidCallback onHoldStart;
  final ValueChanged<double> onHoldProgress;
  final VoidCallback onHoldCancel;
  final VoidCallback onHoldComplete;

  const SosHoldHooks({
    required this.onHoldStart,
    required this.onHoldProgress,
    required this.onHoldCancel,
    required this.onHoldComplete,
  });
}

/// The one code path both the nav-bar SOS button and `SosScreen`'s own SOS
/// button use to drive [SosRevealHost]. Owns the anchor [GlobalKey] the
/// reveal measures its origin from, and the [startDelay] that keeps a
/// quick tap from flashing the emergency layer before it's known to be a
/// real hold.
class SosRevealBinding extends StatefulWidget {
  const SosRevealBinding({
    super.key,
    required this.onHoldComplete,
    required this.builder,
    this.startDelay = Duration.zero,
  });

  /// The caller's real hold-complete handler — already responsible for
  /// firing the SOS request (and, for the nav bar, pushing `SosScreen`).
  /// Unchanged by this widget; called first, synchronously, every time.
  final VoidCallback onHoldComplete;

  /// How long a press must run before the reveal is allowed to start.
  /// `Duration.zero` for `SosScreen`'s own button, which has no tap
  /// affordance to protect. The nav bar passes its own tap/hold split
  /// threshold so a quick tap never flashes red.
  final Duration startDelay;

  final Widget Function(
    BuildContext context,
    GlobalKey anchorKey,
    SosHoldHooks hooks,
  ) builder;

  @override
  State<SosRevealBinding> createState() => _SosRevealBindingState();
}

class _SosRevealBindingState extends State<SosRevealBinding> {
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _startTimer;
  bool _revealStarted = false;

  void _handleHoldStart() {
    _startTimer?.cancel();
    _revealStarted = false;
    if (widget.startDelay == Duration.zero) {
      _startReveal();
    } else {
      _startTimer = Timer(widget.startDelay, _startReveal);
    }
  }

  void _startReveal() {
    if (_revealStarted || !mounted) {
      return;
    }
    _revealStarted = true;
    SosRevealHost.maybeOf(
      context,
    )?.beginReveal(anchorContext: context, anchorKey: _anchorKey);
  }

  void _handleHoldProgress(double progress) {
    if (!_revealStarted) {
      return;
    }
    SosRevealHost.maybeOf(context)?.updateHoldProgress(progress);
  }

  void _handleHoldCancel() {
    _startTimer?.cancel();
    final started = _revealStarted;
    _revealStarted = false;
    if (started) {
      SosRevealHost.maybeOf(context)?.cancelReveal();
    }
  }

  void _handleHoldComplete() {
    _startTimer?.cancel();
    final started = _revealStarted;
    _revealStarted = false;
    // Fire the caller's real hold-complete handler first, unconditionally
    // — the decorative layer must never be a precondition for the SOS
    // itself, only a reaction to it.
    widget.onHoldComplete();
    if (started) {
      SosRevealHost.maybeOf(context)?.commit();
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      _anchorKey,
      SosHoldHooks(
        onHoldStart: _handleHoldStart,
        onHoldProgress: _handleHoldProgress,
        onHoldCancel: _handleHoldCancel,
        onHoldComplete: _handleHoldComplete,
      ),
    );
  }
}
