import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../controllers/sos_controller.dart';
import '../providers/auth_provider.dart';
import '../services/incident_status_store.dart';
import '../services/location_service.dart';
import '../theme/sentri_colors.dart';
import '../widgets/floating_nav_bar.dart';
import 'alert_history_screen.dart';
import 'notifications_screen.dart';
import 'sos_screen.dart';

/// The Home tab — the resting screen for a civilian who is not currently
/// in an emergency. Scoped amendment to Decision 28, which cut Home from
/// the manual-SOS MVP; this is that deferred real design.
///
/// Every section reflects real app state rather than static copy: the
/// safety-status card reads [IncidentStatusStore] (never claims "no active
/// alerts" while one is actually open), the location card is a real device
/// fix via [acquireCurrentLocation] with the place name reverse-geocoded
/// from those same coordinates via `package:geocoding` (never a hardcoded
/// place name — geocoding failure just omits the place-name line, it never
/// substitutes a guess), and recent activity reads [SosController.sosSentAt]
/// rather than a fake history list the backend doesn't yet provide. Nothing
/// here is decorative filler with no data behind it — see SENTRI_DESIGN
/// _SYSTEM_V1.1.md §1.1, "quiet by default, loud only when something
/// matters."
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loadingLocation = true;
  double? _latitude;
  double? _longitude;
  double? _accuracyMeters;
  DateTime? _locationCapturedAt;
  String? _locationError;

  /// Reverse-geocoded from the same fix, e.g. "Tagum City". Best-effort:
  /// `null` means "unavailable", not "not fetched yet" — the coordinates
  /// alone already satisfy the card, so a geocoding failure never blocks
  /// or errors the card, it just omits this one line.
  String? _cityName;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
      _cityName = null;
    });
    try {
      final position = await acquireCurrentLocation(
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _accuracyMeters = position.accuracy;
        _locationCapturedAt = DateTime.now();
        _loadingLocation = false;
      });
      // Fire-and-forget: the coordinates already satisfy the card, so the
      // place name fills in when it arrives rather than delaying display.
      unawaited(_reverseGeocode(position.latitude, position.longitude));
    } on LocationUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.message;
        _loadingLocation = false;
      });
    } catch (_) {
      // Anything else — a platform channel/plugin failure, not a
      // permission or GPS-fix problem `acquireCurrentLocation` already
      // classifies. Must still be caught: an unhandled exception here
      // would leave the card stuck on "Getting your location…" forever
      // instead of ever reaching a state the user can act on.
      if (!mounted) return;
      setState(() {
        _locationError = "Couldn't get your location right now.";
        _loadingLocation = false;
      });
    }
  }

  /// Best-effort only: a geocoding failure (offline, no result, plugin
  /// issue) must never surface as a location-card error — the coordinates
  /// it's already showing are correct and sufficient on their own. This
  /// never invents a place name; it only ever shows one the device's own
  /// geocoder returned.
  Future<void> _reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(latitude, longitude);
      if (!mounted || placemarks.isEmpty) return;
      final placemark = placemarks.first;
      final city = [
        placemark.locality,
        placemark.subAdministrativeArea,
        placemark.administrativeArea,
      ].firstWhere((candidate) => (candidate ?? '').trim().isNotEmpty, orElse: () => null);
      if (city == null) return;
      setState(() => _cityName = city);
    } catch (_) {
      // No connectivity, no geocoder on this device, no result — the card
      // already reads fine on coordinates alone.
    }
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  void _openSosStatus() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SosScreen(backLabel: 'Home')),
    );
  }

  void _openAlertHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AlertHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final incidentStore = context.watch<IncidentStatusStore>();
    final sos = context.watch<SosController>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            floatingNavBarContentInset(context) + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Sized up further than SENTRI_DESIGN_SYSTEM
                          // _V1.1.md §3.2's `H3` token (18/600) after an
                          // on-device pass found even that too small —
                          // confirmed readable at this size on a physical
                          // phone.
                          '${_greeting()},',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: SentriColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        Text(
                          // Beyond §3.2's `Display` token (32/700, the
                          // doc's largest defined style) for the same
                          // on-device readability reason as above.
                          _firstName(user?.fullName),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: SentriColors.textPrimary,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _NotificationBell(onTap: _openNotifications),
                ],
              ),
              const SizedBox(height: 24),
              _SafetyStatusCard(
                store: incidentStore,
                onViewStatus: _openSosStatus,
              ),
              const SizedBox(height: 12),
              _LocationCard(
                loading: _loadingLocation,
                cityName: _cityName,
                latitude: _latitude,
                longitude: _longitude,
                accuracyMeters: _accuracyMeters,
                capturedAt: _locationCapturedAt,
                error: _locationError,
                onRetry: _loadLocation,
              ),
              if (!incidentStore.hasActiveIncident) ...[
                const SizedBox(height: 32),
                _RecentActivitySection(
                  sosSentAt: sos.sosSentAt,
                  lastStatus: incidentStore.status,
                  onTap: _openSosStatus,
                  onSeeAll: _openAlertHistory,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// First token of a full name ("Juan Dela Cruz" → "Juan"), falling back to
/// a neutral default when no name is on hand yet — mirrors the fallback
/// `ProfileScreen._AccountHeader` already uses for the same field.
String _firstName(String? fullName) {
  final trimmed = fullName?.trim() ?? '';
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Sits beside the greeting in the same [Row] (not a separate row above
/// it) so it aligns with the greeting block instead of floating above it
/// with a gap. No separate "SENTRI" brand mark — the greeting already
/// opens the screen; the app shell/nav bar is the only branding surface
/// Home needs. No unread-count badge — there is no notification inbox
/// anywhere in this app yet (`NotificationsScreen` is preferences toggles,
/// see its own doc comment), so a numeral badge would be inventing data
/// the app doesn't have.
class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;

  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Notification settings',
      icon: const Icon(LucideIcons.bell, color: SentriColors.textPrimary),
    );
  }
}

/// The one status claim Home makes, and the only card allowed to read as
/// "loud" per SENTRI_DESIGN_SYSTEM_V1.1.md §2.4's emergency exception —
/// driven entirely by [IncidentStatusStore], never a static "you're safe"
/// string. `hasActiveIncident` (not the weaker `isTracking`, which can
/// stay true after resolution) decides which of the two real states shows.
class _SafetyStatusCard extends StatelessWidget {
  final IncidentStatusStore store;
  final VoidCallback onViewStatus;

  const _SafetyStatusCard({required this.store, required this.onViewStatus});

  String get _activeLabel => switch (store.status) {
        IncidentLifecycle.detected ||
        IncidentLifecycle.dashboardAlerted =>
          'Waiting for a dispatcher',
        IncidentLifecycle.dispatcherReviewing =>
          'A dispatcher is reviewing your SOS',
        IncidentLifecycle.dispatched => 'Help has been dispatched',
        _ => 'SOS in progress',
      };

  @override
  Widget build(BuildContext context) {
    if (!store.hasActiveIncident) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SentriColors.success.withValues(alpha: 0.06),
          border: Border.all(color: SentriColors.success.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            _StatusIconBadge(
              icon: LucideIcons.shieldCheck,
              color: SentriColors.success,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // A claim about reported incidents nearby, not the
                    // stronger (and unverifiable) claim that the user is
                    // objectively safe.
                    'No nearby incidents',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SentriColors.success,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "We'll notify you if an incident is reported nearby.",
                    style: TextStyle(
                      fontSize: 13,
                      color: SentriColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: SentriColors.caution.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onViewStatus,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SentriColors.caution.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const _StatusIconBadge(
                icon: LucideIcons.shieldAlert,
                color: SentriColors.caution,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SentriColors.caution,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to view the full status of your SOS.',
                      style: TextStyle(
                        fontSize: 13,
                        color: SentriColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 20, color: SentriColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tinted circular icon container both the safety-status card and the
/// location card use — one shared definition so the two match exactly
/// instead of two hand-tuned copies drifting apart.
class _StatusIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StatusIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// A real device fix (via [acquireCurrentLocation]), with [cityName] a
/// best-effort reverse-geocode of that same fix — never a hardcoded place
/// name, and never invented when geocoding fails (the coordinates already
/// satisfy the card on their own; see `_HomeScreenState._reverseGeocode`).
/// One fix per screen visit, not a continuous stream — `HomeScreen`
/// stays mounted for the whole session inside the shell's `IndexedStack`,
/// so a live stream started here would keep the location indicator active
/// in the background even while the Profile tab is showing.
class _LocationCard extends StatelessWidget {
  final bool loading;
  final String? cityName;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final String? error;
  final VoidCallback onRetry;

  const _LocationCard({
    required this.loading,
    required this.cityName,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasFix = !loading && error == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SentriColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          hasFix
              ? const _StatusIconBadge(icon: LucideIcons.mapPin, color: SentriColors.primaryRed)
              : Icon(
                  error != null ? LucideIcons.mapPinOff : LucideIcons.mapPin,
                  color: SentriColors.textMuted,
                  size: 22,
                ),
          const SizedBox(width: 14),
          Expanded(child: _buildContent(context)),
          if (!loading)
            IconButton(
              onPressed: onRetry,
              tooltip: 'Refresh location',
              icon: const Icon(LucideIcons.refreshCw, size: 18, color: SentriColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (loading) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: SentriColors.textMuted),
          ),
          SizedBox(width: 10),
          Text(
            'Getting your location…',
            style: TextStyle(fontSize: 13, color: SentriColors.textMuted),
          ),
        ],
      );
    }

    if (error != null) {
      return Text(
        error!,
        style: const TextStyle(fontSize: 13, color: SentriColors.textMuted, height: 1.35),
      );
    }

    final coordinates = '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your location',
          style: TextStyle(fontSize: 12, color: SentriColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        if (cityName != null) ...[
          // The human-readable place name leads — the reason this card
          // exists — with the exact fix retained underneath, not dropped.
          Text(
            cityName!,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SentriColors.textPrimary),
          ),
          const SizedBox(height: 1),
          Text(
            coordinates,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SentriColors.textMuted),
          ),
        ] else
          // No resolved place name yet (or the device's geocoder failed) —
          // the coordinates alone still fully satisfy the card, so they
          // take the primary line rather than the card showing nothing.
          Text(
            coordinates,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SentriColors.textPrimary),
          ),
        const SizedBox(height: 2),
        Text(
          'Accuracy ±${accuracyMeters!.round()} m · ${_relativeTime(capturedAt!)}',
          style: const TextStyle(fontSize: 12, color: SentriColors.textMuted),
        ),
      ],
    );
  }
}

/// Reads [SosController.sosSentAt] for its one-line preview — an
/// in-memory, session-only signal (Decision 28's scope cut), not a fetch
/// from the real incident-history endpoint. [onSeeAll] opens
/// [AlertHistoryScreen] instead, which reads the persisted list via
/// `GET /api/incidents` and survives an app restart; this section stays a
/// lightweight "just happened" preview, not a duplicate of that screen.
/// Hidden entirely while an incident is still active (`HomeScreen` skips
/// this section then) to avoid repeating the safety card above.
class _RecentActivitySection extends StatelessWidget {
  final DateTime? sosSentAt;
  final IncidentLifecycle lastStatus;
  final VoidCallback onTap;
  final VoidCallback onSeeAll;

  const _RecentActivitySection({
    required this.sosSentAt,
    required this.lastStatus,
    required this.onTap,
    required this.onSeeAll,
  });

  String get _statusLabel => switch (lastStatus) {
        IncidentLifecycle.resolved => 'Resolved',
        IncidentLifecycle.falseAlarm => 'Marked as false alarm',
        IncidentLifecycle.cancelled => 'Cancelled',
        _ => 'Sent',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: SentriColors.textPrimary),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(44, 44),
                foregroundColor: SentriColors.primaryRed,
              ),
              child: const Text(
                'See all',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (sosSentAt == null) const _EmptyActivityState() else _buildActivityRow(),
      ],
    );
  }

  Widget _buildActivityRow() {
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
              const Icon(LucideIcons.fileText, size: 20, color: SentriColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manual SOS',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SentriColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_statusLabel · ${_relativeTime(sosSentAt!)}',
                      style: const TextStyle(fontSize: 12, color: SentriColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 20, color: SentriColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SentriColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(LucideIcons.fileText, size: 28, color: SentriColors.textMuted),
          SizedBox(height: 10),
          Text(
            'No recent alerts',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SentriColors.textPrimary),
          ),
          SizedBox(height: 4),
          Text(
            'Your reported incidents will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: SentriColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
