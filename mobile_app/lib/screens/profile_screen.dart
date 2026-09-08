import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/emergency_contacts_store.dart';
import '../services/incident_status_store.dart';
import '../services/sentri_api_client.dart' show SentriUser;
import '../theme/sentri_colors.dart';
import '../theme/sentri_text.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/sentri_card.dart';
import '../widgets/sentri_status_pill.dart';
import 'emergency_contacts_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'privacy_security_screen.dart';

/// The Profile tab: read-only account identity, a link into the in-memory
/// Emergency Contacts preview, and sign-out. Scoped amendment to Decision
/// 28, which cut Profile from the manual-SOS MVP.
///
/// Account fields come from [AuthProvider.user], populated from the
/// `POST /api/auth/login` response. That response carries `full_name`,
/// `email`, `role`, `status` but not `phone_number`, and this pass adds
/// no separate profile fetch — so only name, email and the account
/// status badge are shown, with no edit affordance (nothing here is
/// saved anywhere). The avatar is an icon placeholder — there is no
/// profile-photo support anywhere in the stack.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _handleSignOut(BuildContext context) {
    // Stop the incident-status poller BEFORE clearing the token, so it can
    // never fire a poll with a token that's about to be dropped.
    // stopTracking() cancels its Timer synchronously; logout() then clears
    // the auth state.
    context.read<IncidentStatusStore>().stopTracking();
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final contactCount = context.watch<EmergencyContactsStore>().contacts.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            SentriSpacing.xl,
            SentriSpacing.xl,
            SentriSpacing.xl,
            floatingNavBarContentInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: SentriSpacing.sm),
              _AccountHeader(user: user),
              const SizedBox(height: SentriSpacing.xl + SentriSpacing.xs),
              _ProfileRow(
                icon: LucideIcons.contact,
                label: 'Emergency Contacts',
                subtitle: contactCount == 0
                    ? 'No contacts added yet'
                    : '$contactCount contact${contactCount == 1 ? '' : 's'} added',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmergencyContactsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: SentriSpacing.md),
              _ProfileRow(
                icon: LucideIcons.bell,
                label: 'Notifications',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: SentriSpacing.md),
              _ProfileRow(
                icon: LucideIcons.lock,
                label: 'Privacy & Security',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacySecurityScreen(),
                  ),
                ),
              ),
              const SizedBox(height: SentriSpacing.md),
              // Deliberately styled the same as every other row — SENTRI's
              // emergency red is reserved for the SOS control, so a red
              // row here would read as the wrong kind of urgent (design
              // doc §8's "don't automatically make every destructive-
              // looking action Crimson Blaze" rule). Behaviour unchanged:
              // signs out immediately, no confirmation.
              _ProfileRow(
                icon: LucideIcons.logOut,
                label: 'Sign Out',
                onTap: () => _handleSignOut(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centred identity block: icon-placeholder avatar, name, email, and the
/// account status badge. No surface card behind it and no edit
/// affordance — read-only, matching the Profile reference design.
class _AccountHeader extends StatelessWidget {
  final SentriUser? user;

  const _AccountHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final fullName = user?.fullName ?? '';
    final email = user?.email ?? '';

    return Column(
      children: [
        const CircleAvatar(
          radius: 40,
          backgroundColor: SentriColors.surfaceMuted,
          child: Icon(
            LucideIcons.user,
            size: 40,
            color: SentriColors.textMuted,
          ),
        ),
        const SizedBox(height: SentriSpacing.lg),
        Text(
          fullName.isEmpty ? 'Signed in' : fullName,
          textAlign: TextAlign.center,
          style: SentriText.h3,
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: SentriSpacing.xs),
          Text(
            email,
            textAlign: TextAlign.center,
            style: SentriText.bodySmall.copyWith(color: SentriColors.textMuted),
          ),
        ],
        const SizedBox(height: SentriSpacing.md),
        _StatusPillForStatus(status: user?.status ?? ''),
      ],
    );
  }
}

/// Account-status pill driven by [SentriUser.status] (the `account_status`
/// enum from `schema.sql`). Only `active` reads as "Verified"; every
/// other state — including an unrecognised one — shows its own literal
/// label and never claims verification.
class _StatusPillForStatus extends StatelessWidget {
  final String status;

  const _StatusPillForStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String label, Color color}) spec = switch (status) {
      'active' => (
        icon: LucideIcons.circleCheck,
        label: 'Verified',
        color: SentriColors.success,
      ),
      'pending_verification' => (
        icon: LucideIcons.hourglass,
        label: 'Pending verification',
        color: SentriColors.caution,
      ),
      'suspended' => (
        icon: LucideIcons.ban,
        label: 'Account suspended',
        color: SentriColors.caution,
      ),
      'deactivated' => (
        icon: LucideIcons.ban,
        label: 'Account deactivated',
        color: SentriColors.caution,
      ),
      _ => (
        icon: LucideIcons.helpCircle,
        label: 'Status unknown',
        color: SentriColors.textMuted,
      ),
    };

    return SentriStatusPill(color: spec.color, label: spec.label, icon: spec.icon);
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SentriCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: SentriColors.textMuted),
          const SizedBox(width: SentriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: SentriText.caption),
                ],
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 20,
            color: SentriColors.textMuted,
          ),
        ],
      ),
    );
  }
}
