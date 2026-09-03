import 'package:flutter/material.dart';

import '../theme/sentri_colors.dart';
import '../widgets/floating_nav_bar.dart';

/// Stub. Scoped amendment to Decision 28 (which cut Home/Profile). No real
/// profile or settings data is wired yet — [AuthProvider] holds only an
/// in-memory token, no user record — so this is intentionally a
/// placeholder until profile scope is picked up properly. The repeated
/// rows exist only to make the screen scroll for the bottom-inset check.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Profile')),
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
              const Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: SentriColors.surfaceMuted,
                  child: Icon(
                    Icons.person_outline,
                    size: 32,
                    color: SentriColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You are signed in',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: SentriColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Profile details and settings are not part of this build yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: SentriColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              for (var i = 1; i <= 10; i++) ...[
                _PlaceholderRow(index: i),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  final int index;

  const _PlaceholderRow({required this.index});

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
            Icons.settings_outlined,
            size: 20,
            color: SentriColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Placeholder setting $index',
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
