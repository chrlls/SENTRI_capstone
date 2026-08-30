import { CircleCheck, Loader2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { formatElapsed, humanizeEnum, parseApiTimestamp } from '@/lib/utils'
import { useElapsedSeconds } from '@/hooks/useElapsedSeconds'
import { ACTIVE_STATUSES, NEEDS_REVIEW_STATUSES, STATUS_COLORS, needsReview, statusBadgeVariant } from '@/lib/incidentStatus'
import { triggerIconElement, triggerSourceLabel } from '@/lib/triggerIcons'
import { cn } from '@/lib/utils'

/**
 * Needs-review tier ranks above every other active status — a dispatcher
 * hasn't looked at these yet. Not a new judgment call: this already
 * matches statusBadgeVariant's own destructive→default→secondary
 * ordering, just made explicit and reusable for sorting.
 */
const tierFor = (status) => (NEEDS_REVIEW_STATUSES.includes(status) ? 0 : 1)

/**
 * Row field order (operational-clarity polish pass): type, location,
 * elapsed, trigger source, status. The data model has no field separate
 * from trigger_source for "incident type" — manual_sos/voice_distress is
 * both at once — so the icon+text line covers both rather than repeating
 * the same value on two lines, which the same pass explicitly asks to
 * avoid ("avoid excessive badges... avoid unnecessary icons"). The old
 * second "verification state" badge is dropped for the same reason: tier
 * (needs-review vs in-progress) is already carried by the status badge's
 * own color/variant, so a second badge repeated that signal without
 * adding one.
 */
function QueueRow({ incident, isSelected, onSelect }) {
  const elapsed = useElapsedSeconds(incident.created_at)
  const isUrgent = needsReview(incident.status)

  return (
    <button
      type="button"
      onClick={() => onSelect(incident.incident_id)}
      aria-current={isSelected ? 'true' : undefined}
      className={cn(
        'queue-row flex w-full flex-col gap-1 rounded-md border px-2.5 py-2 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:scale-[0.98]',
        isSelected
          ? 'border-ring bg-accent'
          : 'border-transparent bg-card/60 hover:border-border hover:bg-card'
      )}
      style={{ borderLeftColor: STATUS_COLORS[incident.status], borderLeftWidth: 3 }}
    >
      <span className="flex items-center gap-1.5 text-xs font-medium text-foreground">
        {triggerIconElement(incident.trigger_source, 'size-3.5 shrink-0 text-muted-foreground')}
        <span className="truncate">{triggerSourceLabel(incident.trigger_source)}</span>
      </span>

      <span className="truncate text-[11px] text-muted-foreground">
        {incident.barangay_name ?? 'Unresolved location'}
      </span>

      <div className="mt-0.5 flex items-center justify-between gap-2">
        <span
          className={cn(
            'font-mono text-[11px] font-semibold tabular-nums',
            isUrgent ? 'text-destructive' : 'text-muted-foreground'
          )}
        >
          {elapsed === null ? '—' : formatElapsed(elapsed)}
        </span>
        <Badge variant={statusBadgeVariant(incident.status)} className="text-[10.5px]">
          {humanizeEnum(incident.status)}
        </Badge>
      </div>
    </button>
  )
}

/**
 * The persistent operational queue — replaces the old top-center
 * "needs-review rail." Scope broadened (persistent-queue redesign) from
 * only the pre-review subset to every non-terminal incident
 * (ACTIVE_STATUSES), ordered by status-tier then age — the incident
 * waiting longest for a human decision leads. Sourced entirely from the
 * already-loaded incident list, no per-row fetch.
 *
 * `loading` is a distinct state from "queue is genuinely empty" — the
 * parent's `incidents` list is `null` (not `[]`) during its initial
 * fetch, and DispatcherConsoleLayout already normalizes that to `[]`
 * before this component ever sees it (so `IncidentQueue` never has to
 * handle `null` incidents itself), which meant the "All clear" state was
 * indistinguishable from "still loading" here — confirmed by a real
 * screenshot showing both the loading banner and "All clear" on screen
 * at once, not assumed from reading the code. `loading` restores that
 * distinction explicitly.
 */
export function IncidentQueue({ incidents, loading, selectedIncidentId, onSelectIncident }) {
  const queueIncidents = incidents
    .filter((incident) => ACTIVE_STATUSES.includes(incident.status))
    .sort(
      (a, b) =>
        tierFor(a.status) - tierFor(b.status) ||
        parseApiTimestamp(a.created_at) - parseApiTimestamp(b.created_at)
    )

  const needsReviewCount = queueIncidents.filter((incident) => tierFor(incident.status) === 0).length

  const lastResolved = incidents
    .filter((incident) => incident.status === 'resolved')
    .sort((a, b) => parseApiTimestamp(b.resolved_at) - parseApiTimestamp(a.resolved_at))[0]
  const lastResolvedElapsed = useElapsedSeconds(lastResolved?.resolved_at ?? null)

  return (
    <aside
      aria-label="Incident queue"
      className="absolute inset-y-0 left-0 z-10 flex w-72 flex-col border-r border-border bg-background/95 shadow-elevation-2 backdrop-blur"
    >
      <div className="border-b border-border px-3 py-2.5">
        {loading ? (
          <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
            <Loader2 className="size-3.5 animate-spin" />
            Loading queue…
          </span>
        ) : needsReviewCount === 0 ? (
          <div className="flex flex-col gap-0.5">
            <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <CircleCheck className="size-3.5 text-emerald-500" />
              All clear — no incidents need review
            </span>
            {lastResolved && (
              <span className="pl-5 text-[10.5px] text-muted-foreground/70">
                Last resolved {lastResolvedElapsed === null ? '—' : formatElapsed(lastResolvedElapsed)} ago
              </span>
            )}
          </div>
        ) : (
          <span className="text-xs font-semibold text-destructive">
            Needs review <span className="font-mono tabular-nums">{needsReviewCount}</span>
          </span>
        )}
        {!loading && (
          <div className="mt-1 text-[10.5px] text-muted-foreground">
            Queue <span className="font-mono tabular-nums">{queueIncidents.length}</span>
          </div>
        )}
      </div>

      <div className="flex-1 overflow-y-auto p-2">
        {loading ? null : queueIncidents.length === 0 ? (
          <p className="px-1 py-4 text-center text-[11px] text-muted-foreground">
            No active incidents right now.
          </p>
        ) : (
          <div className="flex flex-col gap-1.5">
            {queueIncidents.map((incident) => (
              <QueueRow
                key={incident.incident_id}
                incident={incident}
                isSelected={incident.incident_id === selectedIncidentId}
                onSelect={onSelectIncident}
              />
            ))}
          </div>
        )}
      </div>
    </aside>
  )
}
