import { X } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import { IncidentStatusActions } from '@/components/IncidentStatusActions'
import { AudioEvidencePlayer } from '@/components/AudioEvidencePlayer'
import { useElapsedSeconds } from '@/hooks/useElapsedSeconds'
import { formatElapsed, formatManilaTime, humanizeEnum, cn } from '@/lib/utils'
import { needsReview, statusBadgeVariant, verificationStateFor } from '@/lib/incidentStatus'
import { triggerIconElement, triggerSourceLabel } from '@/lib/triggerIcons'

/**
 * One heading treatment for the whole panel: quiet, sentence-case, no
 * icon. Separation between sections is carried by the `divide-y` rhythm,
 * not by a decorative glyph or a box around every group. The header's
 * trigger label is the panel's <h2>; every section below is an <h3>.
 */
function SectionHeading({ children }) {
  return <h3 className="text-xs font-semibold text-muted-foreground">{children}</h3>
}

function Field({ label, children }) {
  return (
    <div className="flex flex-col gap-1">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-sm break-words text-foreground">{children ?? '—'}</dd>
    </div>
  )
}

function WhoSection({ reporter }) {
  return (
    <section className="flex flex-col gap-2">
      <SectionHeading>Who</SectionHeading>
      <dl className="grid grid-cols-2 gap-x-3 gap-y-2">
        <Field label="Reporter">{reporter.full_name}</Field>
        <Field label="Role">{humanizeEnum(reporter.role)}</Field>
      </dl>
    </section>
  )
}

/**
 * Coordinates sit under the barangay name as a subordinate mono caption,
 * not a same-weight field beside it. `break-words` (not `truncate`) so a
 * long barangay name or formatted timestamp wraps within the panel's
 * fixed width instead of clipping.
 */
function WhereSection({ incident }) {
  return (
    <section className="flex flex-col gap-2">
      <SectionHeading>Where</SectionHeading>
      <dl className="flex flex-col gap-2">
        <div className="flex flex-col gap-1">
          <dt className="text-xs text-muted-foreground">Barangay</dt>
          <dd className="text-sm break-words text-foreground">
            {incident.barangay_name ?? 'Unresolved (outside known boundaries)'}
          </dd>
          <dd className="font-mono text-[11px] break-all text-muted-foreground">
            {incident.latitude.toFixed(5)}, {incident.longitude.toFixed(5)}
          </dd>
        </div>
        <Field label="Captured">{formatManilaTime(incident.location_captured_at)}</Field>
      </dl>
    </section>
  )
}

/**
 * AI is only ever part of a voice_distress report. A manual SOS is never
 * analyzed (Decision 05) and that absence is the normal, correct state —
 * so the call site omits this section entirely for a non-voice trigger
 * rather than captioning the absence; the header already says "Manual
 * SOS". Only fields the API actually returns are shown (distress_label,
 * distress_confidence, model_version, analyzed_at) — SENTRI's classifier
 * is binary (Decision 08), so there is no panic level, emotion category,
 * risk score, or inference-duration field to invent.
 */
function AiAssessmentSection({ incident }) {
  if (incident.ai_classification === null) {
    // On the inconclusive path nothing is written to disk or to
    // voice_analysis_events, so a null here also means no clip was kept —
    // rendering AudioEvidencePlayer would be a fetch guaranteed to 404.
    return (
      <section className="flex flex-col gap-2">
        <SectionHeading>AI assessment</SectionHeading>
        <p className="text-xs text-muted-foreground">
          No classification or audio was retained for this report. It still requires the same human review.
        </p>
      </section>
    )
  }

  const { distress_label: distressLabel, distress_confidence: confidence, model_version: modelVersion, analyzed_at: analyzedAt } =
    incident.ai_classification
  const confidencePct = Math.round(confidence * 100)
  const isHighConfidence = confidence >= 0.7

  return (
    <section className="flex flex-col gap-3">
      <SectionHeading>AI assessment</SectionHeading>

      <div className="flex flex-col gap-1.5">
        <p className="text-xs text-muted-foreground">Recording</p>
        <AudioEvidencePlayer incidentId={incident.incident_id} />
      </div>

      <div className="flex flex-col gap-2 border-t border-border/60 pt-3">
        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Distress</span>
          <span className="text-sm font-medium text-foreground">{distressLabel ? 'Detected' : 'Not detected'}</span>
        </div>

        <div className="flex flex-col gap-1.5">
          <div className="flex items-center justify-between">
            <span className="text-xs text-muted-foreground">Confidence</span>
            <span className="font-mono text-xs font-semibold text-purple-400">{confidencePct}%</span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-purple-500" style={{ width: `${confidencePct}%` }} />
          </div>
          <p className="text-[11px] text-muted-foreground">
            {isHighConfidence
              ? 'High confidence — the signal strongly suggests genuine distress.'
              : 'Lower confidence — weigh alongside other context, not as a standalone confirmation.'}
          </p>
        </div>

        <p className="font-mono text-[11px] text-muted-foreground">
          {modelVersion} · analyzed {formatManilaTime(analyzedAt)}
        </p>

        {incident.keyword_matches.length > 0 && (
          <div className="flex flex-wrap gap-1.5 border-t border-border/60 pt-2">
            {incident.keyword_matches.map((match) => (
              <span
                key={match.match_id}
                className="rounded bg-amber-500/15 px-1.5 py-0.5 text-[11px] font-medium text-amber-400"
              >
                “{match.matched_phrase}”
              </span>
            ))}
          </div>
        )}
      </div>
    </section>
  )
}

function NotesSection({ incident }) {
  return (
    <section className="flex flex-col gap-2">
      <SectionHeading>Notes</SectionHeading>
      <dl className="flex flex-col gap-2">
        {incident.dispatcher_notes !== null && <Field label="Dispatcher notes">{incident.dispatcher_notes}</Field>}
        {incident.incident_notes !== null && <Field label="Incident notes">{incident.incident_notes}</Field>}
      </dl>
    </section>
  )
}

function HistoryContent({ history }) {
  if (history.length === 0) {
    return <p className="text-xs text-muted-foreground">No status changes yet.</p>
  }

  return (
    <ol className="flex flex-col gap-2.5">
      {history.map((entry) => (
        <li key={entry.history_id} className="flex items-start gap-2 text-xs">
          <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-muted-foreground" />
          <div className="flex flex-col gap-0.5">
            <span className="text-foreground">
              {entry.old_status !== null && `${humanizeEnum(entry.old_status)} → `}
              {humanizeEnum(entry.new_status)}
            </span>
            <span className="text-muted-foreground">
              {entry.changed_by_name} · {formatManilaTime(entry.changed_at)}
            </span>
            {entry.reason !== null && <span className="text-muted-foreground italic">{entry.reason}</span>}
          </div>
        </li>
      ))}
    </ol>
  )
}

function NotificationsContent({ notifications }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between rounded-md bg-muted/40 px-2.5 py-1.5 text-xs">
        <span className="text-foreground">PNP Dashboard</span>
        {notifications.pnp_dashboard === null ? (
          <span className="text-muted-foreground">not created</span>
        ) : (
          <Badge variant="outline">{humanizeEnum(notifications.pnp_dashboard.delivery_status)}</Badge>
        )}
      </div>

      {notifications.barangay_tanod.length === 0 ? (
        <p className="text-xs text-muted-foreground">No responders were matched or notified for this incident.</p>
      ) : (
        notifications.barangay_tanod.map((n) => (
          <div
            key={n.notification_id}
            className="flex items-center justify-between rounded-md bg-muted/40 px-2.5 py-1.5 text-xs"
          >
            <div className="flex flex-col">
              <span className="text-foreground">{n.full_name}</span>
              <span className="text-[11px] text-muted-foreground">
                {n.distance_meters === null ? 'distance unknown' : `${n.distance_meters.toFixed(0)} m away`}
              </span>
            </div>
            <Badge variant="outline">{humanizeEnum(n.delivery_status)}</Badge>
          </div>
        ))
      )}
    </div>
  )
}

/**
 * The panel is one incident record read top to bottom, then acted on: a
 * flat identity/status header → divider-separated read sections (Who,
 * Where, AI assessment for voice reports, Notes, History, Notifications) →
 * the Decision area. Exactly one surface is elevated with a border and
 * fill — the Decision block — because that is the dispatcher's actual
 * task; every read section is separated by spacing and a hairline rule
 * alone, so nothing competes with it for attention.
 */
export function IncidentDetailPanel({ incident, onUpdated, onClose }) {
  const elapsed = useElapsedSeconds(incident.created_at)
  const isUrgent = needsReview(incident.status)
  const isVoiceReport = incident.trigger_source === 'voice_distress'
  const hasNotes = incident.dispatcher_notes !== null || incident.incident_notes !== null

  return (
    <aside className="detail-panel absolute inset-y-0 right-0 z-20 flex w-[26rem] max-w-full flex-col border-l border-border bg-background shadow-elevation-3">
      <button
        type="button"
        onClick={onClose}
        aria-label="Close and return to queue"
        className="absolute top-3.5 right-3.5 z-10 flex size-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:scale-95"
      >
        <X className="size-4" />
      </button>

      <div className="flex-1 overflow-y-auto p-4">
        <header className="flex flex-col gap-2 pb-4">
          <div className="flex items-center gap-2 pr-10">
            {triggerIconElement(incident.trigger_source, 'size-4 shrink-0 text-muted-foreground')}
            <h2 className="text-sm font-semibold text-foreground">{triggerSourceLabel(incident.trigger_source)}</h2>
            <span className="font-mono text-[11px] text-muted-foreground">#{incident.incident_id.slice(0, 8)}</span>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={statusBadgeVariant(incident.status)}>{humanizeEnum(incident.status)}</Badge>
            <span className="text-xs text-muted-foreground">{verificationStateFor(incident.status)}</span>
          </div>

          <div className="flex items-baseline gap-2">
            <span
              className={cn(
                'font-mono text-xl font-semibold tabular-nums',
                isUrgent ? 'text-destructive' : 'text-foreground'
              )}
            >
              {elapsed === null ? '—' : formatElapsed(elapsed)}
            </span>
            <span className="text-xs text-muted-foreground">since report</span>
          </div>
        </header>

        <div className="flex flex-col divide-y divide-border/60 border-t border-border/60">
          <div className="py-4">
            <WhoSection reporter={incident.reporter} />
          </div>

          <div className="py-4">
            <WhereSection incident={incident} />
          </div>

          {isVoiceReport && (
            <div className="py-4">
              <AiAssessmentSection incident={incident} />
            </div>
          )}

          {hasNotes && (
            <div className="py-4">
              <NotesSection incident={incident} />
            </div>
          )}

          <div className="py-4">
            {/* Radix AccordionTrigger is wrapped in an <h3> already, so the
                label is a plain span styled to match SectionHeading — no
                nested heading, no heading inside a button. */}
            <Accordion type="multiple">
              <AccordionItem value="history">
                <AccordionTrigger className="text-xs font-semibold text-muted-foreground">
                  History
                </AccordionTrigger>
                <AccordionContent>
                  <HistoryContent history={incident.status_history} />
                </AccordionContent>
              </AccordionItem>
              <AccordionItem value="notifications">
                <AccordionTrigger className="text-xs font-semibold text-muted-foreground">
                  Notifications
                </AccordionTrigger>
                <AccordionContent>
                  <NotificationsContent notifications={incident.notifications} />
                </AccordionContent>
              </AccordionItem>
            </Accordion>
          </div>
        </div>

        <div className="mt-4 rounded-md border border-border bg-card/40 p-3.5">
          <IncidentStatusActions incident={incident} onUpdated={onUpdated} />
        </div>
      </div>
    </aside>
  )
}
