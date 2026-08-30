import { humanizeEnum } from '@/lib/utils'

/**
 * Mirrors backend/app/Http/Requests/UpdateIncidentStatusRequest.php's
 * TRANSITIONS table exactly (docs/decisions/27-dispatcher-incident-actions.md).
 * The backend is the real enforcement — this only decides which buttons
 * to render, so a dispatcher never sees a button the server would reject.
 * Keep both tables in sync deliberately if the lifecycle ever changes.
 */
export const STATUS_TRANSITIONS = {
  detected: ['dashboard_alerted', 'dispatcher_reviewing', 'dispatched', 'false_alarm', 'cancelled'],
  dashboard_alerted: ['dispatcher_reviewing', 'dispatched', 'false_alarm', 'cancelled'],
  dispatcher_reviewing: ['dispatched', 'false_alarm', 'cancelled'],
  dispatched: ['resolved', 'false_alarm', 'cancelled'],
  resolved: [],
  false_alarm: [],
  cancelled: [],
}

export function nextStatusesFor(currentStatus) {
  return STATUS_TRANSITIONS[currentStatus] ?? []
}

/**
 * Mirrors UpdateIncidentStatusRequest::NOTES_REQUIRED_STATUSES exactly
 * (docs/decisions/27-dispatcher-incident-actions.md's reconciliation
 * addendum). These three transitions assert something consequential
 * about the real world, so the audit trail always carries a
 * human-readable reason. The backend is the real enforcement; this only
 * decides whether the action button requires notes before it's enabled.
 */
export const NOTES_REQUIRED_STATUSES = ['dispatched', 'resolved', 'false_alarm']

export function notesRequiredFor(status) {
  return NOTES_REQUIRED_STATUSES.includes(status)
}

/**
 * Verification state — a distinct lens on status, framed around Decision
 * 06's actual architecture (dispatch is always a human decision) rather
 * than restating the operational status enum. Persistent-queue redesign:
 * shown alongside (not instead of) the operational status badge, in both
 * the queue rows and the detail panel header.
 */
export function verificationStateFor(status) {
  switch (status) {
    case 'detected':
    case 'dashboard_alerted':
      return 'Unverified'
    case 'dispatcher_reviewing':
      return 'Reviewing'
    case 'dispatched':
    case 'resolved':
      return 'Verified'
    case 'false_alarm':
      return 'Ruled out'
    case 'cancelled':
      return 'Cancelled'
    default:
      return humanizeEnum(status)
  }
}

/** Shared Badge variant per status — was previously duplicated in the now-removed IncidentList.jsx; the detail panel uses it too. */
export function statusBadgeVariant(status) {
  switch (status) {
    case 'detected':
    case 'dashboard_alerted':
      return 'destructive'
    case 'dispatcher_reviewing':
      return 'default'
    case 'dispatched':
      return 'secondary'
    default:
      return 'outline'
  }
}

/**
 * Reserved, exact mapping (dispatcher-console redesign): red for
 * detected/dashboard_alerted ("needs a human decision now" — a
 * deliberate, documented deviation from the locked red/amber/green
 * reserved-for-human-verified-status rule, since these two are system
 * states, not human-verified ones), amber for dispatcher_reviewing, blue
 * for dispatched, a muted neutral for the three terminal states (hidden
 * from the map by default, per the redesign's filter strip — this color
 * only matters if a future "closed" filter renders them). Purple is
 * deliberately absent — reserved exclusively for future AI-suggestion
 * states, never a status color. Shared by IncidentMap's markers and the
 * dispatcher-console redesign's rail/filter-strip status dots so the two
 * never drift into two independently-chosen palettes for the same
 * meaning.
 */
/**
 * Every non-terminal status. Closed incidents (resolved/false_alarm/
 * cancelled) are deliberately excluded from every filter below,
 * including "All" — hidden from the map by default per the
 * dispatcher-console redesign's filter strip, only reachable behind a
 * future "closed" filter that phase didn't build. Exported (persistent-
 * queue architecture) so IncidentQueue.jsx shares this exact definition
 * instead of a second, independently-drifting array.
 */
export const ACTIVE_STATUSES = ['detected', 'dashboard_alerted', 'dispatcher_reviewing', 'dispatched']

/**
 * The subset of ACTIVE_STATUSES nobody has acted on yet — shared by the
 * queue's own sort tier and, as of the premium-finish polish pass, by
 * every place that colors an elapsed/waiting timer. Red on that timer
 * used to run unconditionally regardless of status (even a `dispatched`
 * incident's clock stayed red), which read as "everything urgent forever"
 * rather than red meaning something specific — a real color-semantics
 * violation the pass explicitly gates on ("do not make every important
 * thing red"). Now the timer is only urgent-red while nobody has picked
 * this incident up yet; once it's being reviewed or already dispatched,
 * the same number renders neutral — it's still informative, just no
 * longer an alarm.
 */
export const NEEDS_REVIEW_STATUSES = ['detected', 'dashboard_alerted']

export function needsReview(status) {
  return NEEDS_REVIEW_STATUSES.includes(status)
}

export const INCIDENT_FILTERS = [
  { key: 'all', label: 'All', match: (status) => ACTIVE_STATUSES.includes(status) },
  {
    key: 'needs_review',
    label: 'Needs review',
    match: (status) => status === 'detected' || status === 'dashboard_alerted',
  },
  { key: 'dispatched', label: 'Dispatched', match: (status) => status === 'dispatched' },
  { key: 'in_review', label: 'In review', match: (status) => status === 'dispatcher_reviewing' },
]

/** Used by both IncidentFilterStrip (counts) and the queue page (which markers the map renders). */
export function filterIncidentsByKey(incidents, filterKey) {
  const filter = INCIDENT_FILTERS.find((candidate) => candidate.key === filterKey) ?? INCIDENT_FILTERS[0]
  return incidents.filter((incident) => filter.match(incident.status))
}

// KNOWN OPEN ITEM: red for detected/dashboard_alerted below is a deliberate
// deviation from the locked red/amber/green-reserved-for-human-verified-
// status rule (they're system states, not human-verified) — flagged in the
// Phase 3 report, not yet written up as a docs/decisions/ addendum. Not an
// oversight; don't "fix" this without that decision existing first.
export const STATUS_COLORS = {
  detected: '#c15353',
  dashboard_alerted: '#c15353',
  dispatcher_reviewing: '#d6a24c',
  dispatched: '#4c8df5',
  resolved: '#4caf7d',
  false_alarm: '#565f70',
  cancelled: '#565f70',
}
