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
