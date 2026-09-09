import { TrendingDown, TrendingUp } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { cn } from '@/lib/utils'

/**
 * Trend-indicator colour is keyed by sentiment (`tone`), not by arrow
 * direction — an increase isn't automatically good news, so the two stay
 * independent. `positive` uses SENTRI blue; `caution` (the number moved
 * against the metric's favourable direction — e.g. the false-alarm rate
 * climbing) uses the brand red, the one place red is allowed on the KPI
 * row; `neutral` stays muted for a metric with no inherently good
 * direction (Incidents Today). This red is distinct in meaning from the
 * dispatcher console's active-alert crimson: here it just flags a KPI
 * trending the wrong way, not a live incident.
 */
const TREND_TONE_STYLES = {
  positive: 'text-[#1362FE]',
  caution: 'text-destructive',
  neutral: 'text-muted-foreground',
}

/**
 * KPI card — a muted label, one dominant value, and a compact
 * "<trend arrow> <delta> vs <period>" line beneath it. White surface on a
 * very light shadow (no border, `--shadow-admin-card`), 14px radius,
 * generous padding. The slanted trend arrow matches the trigger-source
 * mix panel; its colour is supplementary — the arrow carries direction,
 * the number carries magnitude, and an aria-label spells the whole thing
 * out.
 */
export function StatBlock({ label, value, trend, className }) {
  const TrendArrow = trend?.direction === 'up' ? TrendingUp : TrendingDown

  return (
    <Card className={cn('rounded-[14px] ring-0 shadow-(--shadow-admin-card) [--card-spacing:--spacing(5)]', className)}>
      <CardContent className="flex flex-col gap-3">
        <span className="font-mono text-xs font-medium tracking-wide text-(--sentri-slate-label) uppercase">
          {label}
        </span>

        <span className="font-heading text-[28px] leading-none font-semibold tracking-tight text-foreground tabular-nums">
          {value}
        </span>

        {trend && (
          <div className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-xs">
            <span
              className={cn(
                'inline-flex items-center gap-0.5 font-medium whitespace-nowrap tabular-nums',
                TREND_TONE_STYLES[trend.tone]
              )}
              aria-label={`${trend.direction === 'up' ? 'Up' : 'Down'} ${trend.deltaLabel} versus ${trend.periodLabel}`}
            >
              <TrendArrow className="size-3" aria-hidden="true" />
              {trend.deltaLabel}
            </span>
            <span className="text-muted-foreground">vs {trend.periodLabel}</span>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
