import { TrendingDown, TrendingUp } from 'lucide-react'

/**
 * Directional change vs the previous period. Neutral colour on purpose —
 * a rise or fall in incident volume isn't inherently good or bad news
 * (same reasoning the KPI row applies to "Incidents Today"), so this
 * carries direction and magnitude only. Very short windows swing hard on
 * small counts, so the magnitude is capped at a readable ceiling.
 */
function DeltaIndicator({ value }) {
  if (value === null || value === 0) {
    return <span className="w-12 text-right text-muted-foreground/70">—</span>
  }

  const rising = value > 0
  const magnitude = Math.abs(value)
  const Icon = rising ? TrendingUp : TrendingDown

  return (
    <span
      className="flex w-12 items-center justify-end gap-0.5 text-muted-foreground tabular-nums"
      aria-label={`${rising ? 'Up' : 'Down'} ${magnitude > 99 ? 'over 99' : magnitude} percent versus the previous period`}
    >
      <Icon className="size-3 shrink-0" aria-hidden="true" />
      {magnitude > 99 ? '99+' : magnitude}%
    </span>
  )
}

/**
 * Aggregate companion to IncidentTrendChart — where the chart shows how
 * each trigger source moves over the window, this shows where the four
 * stand for the whole window: count, share of total, a share bar in the
 * source's own blue, and the change from the period before. Same colour
 * mapping as the chart so the two read together.
 */
export function TriggerSourceMix({ data, rangeDays }) {
  const { total, sources } = data

  return (
    <div className="flex flex-col gap-4">
      <div>
        <p className="font-heading text-[28px] leading-none font-semibold tabular-nums text-foreground">
          {total.toLocaleString()}
        </p>
        <p className="mt-1 text-xs text-muted-foreground">
          incidents · {rangeDays === 1 ? 'today' : `last ${rangeDays} days`}
        </p>
      </div>

      <ul className="flex flex-col gap-3">
        {sources.map((source) => (
          <li key={source.key} className="flex flex-col gap-1.5">
            <div className="flex items-center justify-between gap-3 text-sm">
              <span className="flex min-w-0 items-center gap-2 text-foreground">
                <span
                  aria-hidden="true"
                  className="size-2 shrink-0 rounded-full"
                  style={{ backgroundColor: source.color }}
                />
                <span className="truncate">{source.label}</span>
              </span>
              <span className="flex shrink-0 items-baseline gap-2 tabular-nums">
                <span className="font-medium text-foreground">{source.count}</span>
                <span className="w-9 text-right text-muted-foreground">{Math.round(source.share * 100)}%</span>
                <DeltaIndicator value={source.deltaPct} />
              </span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full"
                style={{ width: `${Math.max(source.share * 100, 1.5)}%`, backgroundColor: source.color }}
              />
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
