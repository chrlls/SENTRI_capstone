import { formatElapsed, humanizeEnum } from '@/lib/utils'
import { useElapsedSeconds } from '@/hooks/useElapsedSeconds'
import { needsReview } from '@/lib/incidentStatus'
import { triggerIconElement, triggerSourceLabel } from '@/lib/triggerIcons'
import { cn } from '@/lib/utils'

/**
 * Sourced entirely from the already-loaded list response (Phase 1
 * confirmed trigger_source/status/coordinates are there; Phase 2 added
 * barangay_name; Phase 4 fixed ai_confidence_score to source from a real
 * voice_analysis_events join instead of the incidents column nothing ever
 * writes) — no per-hover fetch, matching the redesign's Doherty-threshold
 * goal.
 */
export function MarkerHoverCard({ incident }) {
  const elapsed = useElapsedSeconds(incident.created_at)
  const isUrgent = needsReview(incident.status)

  return (
    <div className="flex w-44 flex-col gap-1.5 text-xs">
      <div className="flex items-center justify-between gap-2">
        <span className="flex items-center gap-1.5 font-medium text-foreground">
          {triggerIconElement(incident.trigger_source, 'size-3.5 text-muted-foreground')}
          {triggerSourceLabel(incident.trigger_source)}
        </span>
        <span
          className={cn(
            'font-mono text-[11px] font-semibold tabular-nums',
            isUrgent ? 'text-destructive' : 'text-muted-foreground'
          )}
        >
          {elapsed === null ? '—' : formatElapsed(elapsed)}
        </span>
      </div>

      <span className="text-muted-foreground">{incident.barangay_name ?? 'Unresolved location'}</span>

      <div className="flex items-center gap-1.5">
        <span className="text-[11px] text-muted-foreground">{humanizeEnum(incident.status)}</span>
        {incident.ai_confidence_score !== null && (
          <span className="rounded bg-purple-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-purple-400">
            AI {Math.round(incident.ai_confidence_score * 100)}%
          </span>
        )}
      </div>
    </div>
  )
}
