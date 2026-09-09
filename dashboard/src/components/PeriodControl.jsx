import { DateRangeControl } from '@/components/DateRangeControl'
import { PERIOD_PRESETS, customPeriod, presetPeriod } from '@/lib/dashboardPeriod'
import { cn } from '@/lib/utils'

/**
 * Page-level period control on the dashboard's title row — one shared
 * `period` object (see lib/dashboardPeriod.js), never two disagreeing
 * pieces of state:
 *   • the pill-segmented Day / Week / Month / Year selector sets a preset
 *     window (Week is the default);
 *   • the calendar pill (DateRangeControl) *shows* that window's dates,
 *     and stays clickable to pick a custom span. Picking one clears the
 *     preset highlight (period.preset === null) rather than leaving a
 *     segment lit that no longer matches the dates.
 * Drives the trend chart, the trigger-source mix and the dispatch-time
 * chart; the KPI cards keep their own comparison cadence regardless.
 */
export function PeriodControl({ value, onChange }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <div
        role="group"
        aria-label="Time range"
        className="flex items-center gap-0.5 rounded-full bg-[#FFFEFF] p-1 shadow-(--shadow-admin-card)"
      >
        {PERIOD_PRESETS.map((preset) => {
          const selected = value.preset === preset.key
          return (
            <button
              key={preset.key}
              type="button"
              onClick={() => onChange(presetPeriod(preset.key))}
              aria-pressed={selected}
              className={cn(
                'rounded-full px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                selected ? 'bg-[#1362FE] text-white' : 'text-muted-foreground hover:text-foreground'
              )}
            >
              {preset.label}
            </button>
          )
        })}
      </div>

      <DateRangeControl
        value={{ from: value.from, to: value.to }}
        onSelect={(range) => onChange(customPeriod(range))}
      />
    </div>
  )
}
