import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'
import { TRIGGER_SOURCE_CONFIG } from '@/lib/adminMockData'

/**
 * Composition-over-time, not just a same-day snapshot — a stacked area
 * answers "what kind of trigger, and is it trending" in one chart rather
 * than two. Deliberately not a plain Line (see AdminOverviewPage.jsx's
 * comment on this) — the composition breakdown is the actual point here.
 * Recharts' default transition animation stays on — tweening between old
 * and new data when the range control changes is a real, motivated state
 * transition (Emil Kowalski's animation framework: does it explain what
 * changed), not decoration. Verification just has to wait for it to
 * settle before reading/screenshotting the final values.
 */
export function IncidentTrendChart({ data }) {
  return (
    <ChartContainer config={TRIGGER_SOURCE_CONFIG} className="aspect-auto h-64 w-full">
      <AreaChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey="date" tickLine={false} axisLine={false} tickMargin={8} minTickGap={24} />
        <YAxis tickLine={false} axisLine={false} tickMargin={8} width={28} allowDecimals={false} />
        <ChartTooltip content={<ChartTooltipContent />} />
        {Object.keys(TRIGGER_SOURCE_CONFIG).map((key) => (
          <Area
            key={key}
            dataKey={key}
            type="monotone"
            stackId="trigger-source"
            stroke={`var(--color-${key})`}
            fill={`var(--color-${key})`}
            fillOpacity={0.75}
            strokeWidth={1.5}
          />
        ))}
      </AreaChart>
    </ChartContainer>
  )
}
