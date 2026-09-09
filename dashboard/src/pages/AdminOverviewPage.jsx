import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { AdminPageHeader } from '@/components/AdminPageHeader'
import { StatBlock } from '@/components/StatBlock'
import { RecentActivity } from '@/components/RecentActivity'
import { PeriodControl } from '@/components/PeriodControl'
import { IncidentTrendChart } from '@/components/IncidentTrendChart'
import { TriggerSourceMix } from '@/components/TriggerSourceMix'
import { ChartInfoTooltip } from '@/components/ChartInfoTooltip'
import { DispatchTimeChart } from '@/components/DispatchTimeChart'
import { BarangayIncidentChart } from '@/components/BarangayIncidentChart'
import { DottedHealthRing } from '@/components/ui/dotted-health-ring'
import { DEFAULT_PERIOD } from '@/lib/dashboardPeriod'
import {
  ADMIN_KPI_STATS,
  ADMIN_RECENT_ACTIVITY,
  ADMIN_BARANGAY_INCIDENTS,
  getIncidentTrendSeries,
  getTriggerSourceMix,
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
  }
}

/**
 * Admin landing page — system/account/platform state at a glance, not a
 * second dispatcher console. No live queue, no dispatch controls, no map:
 * those stay in DispatcherConsoleLayout. All figures here are static
 * presentation data (see adminMockData.js's own header comment).
 */
export function AdminOverviewPage() {
  const [period, setPeriod] = useState(DEFAULT_PERIOD)
  const { rangeDays, endDaysAgo } = period

  const incidentTrendData = useMemo(() => getIncidentTrendSeries(rangeDays, endDaysAgo), [rangeDays, endDaysAgo])
  const triggerSourceMix = useMemo(() => getTriggerSourceMix(rangeDays, endDaysAgo), [rangeDays, endDaysAgo])
  const dispatchTimeData = useMemo(() => getDispatchTimeSeries(rangeDays, endDaysAgo), [rangeDays, endDaysAgo])

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <AdminPageHeader />
        <PeriodControl value={period} onChange={setPeriod} />
      </div>

      <section aria-label="Key metrics" className="grid grid-cols-2 gap-4 lg:grid-cols-4 lg:gap-5">
        {ADMIN_KPI_STATS.map((stat) => (
          <StatBlock
            key={stat.key}
            label={stat.label}
            value={`${stat.value}${stat.suffix ?? ''}`}
            trend={trendFor(stat)}
          />
        ))}
      </section>

      <section aria-label="Trends" className="flex flex-col gap-4">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-4">
          <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card) lg:col-span-2">
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>Incidents by trigger source</CardTitle>
                <ChartInfoTooltip
                  label="About the incidents by trigger source chart"
                  description="Shows daily incident volume over the selected period, grouped by trigger source."
                />
              </div>
            </CardHeader>
            <CardContent>
              <IncidentTrendChart data={incidentTrendData} />
            </CardContent>
          </Card>

          <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card) lg:col-span-1">
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>Trigger source mix</CardTitle>
                <ChartInfoTooltip
                  label="About the trigger source mix panel"
                  description="Each trigger source's share of incidents over the selected period, with its change from the period before."
                />
              </div>
            </CardHeader>
            <CardContent>
              <TriggerSourceMix data={triggerSourceMix} rangeDays={rangeDays} />
            </CardContent>
          </Card>

          <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card) lg:col-span-1">
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>System health</CardTitle>
                <ChartInfoTooltip
                  label="About the system health ring"
                  description="Overall SENTRI health (outer ring) and the health of supporting services — API, AI, notifications, database (inner ring)."
                />
              </div>
            </CardHeader>
            <CardContent className="flex flex-1 items-center justify-center">
              <DottedHealthRing className="py-2" />
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card)">
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>Time to dispatch</CardTitle>
                <ChartInfoTooltip
                  label="About the time to dispatch chart"
                  description="Time between incident detection and human dispatcher action."
                />
              </div>
            </CardHeader>
            <CardContent>
              <DispatchTimeChart data={dispatchTimeData} />
            </CardContent>
          </Card>

          <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card)">
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>Incidents by barangay</CardTitle>
                <ChartInfoTooltip
                  label="About the incidents by barangay chart"
                  description="Incident count per barangay over the last 30 days. 'Unmapped incidents' are those whose recorded location fell outside every configured barangay boundary."
                />
              </div>
            </CardHeader>
            <CardContent>
              <BarangayIncidentChart data={ADMIN_BARANGAY_INCIDENTS} />
            </CardContent>
          </Card>
        </div>
      </section>

      <section aria-label="Administrative activity" className="flex flex-col gap-3">
        <h2 className="font-heading text-xs font-semibold tracking-[0.12em] text-(--sentri-slate-label) uppercase">
          Administrative Activity
        </h2>

        <Card className="rounded-[14px] ring-0 shadow-(--shadow-admin-card)">
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
              <CardTitle>Recent Activity</CardTitle>
              <Link
                to="/admin/audit"
                className="inline-flex items-center gap-1 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
              >
                View audit logs
                <ArrowRight className="size-3.5" aria-hidden="true" />
              </Link>
            </div>
          </CardHeader>
          <CardContent>
            <RecentActivity activity={ADMIN_RECENT_ACTIVITY} />
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
