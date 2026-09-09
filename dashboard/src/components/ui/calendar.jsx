import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

const WEEKDAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

const startOfDay = (date) => {
  const next = new Date(date)
  next.setHours(0, 0, 0, 0)
  return next
}
const addMonths = (date, amount) => new Date(date.getFullYear(), date.getMonth() + amount, 1)
const isSameDay = (a, b) =>
  !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()

const isWithin = (day, from, to) => {
  if (!from || !to) return false
  const t = startOfDay(day).getTime()
  return t > startOfDay(from).getTime() && t < startOfDay(to).getTime()
}

/** 6-week (42-cell) grid for `monthDate`'s month, padded with the surrounding months' days. */
const monthMatrix = (monthDate) => {
  const first = new Date(monthDate.getFullYear(), monthDate.getMonth(), 1)
  const gridStart = new Date(first)
  gridStart.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(gridStart)
    day.setDate(gridStart.getDate() + index)
    return day
  })
}

function MonthGrid({ monthDate, selected, today, onPick, isDisabled }) {
  const from = selected?.from
  const to = selected?.to

  return (
    <div className="w-[15rem]">
      <div className="mb-2 text-center font-medium text-foreground text-sm">
        {MONTHS[monthDate.getMonth()]} {monthDate.getFullYear()}
      </div>
      <div className="grid grid-cols-7">
        {WEEKDAYS.map((weekday) => (
          <div key={weekday} className="pb-1.5 text-center font-normal text-[0.7rem] text-muted-foreground">
            {weekday}
          </div>
        ))}
        {monthMatrix(monthDate).map((day) => {
          const outside = day.getMonth() !== monthDate.getMonth()
          const disabled = isDisabled?.(day) ?? false
          const endpoint = !disabled && (isSameDay(day, from) || isSameDay(day, to))
          const middle = !disabled && isWithin(day, from, to)
          const complete = !!from && !!to
          const inSpan = middle || (endpoint && complete)

          return (
            <div
              key={day.toISOString()}
              className={cn(
                'flex justify-center py-0.5',
                inSpan && 'bg-[#1362FE]/10',
                complete && isSameDay(day, from) && 'rounded-l-md',
                complete && isSameDay(day, to) && 'rounded-r-md',
                endpoint && !complete && 'rounded-md',
              )}
            >
              <button
                type="button"
                disabled={disabled}
                onClick={() => onPick(startOfDay(day))}
                aria-label={day.toDateString()}
                aria-pressed={endpoint || middle}
                className={cn(
                  'flex size-8 items-center justify-center rounded-md text-sm transition-colors',
                  'hover:bg-[#1362FE]/15 disabled:pointer-events-none disabled:opacity-40',
                  outside ? 'text-muted-foreground/50' : 'text-foreground',
                  middle && !endpoint && 'text-foreground hover:bg-[#1362FE]/20',
                  endpoint && 'bg-[#1362FE] text-white hover:bg-[#1362FE] hover:text-white',
                  isSameDay(day, today) && !endpoint && 'font-semibold text-[#1362FE]',
                )}
              >
                {day.getDate()}
              </button>
            </div>
          )
        })}
      </div>
    </div>
  )
}

/**
 * Minimal range calendar — white surface, the selected span shaded a
 * #1362FE tint with solid #1362FE endpoints. Deliberately dependency-free
 * (no react-day-picker / date-fns): this is a JavaScript project, and a
 * small hand-rolled grid gives exact control over the SENTRI blue range
 * shade the design calls for.
 *
 * `selected` is `{ from, to }` (either may be undefined); `onSelect`
 * receives the next `{ from, to }`. A click sets `from` when the range is
 * empty or already complete, then `to` on the following click (the two
 * are swapped if the second date is earlier).
 */
export function Calendar({ selected, onSelect, numberOfMonths = 2, disabled, className }) {
  const [viewMonth, setViewMonth] = useState(() => {
    const base = selected?.to ?? selected?.from ?? new Date()
    return new Date(base.getFullYear(), base.getMonth() - (numberOfMonths > 1 ? 1 : 0), 1)
  })
  const today = startOfDay(new Date())

  const handlePick = (day) => {
    if (disabled?.(day)) return
    const { from, to } = selected ?? {}
    if (!from || (from && to)) {
      onSelect({ from: day, to: undefined })
    } else if (day.getTime() < from.getTime()) {
      onSelect({ from: day, to: from })
    } else {
      onSelect({ from, to: day })
    }
  }

  return (
    <div className={cn('p-3', className)}>
      <div className="mb-1 flex items-center justify-between">
        <Button
          type="button"
          variant="outline"
          size="icon"
          className="size-7 rounded-md"
          aria-label="Previous month"
          onClick={() => setViewMonth((month) => addMonths(month, -1))}
        >
          <ChevronLeft className="size-4" />
        </Button>
        <Button
          type="button"
          variant="outline"
          size="icon"
          className="size-7 rounded-md"
          aria-label="Next month"
          onClick={() => setViewMonth((month) => addMonths(month, 1))}
        >
          <ChevronRight className="size-4" />
        </Button>
      </div>
      <div className="flex flex-col gap-4 sm:flex-row">
        {Array.from({ length: numberOfMonths }, (_, index) => addMonths(viewMonth, index)).map((month) => (
          <MonthGrid
            key={`${month.getFullYear()}-${month.getMonth()}`}
            monthDate={month}
            selected={selected}
            today={today}
            onPick={handlePick}
            isDisabled={disabled}
          />
        ))}
      </div>
    </div>
  )
}
