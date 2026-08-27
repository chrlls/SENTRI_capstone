import { useId, useState } from 'react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ApiError, updateIncidentStatus } from '@/lib/api'
import { nextStatusesFor, notesRequiredFor } from '@/lib/incidentStatus'
import { humanizeEnum } from '@/lib/utils'

/**
 * docs/decisions/27-dispatcher-incident-actions.md's reconciliation
 * addendum: dispatcher_notes is required (not optional) for these three
 * — each button stays disabled until real notes are entered, matching
 * the backend's own 422 rule so a dispatcher never hits that error by
 * surprise. Button color follows the existing red/amber/green-style
 * convention already used for status badges (IncidentList's
 * statusVariant) — purple is reserved for AI-suggestion states only,
 * never a human-confirmed action here.
 */
const ACTION_CONFIG = {
  dispatched: { label: 'Dispatch', pendingLabel: 'Dispatching…', variant: 'default' },
  resolved: { label: 'Resolve', pendingLabel: 'Resolving…', variant: 'secondary' },
  false_alarm: { label: 'False Alarm', pendingLabel: 'Marking…', variant: 'destructive' },
}

function NotesRequiredAction({ status, pending, disabled, onConfirm }) {
  const notesId = useId()
  const [notes, setNotes] = useState('')
  const config = ACTION_CONFIG[status]

  return (
    <div className="flex flex-col gap-2 rounded-md border border-border p-3">
      <Label htmlFor={notesId}>Dispatcher notes (required)</Label>
      <Input
        id={notesId}
        value={notes}
        onChange={(event) => setNotes(event.target.value)}
        disabled={disabled}
      />
      {status === 'dispatched' && (
        <p className="text-xs text-muted-foreground">
          This sends a real dispatch decision and satisfies the human-verification requirement — confirm only once a
          human has reviewed this incident.
        </p>
      )}
      <Button
        size={status === 'dispatched' ? 'default' : 'sm'}
        variant={config.variant}
        className={status === 'dispatched' ? 'w-full' : undefined}
        onClick={() => onConfirm(status, notes)}
        disabled={disabled || notes.trim() === ''}
      >
        {pending ? config.pendingLabel : config.label}
      </Button>
    </div>
  )
}

/**
 * No responder picker — dispatching is a single confirm action with
 * required dispatcher_notes. Every other transition (dispatcher_reviewing,
 * cancelled) is a plain one-click confirm with no notes field. Buttons
 * shown are only the ones nextStatusesFor() says are valid from the
 * incident's current status; the backend Gate/transition table is the
 * real enforcement, this only avoids offering a button the server would
 * reject.
 */
export function IncidentStatusActions({ incident, onUpdated }) {
  const [pendingStatus, setPendingStatus] = useState(null)
  const [error, setError] = useState(null)

  const nextStatuses = nextStatusesFor(incident.status)

  async function handleTransition(status, notes) {
    setError(null)
    setPendingStatus(status)

    try {
      const updated = await updateIncidentStatus(incident.incident_id, status, notes)
      onUpdated(updated)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to reach the server. Check your connection and try again.')
    } finally {
      setPendingStatus(null)
    }
  }

  if (nextStatuses.length === 0) {
    return (
      <section>
        <h3 className="mb-2 text-xs font-medium tracking-wide text-muted-foreground uppercase">Actions</h3>
        <p className="text-sm text-muted-foreground">No further actions — this incident is in a terminal state.</p>
      </section>
    )
  }

  const notesRequiredStatuses = nextStatuses.filter(notesRequiredFor)
  const quickStatuses = nextStatuses.filter((status) => !notesRequiredFor(status))

  return (
    <section className="flex flex-col gap-3">
      <h3 className="text-xs font-medium tracking-wide text-muted-foreground uppercase">Actions</h3>

      {error !== null && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {notesRequiredStatuses.map((status) => (
        <NotesRequiredAction
          key={status}
          status={status}
          pending={pendingStatus === status}
          disabled={pendingStatus !== null}
          onConfirm={handleTransition}
        />
      ))}

      {quickStatuses.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {quickStatuses.map((status) => (
            <Button
              key={status}
              variant="outline"
              size="sm"
              onClick={() => handleTransition(status, null)}
              disabled={pendingStatus !== null}
            >
              {pendingStatus === status ? 'Updating…' : humanizeEnum(status)}
            </Button>
          ))}
        </div>
      )}
    </section>
  )
}
