import { cn } from '@/lib/utils'
import { INCIDENT_FILTERS } from '@/lib/incidentStatus'

export function IncidentFilterStrip({ incidents, activeFilter, onFilterChange }) {
  return (
    <div className="absolute bottom-3.5 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1 rounded-full border border-border bg-popover/90 p-1 shadow-elevation-2 backdrop-blur">
      {INCIDENT_FILTERS.map((filter) => {
        const count = incidents.filter((incident) => filter.match(incident.status)).length
        const isActive = filter.key === activeFilter

        return (
          <button
            key={filter.key}
            type="button"
            onClick={() => onFilterChange(filter.key)}
            aria-pressed={isActive}
            className={cn(
              'flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs transition-[color,background-color,transform] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:scale-95',
              isActive ? 'bg-accent text-accent-foreground' : 'text-muted-foreground hover:text-foreground'
            )}
          >
            {filter.label}
            <span
              className={cn(
                'font-mono tabular-nums',
                isActive ? 'text-accent-foreground' : 'text-muted-foreground/70'
              )}
            >
              {count}
            </span>
          </button>
        )
      })}
    </div>
  )
}
