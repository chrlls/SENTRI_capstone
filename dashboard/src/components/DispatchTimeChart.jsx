import { CartesianGrid, Line, LineChart, XAxis, YAxis } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'

/**
 * p90 is the point, not p50 — a calm median can hide a bad tail (10% of
 * incidents quietly sitting well past the median while the number that
 * gets quoted looks fine). p90 gets amber, the same "needs attention"
 * color the KPI row's caution pill uses — not Crimson Blaze, which stays
 * reserved for the dispatcher console's real active alerts.
 */
const DISPATCH_TIME_CONFIG = {
  p50: { label: 'Median (p50)', color: 'var(--chart-3)' },
  p90: { label: '90th percentile (p90)', color: '#B45309' },
}

export function DispatchTimeChart({ data }) {
  // Recharts' auto-generated ticks rendered out of numeric order for this
  // domain (observed directly in a screenshot: "4m, 8m, 2m, 6m, 0m" top to
  // bottom, not a sorted sequence) — computing explicit, evenly-stepped
  // integer ticks from the actual data sidesteps whatever's wrong with its
  // default "nice number" selection here, rather than trusting it.
  const maxMinutes = Math.max(1, ...data.flatMap((row) => [row.p50, row.p90]))
  const step = Math.ceil(maxMinutes / 4)
  const ticks = [0, step, step * 2, step * 3, step * 4]

  return (
    <ChartContainer config={DISPATCH_TIME_CONFIG} className="aspect-auto h-64 w-full">
      <LineChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey="date" tickLine={false} axisLine={false} tickMargin={8} minTickGap={24} />
        <YAxis
          tickLine={false}
          axisLine={false}
          tickMargin={8}
          width={32}
          domain={[0, step * 4]}
          ticks={ticks}
          tickFormatter={(value) => `${value}m`}
        />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Line dataKey="p50" type="monotone" stroke="var(--color-p50)" strokeWidth={2} dot={false} />
        <Line dataKey="p90" type="monotone" stroke="var(--color-p90)" strokeWidth={2} dot={false} strokeDasharray="4 3" />
      </LineChart>
    </ChartContainer>
  )
}
