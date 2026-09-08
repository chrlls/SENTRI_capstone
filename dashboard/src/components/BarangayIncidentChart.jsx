import { Bar, BarChart, CartesianGrid, Cell, XAxis, YAxis } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'

const BAR_CONFIG = {
  count: { label: 'Incidents', color: 'var(--chart-2)' },
}

/**
 * Horizontal, not vertical — barangay names are long ("Unresolved (no
 * boundary match)"), and rotated tick labels under a vertical bar chart
 * hurt legibility more than they save space. "Unresolved" gets a lighter,
 * distinct fill (not a color with any other meaning elsewhere on this
 * page) since it's categorically different from a named barangay — a
 * real, documented data gap (TASK_CHECKLIST.md: barangay boundary data
 * isn't fully populated yet), not an error to flag with amber/crimson.
 */
export function BarangayIncidentChart({ data }) {
  return (
    <ChartContainer config={BAR_CONFIG} className="aspect-auto h-64 w-full">
      <BarChart data={data} layout="vertical" margin={{ left: 8, right: 16, top: 8, bottom: 0 }}>
        <CartesianGrid horizontal={false} stroke="var(--border)" />
        <XAxis type="number" tickLine={false} axisLine={false} tickMargin={8} allowDecimals={false} />
        <YAxis
          type="category"
          dataKey="barangay"
          tickLine={false}
          axisLine={false}
          tickMargin={8}
          width={150}
        />
        <ChartTooltip content={<ChartTooltipContent hideLabel />} />
        <Bar dataKey="count" radius={[0, 3, 3, 0]}>
          {data.map((row) => (
            <Cell
              key={row.barangay}
              fill={row.barangay.startsWith('Unresolved') ? 'var(--chart-5)' : 'var(--color-count)'}
            />
          ))}
        </Bar>
      </BarChart>
    </ChartContainer>
  )
}
