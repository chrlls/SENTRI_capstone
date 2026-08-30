import { useId, useState } from 'react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { ApiError, updateIncidentStatus } from '@/lib/api'
import { nextStatusesFor, notesRequiredFor } from '@/lib/incidentStatus'
import { humanizeEnum } from '@/lib/utils'

/**
 * docs/decisions/27-dispatcher-incident-actions.md's reconciliation
 * addendum: dispatcher_notes is required (not optional) for these three
 * — each button stays disabled until real notes are entered, matching
 * the backend's own 422 rule so a dispatcher never hits that error by
 * surprise. Button color follows the existing red/amber/green-style
 * convention already used for status badges (lib/incidentStatus.js's
 * statusBadgeVariant) — purple is reserved for AI-suggestion states only,
 * never a human-confirmed action here.
 */
const ACTION_CONFIG = {
  dispatched: { label: 'Dispatch', pendingLabel: 'Dispatching…', variant: 'default' },
  resolved: { label: 'Resolve', pendingLabel: 'Resolving…', variant: 'default' },
  false_alarm: { label: 'False Alarm', pendingLabel: 'Marking…', variant: 'destructive' },
}

/**
 * dispatcher-console redesign, Phase 5: which status gets the large
 * primary treatment. `dispatched` is the core action this whole console
 * exists for (Decision 06's human-verification gate) and is primary
 * whenever it's a valid next step; the one status it's never offered
 * alongside is `resolved` (only reachable *from* `dispatched` itself, per
 * the transition table — mutually exclusive, never both candidates at
 * once), which becomes primary there instead — closing out a real
 * dispatch is the "forward progress" action once already dispatched.
 * `dispatcher_reviewing`/`dashboard_alerted` are never primary — they're
 * low-stakes, non-terminal, optional steps (the reconciliation addendum's
 * own language: "no informational value" in even requiring a note for
 * one of them), not the headline decision a dispatcher is making.
 */
function primaryStatusFor(nextStatuses) {
  if (nextStatuses.includes('dispatched')) {
    return 'dispatched'
  }
  if (nextStatuses.includes('resolved')) {
    return 'resolved'
  }
  return null
}

const CONFIRM_COPY = {
  dispatched: {
    title: 'Confirm dispatch',
    description: 'This notifies responders and logs you as the dispatching officer. This can’t be undone.',
  },
  resolved: {
    title: 'Confirm resolution',
    description: 'This closes the incident as resolved. This can’t be undone.',
  },
  false_alarm: {
    title: 'Mark as false alarm',
    description: 'This closes the incident as a false alarm. This can’t be undone.',
  },
  cancelled: {
    title: 'Cancel incident',
    description: 'This cancels the incident. This can’t be undone.',
  },
  dispatcher_reviewing: {
    title: 'Mark as reviewing',
    description: 'Marks this incident as under your review.',
  },
  dashboard_alerted: {
    title: 'Mark as dashboard alerted',
    description: 'Moves this incident back to the dashboard-alerted state.',
  },
}

function confirmCopyFor(status) {
  return CONFIRM_COPY[status] ?? { title: humanizeEnum(status), description: `Move this incident to ${humanizeEnum(status)}.` }
}

/**
 * detail-panel polish pass: one shared note, not one text input per
 * notes-required status. The previous design gave `dispatched` and
 * `false_alarm` their own separate bordered card, each with its own
 * "Dispatcher notes (required)" field — functionally fine, but it read as
 * two independent little forms stacked in the panel rather than one
 * decision. A dispatcher only ever picks one outcome per incident, so one
 * note describing that decision, sitting above both possible outcome
 * buttons, is both the simpler UI and the more accurate model of what's
 * actually happening. The backend is unaffected — this still submits
 * dispatcher_notes exactly as before, just sourced from one field instead
 * of whichever per-button field happened to be filled in.
 */
export function IncidentStatusActions({ incident, onUpdated }) {
  const notesId = useId()
  const [notes, setNotes] = useState('')
  const [pendingStatus, setPendingStatus] = useState(null)
  const [error, setError] = useState(null)
  const [confirming, setConfirming] = useState(null) // { status, notes } | null

  const nextStatuses = nextStatusesFor(incident.status)

  async function handleTransition(status, transitionNotes) {
    setConfirming(null)
    setError(null)
    setPendingStatus(status)

    try {
      const updated = await updateIncidentStatus(incident.incident_id, status, transitionNotes)
      onUpdated(updated)
      setNotes('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to reach the server. Check your connection and try again.')
    } finally {
      setPendingStatus(null)
    }
  }

  if (nextStatuses.length === 0) {
    return (
      <section className="flex flex-col gap-1.5">
        <h3 className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">Decision</h3>
        <p className="text-sm text-muted-foreground">No further actions — this incident is in a terminal state.</p>
      </section>
    )
  }

  const primaryStatus = primaryStatusFor(nextStatuses)
  const notesRequiredStatuses = nextStatuses.filter(notesRequiredFor)
  const quietStatuses = nextStatuses.filter((status) => !notesRequiredFor(status))
  const notesAreNeeded = notesRequiredStatuses.length > 0
  const disabled = pendingStatus !== null

  // Primary first (large), then any other notes-required status (false_alarm,
  // typically) — spatially distinct via size/weight, not via a second
  // bordered card, so the two read as one decision with two possible
  // outcomes rather than two separate forms.
  const orderedNotesStatuses = [
    ...(primaryStatus !== null ? [primaryStatus] : []),
    ...notesRequiredStatuses.filter((status) => status !== primaryStatus),
  ]

  const confirmCopy = confirming !== null ? confirmCopyFor(confirming.status) : null

  return (
    <section className="flex flex-col gap-3">
      <h3 className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">Decision</h3>

      {error !== null && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {notesAreNeeded && (
        <div className="flex flex-col gap-1.5">
          <Label htmlFor={notesId} className="text-xs text-muted-foreground">
            Dispatcher notes (required)
          </Label>
          <Input
            id={notesId}
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            disabled={disabled}
            placeholder="Reason for this decision…"
          />
        </div>
      )}

      <div className="flex flex-col gap-2">
        {orderedNotesStatuses.map((status) => {
          const config = ACTION_CONFIG[status]
          const isPrimary = status === primaryStatus
          return (
            <Button
              key={status}
              size={isPrimary ? 'lg' : 'default'}
              variant={config.variant}
              className="w-full"
              onClick={() => setConfirming({ status, notes })}
              disabled={disabled || notes.trim() === ''}
            >
              {pendingStatus === status ? config.pendingLabel : config.label}
            </Button>
          )
        })}
      </div>

      {quietStatuses.length > 0 && (
        <div className="flex flex-wrap gap-1.5 border-t border-border/60 pt-3">
          {quietStatuses.map((status) => (
            <Button
              key={status}
              variant="outline"
              size="sm"
              onClick={() => setConfirming({ status, notes: null })}
              disabled={disabled}
            >
              {pendingStatus === status ? 'Updating…' : humanizeEnum(status)}
            </Button>
          ))}
        </div>
      )}

      <p className="text-[11px] text-muted-foreground">Human verification required — dispatch is always a human decision.</p>

      <AlertDialog open={confirming !== null} onOpenChange={(open) => !open && setConfirming(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirmCopy?.title}</AlertDialogTitle>
            <AlertDialogDescription>{confirmCopy?.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant={confirming !== null && ACTION_CONFIG[confirming.status] ? ACTION_CONFIG[confirming.status].variant : 'default'}
              onClick={() => confirming !== null && handleTransition(confirming.status, confirming.notes)}
            >
              Confirm
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </section>
  )
}
