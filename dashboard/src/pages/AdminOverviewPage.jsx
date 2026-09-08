import { useMemo, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { AdminPageHeader } from '@/components/AdminPageHeader'
import { StatBlock } from '@/components/StatBlock'
import { ActivityList } from '@/components/ActivityList'
import { DateRangeControl } from '@/components/DateRangeControl'
import { IncidentTrendChart } from '@/components/IncidentTrendChart'
import { DispatchTimeChart } from '@/components/DispatchTimeChart'
import { BarangayIncidentChart } from '@/components/BarangayIncidentChart'
import { VerificationQueueList } from '@/components/VerificationQueueList'
import {
  ADMIN_KPI_STATS,
  ADMIN_RECENT_ACTIVITY,
  ADMIN_BARANGAY_INCIDENTS,
  ADMIN_VERIFICATION_QUEUE,
  getIncidentTrendSeries,
  getDispatchTimeSeries,
} from '@/lib/adminMockData'

/**
 * Derives a real trend from current/previous values rather than
 * hardcoding one — see adminMockData.js's own header comment. Pill color
 * comes from comparing the actual direction against `goodDirection`
 * (does this specific metric want to go up or down), not a static label —
 * a metric with `tone` set (Incidents Today) skips that comparison
 * entirely, since raw volume has no inherently good direction.
 */
function trendFor(stat) {
  if (!stat.previousValue) {
    return null
  }

  const delta = stat.value - stat.previousValue
  const direction = delta >= 0 ? 'up' : 'down'
  const tone = stat.tone ?? (direction === stat.goodDirection ? 'positive' : 'caution')

  const deltaLabel =
    stat.deltaMode === 'points' ? `${Math.abs(delta).toFixed(2)}pp` : `${((Math.abs(delta) / stat.previousValue) * 100).toFixed(1)}%`

  return {
    direction,
    tone,
    deltaLabel,
    periodLabel: stat.previousPeriod,
    title: `${stat.value}${stat.suffix ?? ''} vs ${stat.previousValue}${stat.suffix ?? ''} ${stat.previousPeriod}`,
  }
}

/**
 * Admin landing page — system/account/platform state at a glance, not a
 * second dispatcher console. No live queue, no dispatch controls, no map:
 * those stay in DispatcherConsoleLayout. All figures here are static
 * presentation data (see adminMockData.js's own header comment).
 */
export function AdminOverviewPage() {
  const [rangeDays, setRangeDays] = useState(30)

  const incidentTrendData = useMemo(() => getIncidentTrendSeries(rangeDays), [rangeDays])
  const dispatchTimeData = useMemo(() => getDispatchTimeSeries(rangeDays), [rangeDays])

  return (
    <div className="flex flex-col gap-6">
      <AdminPageHeader />

      <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
        {ADMIN_KPI_STATS.map((stat) => (
          <StatBlock
            key={stat.key}
            label={stat.label}
            value={`${stat.value}${stat.suffix ?? ''}`}
            trend={trendFor(stat)}
          />
        ))}
      </section>

      <div className="flex items-center justify-between gap-3">
        <h2 className="font-heading text-sm font-semibold text-(--sentri-slate-label) uppercase tracking-wide">
          Trends
        </h2>
        <DateRangeControl value={rangeDays} onChange={setRangeDays} />
      </div>

      <Card className="rounded-[14px] shadow-none">
        <CardHeader>
          <CardTitle>Incidents by trigger source</CardTitle>
        </CardHeader>
        <CardContent>
          <IncidentTrendChart data={incidentTrendData} />
        </CardContent>
      </Card>

      <section className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="rounded-[14px] shadow-none">
          <CardHeader>
            <CardTitle>Time to dispatch</CardTitle>
          </CardHeader>
          <CardContent>
            <DispatchTimeChart data={dispatchTimeData} />
          </CardContent>
        </Card>

        <Card className="rounded-[14px] shadow-none">
          <CardHeader>
            <CardTitle>Incidents by barangay</CardTitle>
          </CardHeader>
          <CardContent>
            <BarangayIncidentChart data={ADMIN_BARANGAY_INCIDENTS} />
          </CardContent>
        </Card>
      </section>

      <section className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="rounded-[14px] shadow-none">
          <CardHeader>
            <CardTitle>Responder verification queue</CardTitle>
          </CardHeader>
          <CardContent>
            <VerificationQueueList items={ADMIN_VERIFICATION_QUEUE} />
          </CardContent>
        </Card>

        <Card className="rounded-[14px] shadow-none">
          <CardHeader>
            <CardTitle>Recent administrative activity</CardTitle>
          </CardHeader>
          <CardContent>
            <ActivityList items={ADMIN_RECENT_ACTIVITY} />
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
