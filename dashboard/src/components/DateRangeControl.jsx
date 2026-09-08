import { ChevronDown } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

const RANGE_OPTIONS = [
  { days: 7, label: 'Last 7 days' },
  { days: 30, label: 'Last 30 days' },
  { days: 90, label: 'Last 90 days' },
]

/**
 * Scoped to the chart section below the KPI row, not the top search
 * header (kept deliberately free of controls) and not the KPI row itself
 * (each of its cards keeps its own natural comparison cadence — see
 * AdminOverviewPage.jsx's trendFor()). Built on the existing DropdownMenu
 * primitive rather than a new calendar/date-picker dependency.
 */
export function DateRangeControl({ value, onChange }) {
  const current = RANGE_OPTIONS.find((option) => option.days === value) ?? RANGE_OPTIONS[1]

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="rounded-[3px]">
          {current.label}
          <ChevronDown className="size-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {RANGE_OPTIONS.map((option) => (
          <DropdownMenuItem key={option.days} onClick={() => onChange(option.days)}>
            {option.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
