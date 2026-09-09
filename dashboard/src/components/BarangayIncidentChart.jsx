import { Bar, BarChart, Cell, LabelList, XAxis, YAxis } from 'recharts'
import { ChartContainer, ChartTooltip } from '@/components/ui/chart'

const BAR_CONFIG = {
  count: { label: 'Incidents', color: '#1362FE' },
}

const UNMAPPED_FILL = '#A0C0FE'

/** Dark tooltip card — near-black SENTRI navy, matching the other dashboard charts. */
function BarangayTooltip({ active, payload }) {
  if (!active || !payload?.length) {
    return null
  }

  const row = payload[0].payload
  return (
    <div className="rounded-lg border border-white/10 bg-[#010919] px-2.5 py-2 text-xs text-white shadow-lg">
      <p className="font-medium">{row.barangay}</p>
      <p className="mt-0.5 tabular-nums text-white/70">
        {row.count} {row.count === 1 ? 'incident' : 'incidents'}
      </p>
    </div>
  )
}

/**
 * Horizontal, not vertical — barangay names are long and read straight
 * without rotation this way. Values are labelled directly at the end of
 * each bar (no x-axis needed) so there's no eye-travel to an axis. Bars
 * are the SENTRI brand blue; the `unmapped` row — incidents whose GPS
 * fell outside every configured barangay boundary, a real documented data
 * gap (TASK_CHECKLIST.md), not an error — gets a paler blue so it reads
 * as set apart from the real barangays (the title-level info tooltip
 * carries the explanation).
 */
export function BarangayIncidentChart({ data }) {
  const ordered = [...data].sort((a, b) => {
    if (a.unmapped) return 1
    if (b.unmapped) return -1
    return b.count - a.count
  })

  return (
    <ChartContainer
      config={BAR_CONFIG}
      className="aspect-auto h-64 w-full"
      role="img"
      aria-label={`Horizontal bar chart ranking barangays by incident count over the last 30 days. ${ordered
        .map((row) => `${row.barangay}: ${row.count}`)
        .join('. ')}.`}
    >
      <BarChart data={ordered} layout="vertical" margin={{ left: 8, right: 32, top: 4, bottom: 4 }}>
        <XAxis type="number" hide />
        <YAxis type="category" dataKey="barangay" tickLine={false} axisLine={false} tickMargin={8} width={150} />
        <ChartTooltip cursor={{ fill: 'var(--muted)' }} content={<BarangayTooltip />} />
        <Bar dataKey="count" radius={[0, 3, 3, 0]} maxBarSize={26}>
          {ordered.map((row) => (
            <Cell key={row.barangay} fill={row.unmapped ? UNMAPPED_FILL : 'var(--color-count)'} />
          ))}
          <LabelList
            dataKey="count"
            position="right"
            offset={8}
            className="fill-foreground font-mono text-xs tabular-nums"
          />
        </Bar>
      </BarChart>
    </ChartContainer>
  )
}
