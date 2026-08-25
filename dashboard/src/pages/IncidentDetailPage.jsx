import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, SearchX } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { DispatcherHeader } from '@/components/DispatcherHeader'
import { IncidentMap } from '@/components/IncidentMap'
import { ApiError, fetchIncident } from '@/lib/api'
import { humanizeEnum } from '@/lib/utils'

function Field({ label, children }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-sm text-foreground">{children ?? '—'}</dd>
    </div>
  )
}

function DetailLoadingState() {
  return (
    <div className="grid grid-cols-2 gap-4 p-6">
      {[0, 1, 2, 3, 4, 5].map((i) => (
        <Skeleton key={i} className="h-10 w-full" />
      ))}
    </div>
  )
}

function DetailNotFoundState() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 py-24 text-center">
      <SearchX className="size-6 text-muted-foreground" />
      <p className="text-sm font-medium text-foreground">Incident not found</p>
      <p className="max-w-xs text-xs text-muted-foreground">
        This incident doesn't exist, or isn't available to your account.
      </p>
    </div>
  )
}

function DetailErrorState({ message }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 py-24 text-center">
      <p className="text-sm font-medium text-destructive">{message}</p>
    </div>
  )
}

function AiClassificationSection({ classification }) {
  if (classification === null) {
    return (
      <section>
        <h3 className="mb-2 text-xs font-medium tracking-wide text-muted-foreground uppercase">AI Classification</h3>
        <p className="text-sm text-muted-foreground">No completed classification for this incident.</p>
      </section>
    )
  }

  return (
    <section>
      <h3 className="mb-2 text-xs font-medium tracking-wide text-muted-foreground uppercase">AI Classification</h3>
      <dl className="grid grid-cols-2 gap-4">
        <Field label="Distress detected">{classification.distress_label ? 'Yes' : 'No'}</Field>
        <Field label="Confidence">{(classification.distress_confidence * 100).toFixed(1)}%</Field>
        <Field label="Model version">{classification.model_version}</Field>
        <Field label="Analyzed at">{classification.analyzed_at}</Field>
        <Field label="Audio reference">
          <span className="font-mono text-xs break-all">{classification.audio_storage_ref}</span>
        </Field>
      </dl>
    </section>
  )
}

function NotificationsSection({ notifications }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-medium tracking-wide text-muted-foreground uppercase">Notifications</h3>
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-between rounded-md bg-muted/40 px-3 py-2 text-sm">
          <span className="text-foreground">PNP Dashboard</span>
          {notifications.pnp_dashboard === null ? (
            <span className="text-xs text-muted-foreground">not created</span>
          ) : (
            <Badge variant="outline">{humanizeEnum(notifications.pnp_dashboard.delivery_status)}</Badge>
          )}
        </div>

        {notifications.barangay_tanod.length === 0 ? (
          <p className="text-xs text-muted-foreground">No responders were matched/notified for this incident.</p>
        ) : (
          notifications.barangay_tanod.map((n) => (
            <div key={n.notification_id} className="flex items-center justify-between rounded-md bg-muted/40 px-3 py-2 text-sm">
              <div className="flex flex-col">
                <span className="text-foreground">{n.full_name}</span>
                <span className="text-xs text-muted-foreground">
                  {n.distance_meters === null ? 'distance unknown' : `${n.distance_meters.toFixed(0)} m away`}
                </span>
              </div>
              <Badge variant="outline">{humanizeEnum(n.delivery_status)}</Badge>
            </div>
          ))
        )}
      </div>
    </section>
  )
}

function IncidentDetailContent({ incident }) {
  return (
    <div className="flex flex-1 overflow-hidden">
      <div className="flex w-[26rem] shrink-0 flex-col gap-6 overflow-y-auto border-r border-border p-6">
        <div className="flex items-center gap-2">
          <Badge variant="destructive">{humanizeEnum(incident.status)}</Badge>
          <span className="text-sm text-muted-foreground">{humanizeEnum(incident.trigger_source)}</span>
        </div>

        <dl className="grid grid-cols-2 gap-4">
          <Field label="Incident ID">
            <span className="font-mono text-xs break-all">{incident.incident_id}</span>
          </Field>
          <Field label="Reporter ID">
            <span className="font-mono text-xs break-all">{incident.reporter_id}</span>
          </Field>
          <Field label="Location">
            {incident.latitude.toFixed(5)}, {incident.longitude.toFixed(5)}
          </Field>
          <Field label="Barangay">
            {incident.incident_barangay_id ?? 'Unresolved (outside known boundaries)'}
          </Field>
          <Field label="Location captured at">{incident.location_captured_at}</Field>
          <Field label="AI confidence score">
            {incident.ai_confidence_score === null ? null : `${(incident.ai_confidence_score * 100).toFixed(1)}%`}
          </Field>
          <Field label="Dispatched by">{incident.dispatched_by}</Field>
          <Field label="Dispatched at">{incident.dispatched_at}</Field>
          <Field label="Created at">{incident.created_at}</Field>
          <Field label="Updated at">{incident.updated_at}</Field>
          <Field label="Resolved at">{incident.resolved_at}</Field>
        </dl>

        <Field label="Dispatcher notes">{incident.dispatcher_notes}</Field>
        <Field label="Incident notes">{incident.incident_notes}</Field>

        <AiClassificationSection classification={incident.ai_classification} />
        <NotificationsSection notifications={incident.notifications} />
      </div>

      <main className="flex-1">
        <IncidentMap incidents={[incident]} />
      </main>
    </div>
  )
}

export function IncidentDetailPage() {
  const { id } = useParams()
  // Keyed by id so navigating between two incidents remounts this loader
  // with fresh initial state, instead of an effect resetting state
  // synchronously on id change (react-hooks/set-state-in-effect flags that).
  return <IncidentDetailLoader key={id} id={id} />
}

function IncidentDetailLoader({ id }) {
  const navigate = useNavigate()
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

  return (
    <div className="flex h-svh flex-col bg-background">
      <DispatcherHeader />
      <div className="flex items-center gap-2 border-b border-border px-4 py-2">
        <Button variant="ghost" size="sm" onClick={() => navigate('/')}>
          <ArrowLeft /> Back to queue
        </Button>
      </div>

      {incident === null && !notFound && error === null && <DetailLoadingState />}
      {notFound && <DetailNotFoundState />}
      {error !== null && <DetailErrorState message={error} />}
      {incident !== null && <IncidentDetailContent incident={incident} />}
    </div>
  )
}
