import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/emergency_contacts_store.dart';
import '../services/incident_status_store.dart';
import '../services/sentri_api_client.dart' show SentriUser;
import '../theme/sentri_colors.dart';
import '../widgets/floating_nav_bar.dart';
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
            24,
            24,
            24,
            floatingNavBarContentInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _AccountHeader(user: user),
              const SizedBox(height: 28),
              _ProfileRow(
                icon: Icons.contacts_outlined,
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
              const SizedBox(height: 12),
              _ProfileRow(
                icon: Icons.notifications_none,
                label: 'Notifications',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ProfileRow(
                icon: Icons.lock_outline,
                label: 'Privacy & Security',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacySecurityScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ProfileRow(
                icon: Icons.logout,
                label: 'Sign Out',
                labelColor: SentriColors.primaryRed,
                iconColor: SentriColors.primaryRed,
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
            Icons.person_outline,
            size: 40,
            color: SentriColors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          fullName.isEmpty ? 'Signed in' : fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: SentriColors.textPrimary,
          ),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: SentriColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _StatusBadge(status: user?.status ?? ''),
      ],
    );
  }
}

/// Account-status pill driven by [SentriUser.status] (the `account_status`
/// enum from `schema.sql`). Only `active` reads as "Verified"; every
/// other state — including an unrecognised one — shows its own literal
/// label and never claims verification.
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String label, Color color}) spec = switch (status) {
      'active' => (
        icon: Icons.check_circle,
        label: 'Verified',
        color: SentriColors.success,
      ),
      'pending_verification' => (
        icon: Icons.hourglass_bottom,
        label: 'Pending verification',
        color: SentriColors.caution,
      ),
      'suspended' => (
        icon: Icons.block,
        label: 'Account suspended',
        color: SentriColors.caution,
      ),
      'deactivated' => (
        icon: Icons.block,
        label: 'Account deactivated',
        color: SentriColors.caution,
      ),
      _ => (
        icon: Icons.help_outline,
        label: 'Status unknown',
        color: SentriColors.textMuted,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 14, color: spec.color),
          const SizedBox(width: 6),
          Text(
            spec.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: spec.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SentriColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor ?? SentriColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: labelColor ?? SentriColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SentriColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: SentriColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
