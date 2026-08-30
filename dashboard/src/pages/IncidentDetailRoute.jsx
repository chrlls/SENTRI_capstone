import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useOutletContext, useParams } from 'react-router-dom'
import { Loader2, SearchX, X } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { IncidentDetailPanel } from '@/components/IncidentDetailPanel'
import { ApiError, fetchIncident } from '@/lib/api'

/**
 * Loading/not-found/error state for this route, rendered in the same
 * right-side panel slot the real detail panel would occupy — deliberately
 * NOT the shared top-left QueueStatusBanner position DispatcherConsoleLayout
 * uses for the list fetch. A direct `/incidents/:id` page load now fires
 * both fetches at once (the persistent layout's list fetch and this
 * route's own incident fetch), which never happened when these were
 * separate pages; reusing one banner position would visually collide.
 */
function DetailPanelStatus({ loading, notFound, error, onClose }) {
  return (
    <aside className="detail-panel absolute inset-y-0 right-0 z-20 flex w-[26rem] max-w-full flex-col items-center justify-center border-l border-border bg-background shadow-elevation-3">
      <button
        type="button"
        onClick={onClose}
        aria-label="Close and return to queue"
        className="absolute top-3.5 right-3.5 z-10 flex size-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        <X className="size-4" />
      </button>

      {loading && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="size-4 animate-spin" />
          Loading incident…
        </div>
      )}

      {notFound && (
        <div className="flex flex-col items-center gap-2 px-6 text-center">
          <SearchX className="size-6 text-muted-foreground" />
          <p className="text-sm font-medium text-foreground">Incident not found</p>
          <p className="max-w-xs text-xs text-muted-foreground">
            This incident doesn't exist, or isn't available to your account.
          </p>
        </div>
      )}

      {error !== null && (
        <div className="px-6">
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        </div>
      )}
    </aside>
  )
}

export function IncidentDetailRoute() {
  const { id } = useParams()
  // Keyed by id so navigating between two incidents remounts this loader
  // with fresh initial state, instead of an effect resetting state
  // synchronously on id change (react-hooks/set-state-in-effect flags that).
  return <IncidentDetailLoader key={id} id={id} />
}

function IncidentDetailLoader({ id }) {
  const navigate = useNavigate()
  const { onIncidentUpdated } = useOutletContext()
  // null = loading; distinct from notFound/error, which are terminal states.
  const [incident, setIncident] = useState(null)
  const [notFound, setNotFound] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false

    fetchIncident(id)
      .then((data) => {
        if (!cancelled) {
          setIncident(data)
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
        if (err instanceof ApiError && err.status === 404) {
          setNotFound(true)
          return
        }
        setError(err instanceof ApiError ? err.message : 'Unable to reach the server. Check your connection and try again.')
      })

    return () => {
      cancelled = true
    }
  }, [id, navigate])

  // The PATCH response is the narrower read-endpoint summary shape (per
  // API_CONTRACTS.md), not the full detail shape this page already holds
  // (it has no ai_classification/reporter/keyword_matches/status_history/
  // notifications/location_captured_at/incident_notes) — merge rather than
  // replace, or those sections would go blank after the first status change.
  // Also syncs the change up to DispatcherConsoleLayout's own list (new,
  // persistent-queue architecture) so the queue row and map marker color
  // update immediately.
  const handleUpdated = useCallback((updated) => {
    setIncident((current) => ({ ...current, ...updated }))
    onIncidentUpdated(id, updated)
  }, [id, onIncidentUpdated])

  const handleClose = () => navigate('/')

  if (incident === null && !notFound && error === null) {
    return <DetailPanelStatus loading notFound={false} error={null} onClose={handleClose} />
  }

  if (notFound) {
    return <DetailPanelStatus loading={false} notFound error={null} onClose={handleClose} />
  }

  if (error !== null) {
    return <DetailPanelStatus loading={false} notFound={false} error={error} onClose={handleClose} />
  }

  return <IncidentDetailPanel incident={incident} onUpdated={handleUpdated} onClose={handleClose} />
}
