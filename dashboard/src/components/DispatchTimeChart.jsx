import { CartesianGrid, Line, LineChart, XAxis, YAxis } from 'recharts'
import { ChartContainer, ChartLegend, ChartLegendContent, ChartTooltip } from '@/components/ui/chart'
import { formatDurationMinutes } from '@/lib/utils'

/**
 * Plain-language legend labels, not bare "p50" / "p90" — the card can't
 * assume the viewer reads percentile notation. Two treatments in the
 * SENTRI blue tint scale, told apart by a dash pattern plus a dark/light
 * step, not by a "slower = worse" colour: P90 is the expected long tail
 * of a distribution, not an error state. P50 solid on the brand blue,
 * P90 dashed on a lighter step of it.
 */
const DISPATCH_TIME_CONFIG = {
  p50: { label: 'Typical (P50)', color: '#1362FE' },
  p90: { label: 'Slowest 10% (P90)', color: '#71A0FE' },
}

function DispatchTimeTooltip({ active, payload, label }) {
  if (!active || !payload?.length) {
    return null
  }

  return (
    <div className="min-w-44 rounded-lg border border-white/10 bg-[#010919] px-2.5 py-2 text-xs text-white shadow-lg">
      <p className="mb-1.5 font-medium">{label}</p>
      <ul className="grid gap-1">
        {payload.map((entry) => (
          <li key={entry.dataKey} className="flex items-center justify-between gap-4">
            <span className="flex items-center gap-1.5 text-white/70">
              <span
                aria-hidden="true"
                className="h-0.5 w-3 shrink-0 rounded-full"
                style={{ backgroundColor: DISPATCH_TIME_CONFIG[entry.dataKey]?.color ?? entry.color }}
              />
              {DISPATCH_TIME_CONFIG[entry.dataKey]?.label ?? entry.dataKey}
            </span>
            <span className="font-mono tabular-nums text-white">{formatDurationMinutes(entry.value)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

export function DispatchTimeChart({ data }) {
  return (
    <ChartContainer
      config={DISPATCH_TIME_CONFIG}
      className="aspect-auto h-64 w-full"
      role="img"
      aria-label="Line chart of time from incident detection to human dispatch over the selected date range, showing the typical (50th percentile) time and the slowest-10% (90th percentile) time in minutes."
    >
      <LineChart data={data} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey="date" tickLine={false} axisLine={false} tickMargin={8} minTickGap={32} />
        <YAxis
          tickLine={false}
          axisLine={false}
          tickMargin={8}
          width={40}
          allowDecimals={false}
          tickFormatter={(value) => `${value}m`}
        />
        <ChartTooltip content={<DispatchTimeTooltip />} />
        <ChartLegend content={<ChartLegendContent />} />
        <Line dataKey="p50" type="monotone" stroke="var(--color-p50)" strokeWidth={2} dot={false} />
        <Line
          dataKey="p90"
          type="monotone"
          stroke="var(--color-p90)"
          strokeWidth={2}
          strokeDasharray="5 4"
          dot={false}
        />
      </LineChart>
    </ChartContainer>
  )
}
