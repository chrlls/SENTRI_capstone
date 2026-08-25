import { Badge } from '@/components/ui/badge'
import { formatRelativeTime, humanizeEnum } from '@/lib/utils'

function statusVariant(status) {
  switch (status) {
    case 'detected':
    case 'dashboard_alerted':
      return 'destructive'
    case 'dispatcher_reviewing':
      return 'default'
    case 'dispatched':
      return 'secondary'
    default:
      return 'outline'
  }
}

export function IncidentList({ incidents, onSelectIncident }) {
  return (
    <ul className="flex flex-col divide-y divide-border overflow-y-auto">
      {incidents.map((incident) => (
        <li key={incident.incident_id}>
          <button
            type="button"
            onClick={() => onSelectIncident(incident.incident_id)}
            className="flex w-full flex-col gap-1.5 px-4 py-3 text-left transition-colors hover:bg-muted/60"
          >
            <div className="flex items-center justify-between gap-2">
              <Badge variant={statusVariant(incident.status)}>{humanizeEnum(incident.status)}</Badge>
              <span className="text-xs text-muted-foreground">{formatRelativeTime(incident.created_at)}</span>
            </div>
            <div className="flex items-center justify-between gap-2 text-sm">
              <span className="text-foreground">{humanizeEnum(incident.trigger_source)}</span>
              <span className="font-mono text-xs text-muted-foreground">
                {incident.latitude.toFixed(4)}, {incident.longitude.toFixed(4)}
              </span>
            </div>
          </button>
        </li>
      ))}
    </ul>
  )
}
