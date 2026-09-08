import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/incident_status_store.dart'
    show IncidentLifecycle, isTerminalIncidentStatus, parseIncidentLifecycle;
import '../services/sentri_api_client.dart';
import '../theme/sentri_colors.dart';
import '../theme/sentri_text.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/sentri_status_pill.dart';

enum _HistoryFilter { all, active, resolved }

/// One row's worth of `GET /api/incidents` (`API_CONTRACTS.md`) — the
/// lighter list shape, not the full detail response. `barangayName` is
/// already resolved server-side (`ListIncidentsForUser`'s join); this
/// screen never re-derives a place name client-side.
class _HistoryEntry {
  final String incidentId;
  final IncidentLifecycle status;
  final DateTime createdAt;
  final String? barangayName;
  final double? latitude;
  final double? longitude;

  const _HistoryEntry({
    required this.incidentId,
    required this.status,
    required this.createdAt,
    this.barangayName,
    this.latitude,
    this.longitude,
  });

  factory _HistoryEntry.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    return _HistoryEntry(
      incidentId: json['incident_id'] as String? ?? '',
      status: parseIncidentLifecycle(json['status'] as String?),
      createdAt: createdAtRaw != null
          ? (DateTime.tryParse(createdAtRaw) ?? DateTime.now())
          : DateTime.now(),
      barangayName: json['barangay_name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Full, persistent alert history — reads every incident this civilian has
/// ever reported via the real, already-verified `GET /api/incidents`
/// (Decision 21 civilian scoping: the server returns only this reporter's
/// own rows, nothing filtered client-side). Frontend-only: no new backend
/// endpoint, no new table, no new migration.
///
/// Deliberately different from Home's `_RecentActivitySection`, which
/// shows a single in-memory "just sent" indicator that resets on app
/// restart (Decision 28's in-memory-only scope cut) — this fetches real,
/// persisted history instead.
///
/// A reviewed mockup for this screen also proposed a "Safety Update / I'm
/// safe now" row type. Omitted here on purpose: no backend data source
/// exists for it (no `safety_reports` table, no endpoint) per this
/// session's architecture audit — that feature is NOT READY, not just
/// unwired.
class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_HistoryEntry> _entries = const [];
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Please log in again to view your alert history.';
      });
      return;
    }

    try {
      final raw = await auth.apiClient.listIncidents(token: token);
      if (!mounted) return;
      setState(() {
        _entries = raw.map(_HistoryEntry.fromJson).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            "Couldn't load your alert history. Check your connection and try again.";
      });
    }
  }

  /// "Resolved" bundles every terminal outcome (resolved / false_alarm /
  /// cancelled) rather than only `resolved` literally — the mockup this
  /// screen is based on has no separate tab for the other two terminal
  /// values, so "closed" vs "still open" is the two-way split this filter
  /// actually offers.
  List<_HistoryEntry> get _filtered {
    switch (_filter) {
      case _HistoryFilter.all:
        return _entries;
      case _HistoryFilter.active:
        return _entries
            .where((e) => !isTerminalIncidentStatus(e.status))
            .toList();
      case _HistoryFilter.resolved:
        return _entries
            .where((e) => isTerminalIncidentStatus(e.status))
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // No local color/elevation override — inherits the app-wide
      // `appBarTheme` (`theme/sentri_theme.dart`) like every other screen,
      // so it can't silently drift from a future theme change.
      appBar: AppBar(title: const Text('Alert History'), centerTitle: true),
      body: SafeArea(
        child: AnimatedSwitcher(
          // Purpose: prevents the jarring instant swap from spinner to
          // content/error that every other loading state in this app still
          // has — the one place in this migration that adds motion for a
          // stated reason, not decoration. Collapses to instant under the
          // OS reduced-motion setting, same as `AnimationController`-based
          // motion elsewhere in this app — implicit animations don't get
          // that for free, so it's checked explicitly.
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return ListView(
        key: const ValueKey('error'),
        padding: const EdgeInsets.all(SentriSpacing.xl),
        children: [
          const SizedBox(height: 80),
          const Icon(
            LucideIcons.circleAlert,
            size: 32,
            color: SentriColors.textMuted,
          ),
          const SizedBox(height: SentriSpacing.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: SentriText.bodySmall.copyWith(color: SentriColors.textMuted),
          ),
          const SizedBox(height: SentriSpacing.lg),
          Center(
            child: TextButton(onPressed: _load, child: const Text('Try again')),
          ),
        ],
      );
    }

    final filtered = _filtered;

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _FilterTabs(
              selected: _filter,
              onSelect: (f) => setState(() => _filter = f),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    // Keeps pull-to-refresh working even when the list has
                    // nothing to show yet.
                    padding: const EdgeInsets.all(SentriSpacing.xl),
                    children: const [SizedBox(height: 60), _EmptyHistoryState()],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: filtered.length,
                    // Inherits the app-wide `dividerTheme` (1px, the
                    // shared border color) — no local override needed.
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) =>
                        _HistoryRow(entry: filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  final _HistoryFilter selected;
  final ValueChanged<_HistoryFilter> onSelect;

  const _FilterTabs({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SentriColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SentriRadius.sm),
      ),
      child: Row(
        children: [
          _tab(_HistoryFilter.all, 'All'),
          _tab(_HistoryFilter.active, 'Active'),
          _tab(_HistoryFilter.resolved, 'Resolved'),
        ],
      ),
    );
  }

  Widget _tab(_HistoryFilter value, String label) {
    final isSelected = value == selected;
    // A compact, iOS-segmented-control-sized pill (~36px total) rather
    // than the 44px touch-target height used elsewhere in this app —
    // deliberate here: each tab spans a third of the screen width, an
    // adjacent mis-tap just shows a different, equally-safe filtered
    // view (nothing destructive), so trading a few px of height for a
    // visibly lighter control is the right call for this specific
    // control, unlike the safety-critical SOS button.
    //
    // This is a selection state, not an emergency action, so the
    // selected fill is the app's non-emergency accent (Cosmos Blue), not
    // Crimson Blaze — `InkWell`, not a bare `GestureDetector`, so it
    // gives the same press feedback every other tappable row in the app
    // does.
    return Expanded(
      child: Material(
        color: isSelected ? SentriColors.info : Colors.transparent,
        borderRadius: BorderRadius.circular(SentriRadius.sm),
        child: InkWell(
          onTap: () => onSelect(value),
          borderRadius: BorderRadius.circular(SentriRadius.sm),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            child: Text(
              label,
              style: SentriText.label.copyWith(
                color: isSelected ? Colors.white : SentriColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each status renders its own color *and* its own text label — the label
/// carries the meaning; color is reinforcement, never the only signal
/// (`false_alarm` and `cancelled` are deliberately never colored the same
/// as `resolved` — they're different real-world outcomes, not decorative
/// variety).
class _HistoryRow extends StatelessWidget {
  final _HistoryEntry entry;

  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final location = entry.barangayName ??
        (entry.latitude != null && entry.longitude != null
            ? '${entry.latitude!.toStringAsFixed(4)}, ${entry.longitude!.toStringAsFixed(4)}'
            : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS Alert',
                  style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(_formatAlertTimestamp(entry.createdAt), style: SentriText.caption),
                if (location != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.mapPin,
                        size: 13,
                        color: SentriColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location,
                          overflow: TextOverflow.ellipsis,
                          style: SentriText.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: SentriSpacing.md),
          _StatusPillForLifecycle(status: entry.status),
        ],
      ),
    );
  }
}

class _StatusPillForLifecycle extends StatelessWidget {
  final IncidentLifecycle status;

  const _StatusPillForLifecycle({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color accent;
    final String label;
    switch (status) {
      case IncidentLifecycle.resolved:
        accent = SentriColors.success;
        label = 'Resolved';
      case IncidentLifecycle.falseAlarm:
        accent = SentriColors.caution;
        label = 'False Alarm';
      case IncidentLifecycle.cancelled:
        accent = SentriColors.textMuted;
        label = 'Cancelled';
      // detected / dashboard_alerted / dispatcher_reviewing / dispatched /
      // unknown — every non-terminal (or unrecognised) value reads as
      // "Active," matching this screen's Active/Resolved filter split.
      default:
        accent = SentriColors.info;
        label = 'Active';
    }
    return SentriStatusPill(color: accent, label: label);
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(LucideIcons.clock, size: 32, color: SentriColors.textMuted),
        const SizedBox(height: SentriSpacing.md),
        Text('No alerts yet', style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: SentriSpacing.xs),
        Text(
          'Incidents you report will show up here.',
          textAlign: TextAlign.center,
          style: SentriText.caption,
        ),
      ],
    );
  }
}

const _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// No `intl` dependency in this project — mirrors the manual formatting
/// approach `home_screen.dart`'s `_relativeTime` already uses rather than
/// adding a new package for one screen.
String _formatAlertTimestamp(DateTime time) {
  final local = time.toLocal();
  final month = _monthAbbreviations[local.month - 1];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$month ${local.day}, ${local.year} • $hour12:$minute $period';
}
