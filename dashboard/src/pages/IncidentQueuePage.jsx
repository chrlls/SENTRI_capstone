import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RadioTower } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DispatcherHeader } from '@/components/DispatcherHeader'
import { IncidentList } from '@/components/IncidentList'
import { IncidentMap } from '@/components/IncidentMap'
import { useIncidentStream } from '@/hooks/useIncidentStream'
import { ApiError, fetchIncidents, normalizeStreamedIncident } from '@/lib/api'

function QueueLoadingState() {
  return (
    <div className="flex flex-col gap-3 p-4">
      {[0, 1, 2].map((i) => (
        <div key={i} className="flex flex-col gap-2">
          <Skeleton className="h-4 w-20" />
          <Skeleton className="h-4 w-full" />
        </div>
      ))}
    </div>
  )
}

function QueueEmptyState() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 py-16 text-center">
      <RadioTower className="size-6 text-muted-foreground" />
      <p className="text-sm font-medium text-foreground">No active incidents</p>
      <p className="text-xs text-muted-foreground">The queue is clear. New alerts will appear here automatically.</p>
    </div>
  )
}

function QueueErrorState({ message, onRetry }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <p className="text-sm font-medium text-destructive">{message}</p>
      <Button variant="outline" size="sm" onClick={onRetry}>
        Retry
      </Button>
    </div>
  )
}

export function IncidentQueuePage() {
  const navigate = useNavigate()
  // null = initial load in flight; [] is a real, already-loaded empty queue.
  const [incidents, setIncidents] = useState(null)
  const [error, setError] = useState(null)

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

  const handleSelectIncident = (id) => navigate(`/incidents/${id}`)

  const list = incidents ?? []

  return (
    <div className="flex h-svh flex-col bg-background">
      <DispatcherHeader />
      <div className="flex flex-1 overflow-hidden">
        <aside className="flex w-96 shrink-0 flex-col overflow-hidden border-r border-border">
          <div className="border-b border-border px-4 py-3">
            <h2 className="text-sm font-medium text-foreground">Incident Queue</h2>
            <p className="text-xs text-muted-foreground">
              {incidents === null ? 'Loading…' : `${list.length} incident${list.length === 1 ? '' : 's'}`}
            </p>
          </div>

          <div className="flex flex-1 flex-col overflow-hidden">
            {incidents === null && <QueueLoadingState />}
            {incidents !== null && error !== null && (
              <QueueErrorState message={error} onRetry={() => setReloadKey((key) => key + 1)} />
            )}
            {incidents !== null && error === null && list.length === 0 && <QueueEmptyState />}
            {incidents !== null && error === null && list.length > 0 && (
              <IncidentList incidents={list} onSelectIncident={handleSelectIncident} />
            )}
          </div>
        </aside>

        <main className="flex-1">
          <IncidentMap incidents={list} onSelectIncident={handleSelectIncident} />
        </main>
      </div>
    </div>
  )
}
