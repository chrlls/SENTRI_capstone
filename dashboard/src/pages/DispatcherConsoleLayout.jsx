import { useCallback, useEffect, useMemo, useState } from 'react'
import { Outlet, useMatch, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Alert, AlertAction, AlertDescription } from '@/components/ui/alert'
import { DispatcherCornerControls } from '@/components/DispatcherCornerControls'
import { IncidentQueue } from '@/components/IncidentQueue'
import { IncidentFilterStrip } from '@/components/IncidentFilterStrip'
import { IncidentMap } from '@/components/IncidentMap'
import { useIncidentStream } from '@/hooks/useIncidentStream'
import { ApiError, fetchIncidents, normalizeStreamedIncident } from '@/lib/api'
import { filterIncidentsByKey } from '@/lib/incidentStatus'

/**
 * Error only — the loading state lives inside IncidentQueue itself now
 * (its own "Loading queue…" header), not a separate floating banner.
 * Confirmed via a real screenshot that having both at once was not just
 * redundant but actively misleading: IncidentQueue's list defaults an
 * unresolved `incidents` fetch to `[]`, so its old "All clear" empty
 * state and this banner's "Loading incidents…" could both be on screen
 * simultaneously, asserting two different things about the same not-yet-
 * known data.
 */
function QueueErrorBanner({ error, onRetry }) {
  if (error === null) {
    return null
  }

  return (
    <div className="absolute top-3.5 left-[19rem] z-20 max-w-xs">
      <Alert variant="destructive" className="shadow-elevation-2">
        <AlertDescription>{error}</AlertDescription>
        <AlertAction>
          <Button variant="outline" size="sm" onClick={onRetry}>
            Retry
          </Button>
        </AlertAction>
      </Alert>
    </div>
  )
}

/**
 * Persistent-queue architecture (dispatcher-console redesign): the map,
 * corner controls, queue, and filter strip live here exactly once, for
 * the lifetime of the authenticated session — not remounted when an
 * incident's detail opens/closes. IncidentDetailRoute (rendered via the
 * nested <Outlet/> below) owns only what's specific to one incident.
 */
export function DispatcherConsoleLayout() {
  const navigate = useNavigate()
  // null = initial load in flight; [] is a real, already-loaded empty queue.
  const [incidents, setIncidents] = useState(null)
  const [error, setError] = useState(null)
  const [activeFilter, setActiveFilter] = useState('all')

  // Bumped by the Retry button to re-run the effect below on demand,
  // rather than the effect calling a separately-defined fetch function
  // (react-hooks/set-state-in-effect flags that shape).
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let cancelled = false

    fetchIncidents()
      .then((data) => {
        if (!cancelled) {
          setError(null)
          setIncidents(data)
        }
      })
      .catch((err) => {
        if (cancelled) {
          return
        }
        if (err instanceof ApiError && err.status === 401) {
          navigate('/login', { replace: true })
          return
        }
        setError(err instanceof ApiError ? err.message : 'Unable to reach the server. Check your connection and try again.')
        setIncidents((current) => current ?? [])
      })

    return () => {
      cancelled = true
    }
  }, [reloadKey, navigate])

  const handleNewIncident = useCallback((incident) => {
    setIncidents((current) => {
      const base = current ?? []
      if (base.some((existing) => existing.incident_id === incident.incident_id)) {
        return base
      }
      return [normalizeStreamedIncident(incident), ...base]
    })
  }, [])

  useIncidentStream(handleNewIncident)

  // Persists a status-PATCH response into the list living here (not just
  // the detail route's own local state) — the queue row and map marker
  // color need to update immediately without a re-fetch.
  const handleIncidentUpdated = useCallback((incidentId, patch) => {
    setIncidents((current) => (current ?? []).map((incident) => (
      incident.incident_id === incidentId ? { ...incident, ...patch } : incident
    )))
  }, [])

  const handleSelectIncident = (id) => navigate(`/incidents/${id}`)

  // Which incident's detail is currently open, derived from the route
  // itself (not a second, desyncable piece of state) — this layout's own
  // route ("/") has no :id segment, only its nested child does, so
  // useMatch reads the current location regardless of this component's
  // own depth in the tree.
  const detailMatch = useMatch('/incidents/:id')
  const selectedIncidentId = detailMatch?.params.id ?? null

  // Both memoized on [incidents] specifically (not a plain `incidents ?? []`
  // literal) — required, not optional: once the map/queue are persistent,
  // this layout re-renders for reasons unrelated to the incident set (e.g.
  // selecting a different incident changes the matched route). A `[]`
  // fallback literal or a fresh `.filter()` result on every such render
  // would refire IncidentMap's FitToIncidents effect and yank the
  // dispatcher's pan/zoom for no real reason.
  const list = useMemo(() => incidents ?? [], [incidents])
  const visibleIncidents = useMemo(() => filterIncidentsByKey(list, activeFilter), [list, activeFilter])

  return (
    <div className="relative h-svh w-full overflow-hidden bg-background">
      {/* `isolate` forces a new stacking context here — without it, the
          map's own internal layers (MapLibre's WebGL canvas plus its
          DOM-based marker/tooltip/control elements, which this app's own
          map/Map.jsx and IncidentMap.jsx give z-index up to 1000) have no
          containing stacking context of their own and are compared
          directly against this page's z-10/z-20 overlay controls below,
          so the opaque canvas layer paints over all of them. The nested
          <Outlet/> below (the detail panel) must stay a sibling after this
          div, never nested inside it, for the same reason. */}
      <div className="absolute inset-0 isolate">
        <IncidentMap incidents={visibleIncidents} onSelectIncident={handleSelectIncident} selectedIncidentId={selectedIncidentId} />
      </div>

      <IncidentQueue
        incidents={list}
        loading={incidents === null}
        selectedIncidentId={selectedIncidentId}
        onSelectIncident={handleSelectIncident}
      />

      <QueueErrorBanner error={error} onRetry={() => setReloadKey((key) => key + 1)} />

      <DispatcherCornerControls />

      <IncidentFilterStrip incidents={list} activeFilter={activeFilter} onFilterChange={setActiveFilter} />

      <Outlet context={{ incidents: list, onIncidentUpdated: handleIncidentUpdated }} />
    </div>
  )
}
