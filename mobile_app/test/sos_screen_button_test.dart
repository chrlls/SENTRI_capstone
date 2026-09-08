import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/controllers/sos_controller.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/screens/sos_screen.dart';
import 'package:mobile_app/services/incident_status_store.dart';
import 'package:mobile_app/widgets/hold_to_confirm_sos_button.dart';

/// Exercises the redesigned single-disc SOS button directly on `SosScreen`
/// (as opposed to `sos_reveal_test.dart`, which exercises the hold-gate
/// mechanics against a synthetic harness): does the screen still render at
/// realistic and small phone widths now that the button's box size is
/// computed responsively, and does an early release still leave
/// `SosController` untouched.
Widget _buildSosScreen() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => IncidentStatusStore()),
      ChangeNotifierProxyProvider2<AuthProvider, IncidentStatusStore,
          SosController>(
        create: (context) => SosController(
          context.read<AuthProvider>().apiClient,
          context.read<IncidentStatusStore>(),
        ),
        update: (context, auth, store, previous) =>
            previous ?? SosController(auth.apiClient, store),
      ),
    ],
    child: const MaterialApp(home: SosScreen(backLabel: 'Home')),
  );
}

void main() {
  group('SosScreen single-disc SOS button', () {
    testWidgets(
      'renders a single SOS button (no ring artifacts) on a typical phone width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_buildSosScreen());
        await tester.pump();

        expect(find.byType(HoldToConfirmSosButton), findsOneWidget);
        expect(find.text('SOS'), findsOneWidget);
        expect(find.text('Need help?'), findsOneWidget);
      },
    );

    testWidgets('still renders correctly on a small phone width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildSosScreen());
      await tester.pump();

      expect(find.byType(HoldToConfirmSosButton), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);
    });

    testWidgets(
      'an early release on the button never advances SosController off idle',
      (tester) async {
        await tester.pumpWidget(_buildSosScreen());
        await tester.pump();

        final center = tester.getCenter(find.byType(HoldToConfirmSosButton));
        final gesture = await tester.startGesture(center);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final controller = Provider.of<SosController>(
          tester.element(find.byType(SosScreen)),
          listen: false,
        );
        expect(controller.phase, SosButtonPhase.idle);
      },
    );
  });
}
