import { useEffect } from 'react'
import { MapContainer, TileLayer, Marker, Tooltip, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { humanizeEnum } from '@/lib/utils'

// Tagum City, Davao del Norte — the manuscript's operational area, used
// as the default view when there are no incidents yet to fit bounds to.
const DEFAULT_CENTER = [7.4478, 125.8078]
const DEFAULT_ZOOM = 14

// Floor on how far fitBounds (below) is allowed to zoom out. Without this,
// a single incident with an out-of-area coordinate (bad test data, a
// placeholder like 0,0, a stray GPS fix) forces fitBounds to zoom out
// enough to include it too — which can look like the map "covers whole
// continents" instead of staying scoped to the operational area. Kept
// close to Tagum City proper rather than the wider region.
const MIN_ZOOM = 13

// Tagum City plus breathing room into surrounding Davao del Norte (north
// toward Asuncion/Kapalong, south past Panabo, east toward Maco, west to
// the coast) — SENTRI's scope per the manuscript is this area specifically,
// not a pannable world map. maxBoundsViscosity=1.0 makes the edge a firm
// "soft wall" (resists dragging past it) rather than a rubber-band overshoot.
const TAGUM_AREA_BOUNDS = [
  [7.1, 125.4],
  [7.8, 126.2],
]

const STATUS_COLORS = {
  detected: '#c15353',
  dashboard_alerted: '#c15353',
  dispatcher_reviewing: '#d6a24c',
  dispatched: '#4c8df5',
  resolved: '#4caf7d',
  false_alarm: '#565f70',
  cancelled: '#565f70',
}

/**
 * A plain colored dot via L.divIcon, not Leaflet's default pin — sidesteps
 * the well-known bundler-asset path issue with L.Icon.Default entirely,
 * and fits the flat/minimal console aesthetic better than a default pin.
 */
function incidentIcon(status) {
  const color = STATUS_COLORS[status] ?? '#8a93a6'

  return L.divIcon({
    className: '',
    html: `<span style="display:block;width:14px;height:14px;border-radius:9999px;background:${color};border:2px solid rgba(255,255,255,0.85);box-shadow:0 0 0 3px rgba(0,0,0,0.35)"></span>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  })
}

function FitToIncidents({ incidents }) {
  const map = useMap()

  useEffect(() => {
    if (incidents.length === 0) {
      return
    }

    if (incidents.length === 1) {
      map.setView([incidents[0].latitude, incidents[0].longitude], 15)
      return
    }

    const bounds = L.latLngBounds(incidents.map((incident) => [incident.latitude, incident.longitude]))
    map.fitBounds(bounds, { padding: [32, 32] })
  }, [incidents, map])

  return null
}

export function IncidentMap({ incidents, onSelectIncident }) {
  return (
    <MapContainer
      center={DEFAULT_CENTER}
      zoom={DEFAULT_ZOOM}
      minZoom={MIN_ZOOM}
      maxBounds={TAGUM_AREA_BOUNDS}
      maxBoundsViscosity={1.0}
      className="h-full w-full"
    >
      <TileLayer
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      />
      <FitToIncidents incidents={incidents} />
      {incidents.map((incident) => (
        <Marker
          key={incident.incident_id}
          position={[incident.latitude, incident.longitude]}
          icon={incidentIcon(incident.status)}
          eventHandlers={onSelectIncident ? { click: () => onSelectIncident(incident.incident_id) } : undefined}
        >
          <Tooltip direction="top" offset={[0, -8]}>
            {humanizeEnum(incident.trigger_source)} · {humanizeEnum(incident.status)}
          </Tooltip>
        </Marker>
      ))}
    </MapContainer>
  )
}
