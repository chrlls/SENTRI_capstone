import { useState } from 'react'
import { CalendarDays } from 'lucide-react'

import { Calendar } from '@/components/ui/calendar'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

const FORMAT = { day: 'numeric', month: 'short', year: 'numeric' }

function rangeLabel(range) {
  if (!range?.from) return 'Pick a date range'
  const from = range.from.toLocaleDateString('en-US', FORMAT)
  if (!range.to) return from
  return `${from} – ${range.to.toLocaleDateString('en-US', FORMAT)}`
}

const startOfToday = () => {
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  return now
}

/**
 * The calendar pill on the dashboard title row. It is a *view* of the one
 * shared period (`value` = `{ from, to }`): the segment buttons compute
 * that window and this shows it. It also stays clickable — picking a
 * custom span in the calendar calls `onSelect({ from, to })`, which the
 * parent turns into a preset-less period (so no segment stays
 * highlighted). White pill; the selected span shades a #1362FE tint.
 */
export function DateRangeControl({ value, onSelect }) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState(null)

  const shown = draft ?? value

  const handleCalendarSelect = (next) => {
    if (next.from && next.to) {
      setDraft(null)
      setOpen(false)
      onSelect(next)
    } else {
      setDraft(next)
    }
  }

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) setDraft(null)
      }}
    >
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`Date range: ${rangeLabel(value)}. Open calendar to pick a custom range.`}
          className="inline-flex items-center gap-2 rounded-full bg-[#FFFEFF] px-3.5 py-2.5 text-foreground text-xs shadow-(--shadow-admin-card) transition-colors hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring aria-expanded:bg-muted"
        >
          <CalendarDays className="size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <span className="tabular-nums">{rangeLabel(value)}</span>
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-auto p-0">
        <Calendar
          selected={shown}
          onSelect={handleCalendarSelect}
          numberOfMonths={2}
          disabled={(date) => date > startOfToday()}
        />
      </PopoverContent>
    </Popover>
  )
}
