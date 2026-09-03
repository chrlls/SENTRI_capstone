import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';
import '../widgets/floating_nav_bar.dart';

/// Deliberately thin placeholder. This is a scoped amendment to Decision
/// 28, which explicitly cut Home/Profile from the manual-SOS MVP — Home's
/// real idle / active-incident design is separate, later scope. This
/// screen exists only so the app shell has a first tab to show; the
/// repeated placeholder tiles are there purely to make the screen scroll
/// so the bottom inset behind the floating bar is verifiable.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('SENTRI')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            floatingNavBarContentInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(
                Icons.verified_outlined,
                size: 48,
                color: SentriColors.success,
              ),
              const SizedBox(height: 16),
              const Text(
                "You're all set",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SentriColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap SOS to open the emergency screen, or press and hold it '
                'to send an SOS right away.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: SentriColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              for (var i = 1; i <= 12; i++) ...[
                _PlaceholderTile(index: i),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  final int index;

  const _PlaceholderTile({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SentriColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 20,
            color: SentriColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Placeholder item $index',
              style: const TextStyle(
                fontSize: 14,
                color: SentriColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
