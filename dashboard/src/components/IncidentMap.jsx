import { useEffect, useMemo, useState } from 'react'
import { Map, useMap, MapMarker, MarkerContent, MarkerTooltip } from '@/components/map/Map'
import { STATUS_COLORS } from '@/lib/incidentStatus'
import { MarkerHoverCard } from '@/components/MarkerHoverCard'
import operationsBasemapStyle from '@/lib/operationsBasemapStyle.json'
import { cn } from '@/lib/utils'

// Tagum City, Davao del Norte — the manuscript's operational area, used
// as the default view when there are no incidents yet to fit bounds to.
// MapLibre coordinate order is [lng, lat] — the reverse of Leaflet's
// [lat, lng], which this whole file used before the MapLibre migration.
const DEFAULT_CENTER = [125.8078, 7.4478]

/**
 * CAD/GIS zoom strategy — unchanged in intent from the pre-migration
 * Leaflet version, just re-verified for MapLibre's own zoom semantics
 * (they share the same slippy-map zoom-level definition, so the numbers
 * themselves port directly):
 *  - OVERVIEW (13): the whole operational area, multiple incidents
 *    visible at once — the map's resting state whenever no one incident
 *    owns the dispatcher's attention.
 *  - INCIDENT_CONTEXT (15): "where is this incident" — surrounding roads
 *    and barangay context stay legible, without a building-level
 *    zoom-in. Target for both the initial single-incident view and
 *    selecting a queue row.
 *  - MIN_ZOOM (13) matches OVERVIEW — floor exists so a single incident
 *    with a bad/out-of-area coordinate can't force the operational view
 *    to zoom out to "covers whole continents."
 * MAP_MAX_ZOOM (18) is the camera ceiling; each source's own `maxzoom`
 * (see operationsBasemapStyle.json's vector source and SATELLITE_STYLE
 * below) is set to where real tile data actually exists — 14 for the
 * CARTO vector source (confirmed via its own TileJSON), 17 for Esri's
 * World_Imagery (confirmed by fetching and inspecting real tiles in the
 * MapLibre-migration Phase 1 investigation). MapLibre overzooms
 * (upscales the last real tile) past a source's own maxzoom rather than
 * requesting a blank one — no placeholder tiles are ever faked as real
 * detail.
 */
const OVERVIEW_ZOOM = 13
const INCIDENT_CONTEXT_ZOOM = 15
const MIN_ZOOM = 13
const MAP_MAX_ZOOM = 18

// Tagum City plus breathing room into surrounding Davao del Norte (north
// toward Asuncion/Kapalong, south past Panabo, east toward Maco, west to
// the coast) — SENTRI's scope per the manuscript is this area specifically,
// not a pannable world map. The exact real-world box is unchanged from the
// pre-migration Leaflet version ([[7.1,125.4],[7.8,126.2]] there); this is
// the same box with each pair flipped to MapLibre's [lng,lat] order, not a
// re-derived value. MapLibre's maxBounds is a hard clamp with no viscosity
// option (Leaflet's maxBoundsViscosity=1.0 had no true MapLibre
// equivalent) — accepted as the stricter version of the same soft-wall
// intent, per the migration plan.
const TAGUM_AREA_MAX_BOUNDS = [
  [125.4, 7.1],
  [126.2, 7.8],
]

/**
 * Esri's free "World Imagery" satellite service, as a MapLibre raster
 * source/style — the same endpoint the pre-migration Leaflet Satellite
 * mode used, now expressed as a StyleSpecification object instead of a
 * react-leaflet <TileLayer>. `scheme` is left at MapLibre's default
 * ("xyz") deliberately: the MapLibre-migration Phase 1 investigation
 * confirmed Esri's row/column numbering already matches standard
 * north-origin XYZ (not TMS-flipped), the same conclusion this app's own
 * Leaflet rendering had already relied on successfully — no scheme flip
 * needed. The Dark_Gray_Reference layer (roads/place names) is stacked
 * on top for orientation, matching the pre-migration composition — a
 * bare satellite photo alone gave no orientation cues.
 *
 * raster-brightness-max/-contrast/-saturation on the imagery layer are a
 * ported approximation of the CSS filter (`brightness(0.8) contrast(0.92)
 * saturate(0.9)`) the old Leaflet implementation applied — MapLibre's
 * raster paint properties use a different scale (additive -1..1 for
 * contrast/saturation, not CSS's multiplicative percentage), so these
 * are a reasoned starting point, not a claimed exact match — to be
 * confirmed against a real screenshot, not assumed correct from the math
 * alone.
 */
const SATELLITE_STYLE = {
  version: 8,
  sources: {
    'esri-world-imagery': {
      type: 'raster',
      tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
      tileSize: 256,
      maxzoom: 17,
      attribution: 'Tiles &copy; Esri &mdash; Esri, Maxar, Earthstar Geographics, and the GIS User Community',
    },
    'esri-dark-gray-reference': {
      type: 'raster',
      tiles: [
        'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
      ],
      tileSize: 256,
      maxzoom: 16,
    },
  },
  layers: [
    {
      id: 'esri-world-imagery-layer',
      type: 'raster',
      source: 'esri-world-imagery',
      paint: {
        'raster-brightness-max': 0.8,
        'raster-contrast': -0.08,
        'raster-saturation': -0.1,
      },
    },
    { id: 'esri-dark-gray-reference-layer', type: 'raster', source: 'esri-dark-gray-reference' },
  ],
}

const BUILDING_LAYER_ID = 'building-top'

/**
 * The buildings fill layer already ships inside operationsBasemapStyle.json
 * (CARTO's Dark Matter style, verified via a real fetched-and-decompressed
 * Tagum City vector tile in the MapLibre-migration Phase 1 investigation —
 * not authored from scratch here), re-tinted from CARTO's default
 * rgba(57,57,57,1) to a shade in SENTRI's own dark palette family
 * (#343941 — one step lighter than the map's own established base tone,
 * #292D33, the same "subtle elevation over the ground plane" relationship
 * --card already has to --background elsewhere in this app).
 *
 * Per Mapbox's own documented setStyle() behavior (cited in the
 * MapLibre-migration plan report), a style *already containing* this
 * layer survives setStyle() fine when switching *back* to Operations —
 * what doesn't survive is a layer added imperatively via map.addLayer()
 * after the fact. Since the retint lives in the style JSON itself, not
 * added imperatively, no re-add-after-setStyle effect is actually needed
 * for the color — this function exists only as a defensive re-assert in
 * case a future edit ever adds the layer imperatively instead, and is
 * cheap enough (one setPaintProperty call, no-op if already correct) to
 * keep as a safety net.
 */
function reapplyBuildingRetint(map) {
  if (!map.getLayer(BUILDING_LAYER_ID)) {
    return
  }
  map.setPaintProperty(BUILDING_LAYER_ID, 'fill-color', '#343941')
  map.setPaintProperty(BUILDING_LAYER_ID, 'fill-outline-color', '#1a1d22')
}

/**
 * A plain colored dot rendered as real JSX now (previously an HTML
 * string fed to Leaflet's L.divIcon) — same color/size/border/glow logic
 * as before, unchanged, just expressed as inline style instead of a
 * template string.
 *
 * Map-visual-language polish pass (pre-migration, still true): unselected
 * markers get a small colorless drop-shadow (depth/contrast against the
 * tile only, not a status-colored halo) and a dimmer border; the halo/
 * glow treatment is reserved entirely for the one selected marker.
 */
function IncidentMarkerDot({ status, isSelected }) {
  const color = STATUS_COLORS[status] ?? '#8a93a6'
  const size = isSelected ? 20 : 12

  const border = isSelected ? '2px solid rgba(255,255,255,0.95)' : '1.5px solid rgba(255,255,255,0.6)'
  const boxShadow = isSelected
    ? `0 0 0 3px rgba(255,255,255,0.95), 0 0 0 6px ${color}, 0 0 14px 4px ${color}80`
    : '0 1px 3px rgba(0,0,0,0.65)'

  return (
    <span
      style={{
        display: 'block',
        width: size,
        height: size,
        borderRadius: 9999,
        background: color,
        border,
        boxShadow,
      }}
    />
  )
}

/**
 * Whole-set overview fit — but only while nothing is selected, and only
 * once the map/style has actually finished loading (a real, MapLibre-
 * specific requirement the Leaflet version never needed: react-leaflet's
 * useMap() only ever handed children a fully-initialized map instance by
 * construction, whereas this app's own map/Map.jsx exposes `isLoaded`
 * explicitly and calling camera methods before the style is ready is not
 * something to rely on working). A dispatcher reviewing one incident
 * owns the map's view; a new incident streaming in elsewhere (or any
 * other incident's status changing) must never yank the camera away to
 * fit the whole board around it. FocusSelectedIncident below is the sole
 * authority over the view whenever a selection exists; this effect
 * stands down entirely rather than racing it.
 *
 * The dependency is the *set of incident ids*, not the incidents array
 * itself — the array is a fresh reference on every status update even
 * though nothing about which incidents exist or where they are actually
 * changed, and re-fitting the camera on every one of those would be its
 * own kind of unwanted disruption while the dispatcher is just watching
 * the overview.
 */
function FitToIncidents({ incidents, selectedIncidentId }) {
  const { map, isLoaded } = useMap()
  const incidentsKey = useMemo(
    () => incidents.map((incident) => incident.incident_id).sort().join(','),
    [incidents]
  )

  useEffect(() => {
    if (!map || !isLoaded) {
      return
    }

    if (selectedIncidentId) {
      return
    }

    if (incidents.length === 0) {
      return
    }

    if (incidents.length === 1) {
      map.jumpTo({ center: [incidents[0].longitude, incidents[0].latitude], zoom: INCIDENT_CONTEXT_ZOOM })
      return
    }

    const lngs = incidents.map((incident) => incident.longitude)
    const lats = incidents.map((incident) => incident.latitude)
    const bounds = [
      [Math.min(...lngs), Math.min(...lats)],
      [Math.max(...lngs), Math.max(...lats)],
    ]
    // Capped at INCIDENT_CONTEXT_ZOOM — without this, several incidents
    // clustered close together can make fitBounds zoom in as far as the
    // map allows, defeating the overview's own purpose. animate: false
    // matches the pre-migration Leaflet fitBounds' own instant (not
    // eased) behavior — this is the calm "board overview" fit, not a
    // deliberate dispatcher-triggered focus.
    map.fitBounds(bounds, { padding: 32, maxZoom: INCIDENT_CONTEXT_ZOOM, animate: false })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- incidentsKey (a stable id-set string) is the real dependency; `incidents` itself is read from the latest closure, not tracked, so a same-set reference change (a status update) doesn't re-fit the camera.
  }, [incidentsKey, selectedIncidentId, map, isLoaded])

  return null
}

/**
 * Selecting an incident from the queue flies the map to it — a
 * deliberate second effect, independent of FitToIncidents, using flyTo
 * (smooth, since the map is persistent and shared, not remounted per
 * incident) rather than an abrupt jump.
 *
 * If the incident is already inside the current view at a context-or-
 * deeper zoom, this is a no-op (no animation at all) — the dispatcher
 * can already see it. Otherwise it flies to exactly INCIDENT_CONTEXT_ZOOM
 * (never deeper), unless they're already zoomed in further, in which
 * case that deeper zoom is preserved — never a "dramatic" zoom past what
 * they chose.
 */
function FocusSelectedIncident({ incidents, selectedIncidentId }) {
  const { map, isLoaded } = useMap()

  useEffect(() => {
    if (!map || !isLoaded) {
      return
    }

    if (!selectedIncidentId) {
      return
    }

    const incident = incidents.find((candidate) => candidate.incident_id === selectedIncidentId)
    if (!incident) {
      return
    }

    const target = [incident.longitude, incident.latitude]
    const currentZoom = map.getZoom()
    const alreadyInContext = currentZoom >= INCIDENT_CONTEXT_ZOOM && map.getBounds().contains(target)
    if (alreadyInContext) {
      return
    }

    map.flyTo({ center: target, zoom: Math.max(currentZoom, INCIDENT_CONTEXT_ZOOM), duration: 600 })
  }, [selectedIncidentId, incidents, map, isLoaded])

  return null
}

/**
 * Re-applies the buildings retint whenever the style finishes (re)loading
 * on Operations — see reapplyBuildingRetint's own comment for why this is
 * a defensive safety net rather than a load-bearing requirement: the
 * retint already lives inside operationsBasemapStyle.json itself, so it
 * survives setStyle() on its own. This effect exists so that claim is
 * actually exercised and verified across real Operations<->Satellite
 * switches, not just assumed from reading Mapbox's setStyle() docs.
 */
function BuildingRetintGuard({ activeLayer }) {
  const { map, isLoaded } = useMap()

  useEffect(() => {
    if (!map || !isLoaded || activeLayer !== 'operations') {
      return
    }
    reapplyBuildingRetint(map)
  }, [map, isLoaded, activeLayer])

  return null
}

/**
 * Compact two-option layer toggle — unchanged in UI/UX from the
 * pre-migration version; now drives which MapLibre style object is
 * passed to <Map style=...> instead of a Leaflet <TileLayer> ternary.
 * Reuses the same segmented-pill pattern IncidentFilterStrip already
 * established for "pick one of a few options." Stacked directly above
 * the zoom control (bottom-right) — the one corner already reserved for
 * map-navigation chrome.
 */
function LayerToggle({ activeLayer, onChange, panelOpen }) {
  return (
    <div
      className={cn(
        'absolute bottom-[6.5rem] z-[1000] flex flex-col gap-0.5 rounded-lg border border-border bg-popover/90 p-1 shadow-elevation-2 backdrop-blur transition-[right] duration-200',
        panelOpen ? 'right-[26.875rem]' : 'right-3.5'
      )}
      role="group"
      aria-label="Map layer"
    >
      {[
        { key: 'operations', label: 'Operations' },
        { key: 'satellite', label: 'Satellite' },
      ].map((layer) => (
        <button
          key={layer.key}
          type="button"
          onClick={() => onChange(layer.key)}
          aria-pressed={activeLayer === layer.key}
          className={cn(
            'rounded-md px-2.5 py-1.5 text-left text-xs whitespace-nowrap transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:scale-95',
            activeLayer === layer.key
              ? 'bg-accent text-accent-foreground'
              : 'text-muted-foreground hover:text-foreground'
          )}
        >
          {layer.label}
        </button>
      ))}
    </div>
  )
}

/**
 * Zoom +/- control — MapLibre has no built-in equivalent to Leaflet's
 * <ZoomControl>, so this is a small first-party replacement, styled
 * consistently with the rest of SENTRI's dark chrome (matching
 * .leaflet-control-zoom's own theming from before the migration) rather
 * than MapLibre GL's own default NavigationControl look. Positioned
 * bottom-right for the same reason the Leaflet version was: the one
 * corner nothing else docks to, shifted left via `panelOpen` exactly
 * like LayerToggle when the detail panel covers it.
 */
function ZoomControl({ panelOpen }) {
  const { map } = useMap()
  const [zoom, setZoom] = useState(null)

  useEffect(() => {
    if (!map) {
      return
    }
    const updateZoom = () => setZoom(map.getZoom())
    updateZoom()
    map.on('zoom', updateZoom)
    return () => map.off('zoom', updateZoom)
  }, [map])

  if (!map) {
    return null
  }

  // Disabled state at the zoom floor/ceiling — Leaflet's native
  // <ZoomControl> (removed in the MapLibre migration) already had this;
  // preserved here rather than silently dropped, and it doubles as a
  // real, DOM-observable signal (no debug-only API needed) for anything
  // that needs to confirm "zoom is at the ceiling" — e.g. the permanent
  // Playwright suite's own zoom-persistence check.
  const atMinZoom = zoom !== null && zoom <= MIN_ZOOM
  const atMaxZoom = zoom !== null && zoom >= MAP_MAX_ZOOM

  return (
    <div
      className={cn(
        'absolute bottom-3.5 z-[1000] flex flex-col overflow-hidden rounded-md border border-border shadow-elevation-2 transition-[right] duration-200',
        panelOpen ? 'right-[26.875rem]' : 'right-3.5'
      )}
    >
      <button
        type="button"
        aria-label="Zoom in"
        aria-disabled={atMaxZoom}
        disabled={atMaxZoom}
        onClick={() => map.zoomIn()}
        className="flex size-8 items-center justify-center border-b border-border bg-popover text-lg text-popover-foreground transition-colors hover:bg-muted active:bg-accent disabled:pointer-events-none disabled:opacity-40"
      >
        +
      </button>
      <button
        type="button"
        aria-label="Zoom out"
        aria-disabled={atMinZoom}
        disabled={atMinZoom}
        onClick={() => map.zoomOut()}
        className="flex size-8 items-center justify-center bg-popover text-lg text-popover-foreground transition-colors hover:bg-muted active:bg-accent disabled:pointer-events-none disabled:opacity-40"
      >
        &minus;
      </button>
    </div>
  )
}

export function IncidentMap({ incidents, onSelectIncident, selectedIncidentId = null }) {
  const [activeLayer, setActiveLayer] = useState('operations')
  const panelOpen = selectedIncidentId !== null
  const style = activeLayer === 'operations' ? operationsBasemapStyle : SATELLITE_STYLE

  return (
    <div className="relative h-full w-full">
      <Map
        style={style}
        center={DEFAULT_CENTER}
        zoom={OVERVIEW_ZOOM}
        minZoom={MIN_ZOOM}
        maxZoom={MAP_MAX_ZOOM}
        maxBounds={TAGUM_AREA_MAX_BOUNDS}
        className="h-full w-full"
      >
        <FitToIncidents incidents={incidents} selectedIncidentId={selectedIncidentId} />
        <FocusSelectedIncident incidents={incidents} selectedIncidentId={selectedIncidentId} />
        <BuildingRetintGuard activeLayer={activeLayer} />
        <ZoomControl panelOpen={panelOpen} />

        {incidents.map((incident) => {
          const isSelected = incident.incident_id === selectedIncidentId
          return (
            <MapMarker
              key={incident.incident_id}
              longitude={incident.longitude}
              latitude={incident.latitude}
              anchor="center"
              zIndex={isSelected ? 1000 : 0}
              onClick={onSelectIncident ? () => onSelectIncident(incident.incident_id) : undefined}
            >
              <MarkerContent>
                <IncidentMarkerDot status={incident.status} isSelected={isSelected} />
              </MarkerContent>
              <MarkerTooltip className="border border-border bg-popover text-popover-foreground shadow-elevation-2">
                <MarkerHoverCard incident={incident} />
              </MarkerTooltip>
            </MapMarker>
          )
        })}
      </Map>

      <LayerToggle activeLayer={activeLayer} onChange={setActiveLayer} panelOpen={panelOpen} />
    </div>
  )
}
