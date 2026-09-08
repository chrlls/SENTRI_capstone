import { TrendingDown, TrendingUp } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { cn } from '@/lib/utils'

/**
 * Trend pill color is keyed by sentiment (`tone`), not by arrow direction
 * — an increase isn't automatically good news (more pending verifications
 * is bad even though the arrow points up), so the two stay independent
 * signals. See adminMockData.js's own header comment for the full
 * reasoning per card. `caution` deliberately uses Tailwind's built-in
 * amber, not Crimson Blaze — crimson is reserved for the dispatcher
 * console's real, human-verified active alerts; reusing it here for "a
 * backlog grew" would dilute that meaning across the product.
 */
const TREND_TONE_STYLES = {
  positive: 'bg-emerald-50 text-emerald-700',
  caution: 'bg-amber-50 text-amber-700',
  neutral: 'bg-(--sentri-slate-label)/10 text-(--sentri-slate-label)',
}

/**
 * KPI card primitive — label + icon on top, a large value, and a single
 * colored trend pill combining the delta and the comparison period (e.g.
 * "9.9% vs last month") rather than a separate plain-text caption line.
 * Borderless by design (`ring-0`, `--shadow-admin-card` instead) so the
 * card reads as floating above the page rather than boxed — index.css's
 * own comment on that token explains why it's tinted to the brand's
 * obsidian hue rather than a generic black shadow.
 */
export function StatBlock({ label, value, icon: Icon, trend, className }) {
  return (
    <Card className={cn('rounded-[14px] ring-0 shadow-(--shadow-admin-card)', className)}>
      <CardContent className="flex flex-col gap-2.5">
        <div className="flex items-center justify-between gap-2">
          <span className="font-mono text-[11px] font-medium tracking-wide text-(--sentri-slate-label) uppercase">
            {label}
          </span>
          {Icon && <Icon className="size-3.5 shrink-0 text-(--sentri-slate-label)" aria-hidden="true" />}
        </div>

        <span className="font-heading text-2xl font-semibold text-foreground">{value}</span>

        {trend && (
          <span
            title={trend.title}
            className={cn(
              'inline-flex w-fit items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap',
              TREND_TONE_STYLES[trend.tone]
            )}
          >
            {trend.direction === 'up' ? <TrendingUp className="size-3" /> : <TrendingDown className="size-3" />}
            {trend.deltaLabel} vs {trend.periodLabel}
          </span>
        )}
      </CardContent>
    </Card>
  )
}
