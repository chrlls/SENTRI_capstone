import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/widgets/hold_to_confirm_sos_button.dart';
import 'package:mobile_app/widgets/sos_reveal/sos_reveal_binding.dart';
import 'package:mobile_app/widgets/sos_reveal/sos_reveal_geometry.dart';
import 'package:mobile_app/widgets/sos_reveal/sos_reveal_host.dart';
import 'package:mobile_app/widgets/sos_reveal/sos_reveal_layer.dart';

/// A short hold threshold so these tests don't have to burn multiple real
/// seconds — the gate is a real `Stopwatch`, so the test genuinely has to
/// wait this long in wall-clock time regardless of `tester.pump`'s virtual
/// frame clock (see `HoldToConfirmSosButton`'s own doc comment on why).
/// `tester.runAsync` is what makes that real wait possible at all: a bare
/// `await Future.delayed(...)` inside a normal `testWidgets` body never
/// fires, because that body runs in `flutter_test`'s fake-timer zone.
const _holdDuration = Duration(milliseconds: 120);

Widget _buildHarness({
  required VoidCallback onHoldComplete,
  bool withHost = true,
}) {
  final content = Scaffold(
    body: Center(
      child: SosRevealBinding(
        onHoldComplete: onHoldComplete,
        builder: (context, anchorKey, hooks) => SizedBox(
          key: anchorKey,
          width: 200,
          height: 200,
          child: HoldToConfirmSosButton(
            phase: SosButtonPhase.idle,
            holdDuration: _holdDuration,
            onHoldStart: hooks.onHoldStart,
            onHoldProgress: hooks.onHoldProgress,
            onHoldCancel: hooks.onHoldCancel,
            onHoldComplete: hooks.onHoldComplete,
          ),
        ),
      ),
    ),
  );

  if (!withHost) {
    return MaterialApp(home: content);
  }
  return MaterialApp(
    builder: (context, child) => SosRevealHost(child: child!),
    home: content,
  );
}

void main() {
  group('SosRevealBinding + SosRevealHost', () {
    testWidgets(
      'an early release never calls onHoldComplete and removes the overlay',
      (tester) async {
        var completeCalls = 0;
        await tester.pumpWidget(
          _buildHarness(onHoldComplete: () => completeCalls++),
        );

        final center = tester.getCenter(find.byType(HoldToConfirmSosButton));
        final gesture = await tester.startGesture(center);
        await tester.pump();

        // The reveal layer should be up while the hold is in progress.
        expect(find.byType(SosRevealLayer), findsOneWidget);

        // Release well before the (already short) threshold.
        await tester.runAsync(
          () => Future<void>.delayed(_holdDuration ~/ 4),
        );
        await gesture.up();
        await tester.pump();

        expect(
          completeCalls,
          0,
          reason: 'an early release must never fire the SOS callback',
        );

        // Let the reverse animation (and its force-reset) finish.
        await tester.pumpAndSettle();
        expect(
          find.byType(SosRevealLayer),
          findsNothing,
          reason: 'the overlay must not be left covering the app',
        );
      },
    );

    testWidgets(
      'a full hold calls onHoldComplete exactly once and the overlay clears '
      'itself after the handoff',
      (tester) async {
        var completeCalls = 0;
        await tester.pumpWidget(
          _buildHarness(onHoldComplete: () => completeCalls++),
        );

        final center = tester.getCenter(find.byType(HoldToConfirmSosButton));
        final gesture = await tester.startGesture(center);
        await tester.pump();

        // Real wall-clock wait past the (real Stopwatch-gated) threshold.
        await tester.runAsync(() => Future<void>.delayed(_holdDuration * 2));
        await tester.pump();

        expect(
          completeCalls,
          1,
          reason:
              'the caller\'s real hold-complete handler must fire exactly '
              'once, before any decorative animation is even considered',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          find.byType(SosRevealLayer),
          findsNothing,
          reason: 'the overlay must remove itself once the handoff finishes',
        );
      },
    );

    testWidgets(
      'with no SosRevealHost in the tree, a full hold still fires the SOS '
      'callback exactly once',
      (tester) async {
        var completeCalls = 0;
        await tester.pumpWidget(
          _buildHarness(onHoldComplete: () => completeCalls++, withHost: false),
        );

        final center = tester.getCenter(find.byType(HoldToConfirmSosButton));
        final gesture = await tester.startGesture(center);
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(_holdDuration * 2));
        await tester.pump();

        expect(
          completeCalls,
          1,
          reason:
              'the decorative reveal must never be a precondition for the '
              'real SOS request',
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  });

  group('resolveSosRevealAnchor', () {
    testWidgets('returns null for a key with no attached render object', (
      tester,
    ) async {
      final orphanKey = GlobalKey();
      expect(
        resolveSosRevealAnchor(orphanKey, const Size(400, 800)),
        isNull,
      );
    });
  });
}
