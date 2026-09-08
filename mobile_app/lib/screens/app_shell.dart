import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/sos_controller.dart';
import '../providers/auth_provider.dart';
import '../theme/sentri_colors.dart';
import '../theme/sentri_text.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/hold_to_confirm_sos_button.dart' show SosButtonPhase;
import 'home_screen.dart';
import 'profile_screen.dart';
import 'sos_screen.dart';

/// The persistent post-login shell. Scoped amendment to Decision 28: Home
/// and Profile (cut from the manual-SOS MVP) now exist as deliberately
/// thin screens, and this shell — not `SosScreen` — is what login lands
/// on.
///
/// Owns tab switching between Home and Profile (an [IndexedStack] so tab
/// state is kept) and the floating notched nav bar with its persistent
/// SOS button. `SosScreen` is pushed *on top* of this shell — by a tap, or
/// by a completed hold — so the bar is intentionally not visible while it
/// is open; it is its own focused destination, not a tab.
///
/// Decision 05 / Decision 28 point 5: a held SOS from the nav bar calls
/// straight into [SosController.fireManualSos] — the same call `SosScreen`
/// makes — and nothing is awaited before the hold gesture itself can
/// begin (the gesture lives entirely in [HoldToConfirmSosButton]). The
/// push into `SosScreen` that follows happens behind the (purely
/// decorative) emergency-reveal layer — see `SosRevealHost` — and is not
/// itself part of that safety guarantee.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openSosScreen() {
    final backLabel = _index == 0 ? 'Home' : 'Profile';
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SosScreen(backLabel: backLabel)),
    );
  }

  void _fireSosFromHold() {
    context.read<SosController>().fireManualSos(
          token: context.read<AuthProvider>().token,
        );
    // Push the SOS screen straight away, behind the still-covering
    // emergency reveal (see `SosRevealBinding`/`SosRevealHost`) — by the
    // time that layer dissolves a few hundred ms later, this screen has
    // already run its own initState/GPS-status check and laid out once,
    // so nothing jank-inducing happens at the moment it becomes visible.
    _openSosScreen();
  }

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosController>();
    final shellIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final showHoldError = shellIsCurrent &&
        sos.errorMessage != null &&
        sos.phase == SosButtonPhase.idle;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: const [HomeScreen(), ProfileScreen()],
            ),
          ),
          if (showHoldError)
            Positioned(
              left: 16,
              right: 16,
              bottom: floatingNavBarContentInset(context) + 4,
              child: _SosHoldErrorBanner(
                message: sos.errorMessage!,
                onDismiss: () => context.read<SosController>().clearError(),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              currentIndex: _index,
              onSelect: (i) => setState(() => _index = i),
              sosPhase: sos.phase,
              onSosTap: _openSosScreen,
              onSosHoldComplete: _fireSosFromHold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on Home/Profile when a held-from-the-nav-bar SOS fails and the
/// button has snapped back to idle — so a failure is never silent even
/// though the user never left the current screen. A successful send shows
/// as the button's own `sent` state; a send in progress as its `sending`
/// state.
class _SosHoldErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _SosHoldErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    // This reports a *failed emergency send*, not an ordinary form
    // warning — it takes the emergency/danger color (Crimson Blaze via
    // `colorScheme.error`), not the generic caution amber.
    final errorColor = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: SentriColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SentriRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 20, color: errorColor),
              const SizedBox(width: SentriSpacing.md),
              Expanded(
                child: Text(message, style: SentriText.bodySmall),
              ),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
