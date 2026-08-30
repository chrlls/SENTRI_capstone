import { Bell, MapPin, UserRound, X } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import { IncidentStatusActions } from '@/components/IncidentStatusActions'
import { AudioEvidencePlayer } from '@/components/AudioEvidencePlayer'
import { useElapsedSeconds } from '@/hooks/useElapsedSeconds'
import { formatElapsed, formatManilaTime, humanizeEnum, cn } from '@/lib/utils'
import { needsReview, statusBadgeVariant, verificationStateFor } from '@/lib/incidentStatus'
import { triggerSourceLabel } from '@/lib/triggerIcons'

function SectionTitle({ icon: Icon, children }) {
  return (
    <div className="flex items-center gap-1.5">
      {Icon && <Icon className="size-3.5 text-muted-foreground" />}
      <p className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">{children}</p>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-sm break-words text-foreground">{children ?? '—'}</dd>
    </div>
  )
}

function WhoSection({ reporter }) {
  return (
    <section className="flex flex-col gap-2">
      <SectionTitle icon={UserRound}>Who</SectionTitle>
      <dl className="grid grid-cols-2 gap-x-3 gap-y-2.5">
        <Field label="Reporter">{reporter.full_name}</Field>
        <Field label="Role">{humanizeEnum(reporter.role)}</Field>
      </dl>
    </section>
  )
}

/**
 * Coordinates are deliberately subordinate to the barangay name — a small
 * mono caption under it, not a same-weight field beside it — per the
 * detail-panel polish pass's own instruction not to overemphasize raw
 * coordinates. `break-words` on both (not `truncate`) so a long barangay
 * name or an unusually long formatted timestamp wraps within the panel's
 * fixed width instead of clipping.
 */
function WhereSection({ incident }) {
  return (
    <section className="flex flex-col gap-2">
      <SectionTitle icon={MapPin}>Where</SectionTitle>
      <dl className="flex flex-col gap-2.5">
        <div className="flex flex-col gap-0.5">
          <dt className="text-xs text-muted-foreground">Barangay</dt>
          <dd className="text-sm break-words text-foreground">
            {incident.barangay_name ?? 'Unresolved (outside known boundaries)'}
          </dd>
          <dd className="font-mono text-[10.5px] break-all text-muted-foreground/70">
            {incident.latitude.toFixed(5)}, {incident.longitude.toFixed(5)}
          </dd>
        </div>
        <Field label="Captured">{formatManilaTime(incident.location_captured_at)}</Field>
      </dl>
    </section>
  )
}

/**
 * The section closest to SENTRI's actual thesis (Decision 06 — dispatch
 * is always a human decision, AI never authorizes it), so it keeps its
 * own bounded card even though every other section in this panel is now
 * flat — that contrast is deliberate: Evidence is the one section besides
 * Decision genuinely operationally load-bearing, and standing out
 * visually from Who/Where/Incident Information is what signals that.
 *
 * Evidence-and-AI polish pass: Evidence now *always* renders, for both
 * trigger sources — a manual SOS was never analyzed by AI, and that
 * absence needs to read as an intentional, correct fact about this
 * report, not as an error/empty/loading state the way an omitted section
 * risked being misread. The two branches below are a hard content split,
 * not a styling difference: manual_sos gets a plain "Manual SOS / Not
 * applicable" statement; voice_distress gets the full recording-player +
 * AI-assessment hierarchy.
 *
 * Within a voice_distress incident: "Voice Recording" (the primary
 * artifact a dispatcher actually verifies against) → a visually separate,
 * clearly-labeled "AI Assessment" sub-block, bounded distinctly from the
 * player so it reads as a secondary annotation, not the headline of the
 * section → a closing line that AI assists verification and never
 * authorizes dispatch. Only fields the API actually returns
 * (distress_label, distress_confidence, model_version, analyzed_at) are
 * shown — no panic level, keyword/emotion category, risk score, or
 * inference-duration field exists in SENTRI's data model, so none is
 * invented here.
 */
function EvidenceSection({ incident }) {
  if (incident.trigger_source !== 'voice_distress') {
    return (
      <section className="flex flex-col gap-3 rounded-md border border-border bg-card/40 p-3.5">
        <SectionTitle>Evidence</SectionTitle>
        <p className="text-sm text-foreground">Manual SOS</p>

        <div className="flex flex-col gap-1 border-t border-border/60 pt-2.5">
          <p className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">AI Assessment</p>
          <p className="text-sm text-muted-foreground">Not applicable — manual SOS reports are not analyzed by AI.</p>
        </div>
      </section>
    )
  }

  if (incident.ai_classification === null) {
    // Per API_CONTRACTS.md: on the inconclusive path nothing is written to
    // disk or to voice_analysis_events at all — a null ai_classification
    // here means there is structurally no retained clip either, not just
    // no analysis. Rendering AudioEvidencePlayer anyway would always fail
    // (a real fetch that's guaranteed to 404), which reads as something
    // broke rather than as the honest, intentional "nothing was kept"
    // fact it actually is — so this stays one plain statement, not a
    // player that predictably errors.
    return (
      <section className="flex flex-col gap-2 rounded-md border border-border bg-card/40 p-3.5">
        <SectionTitle>Evidence</SectionTitle>
        <p className="text-xs text-muted-foreground">
          No classification available, and no audio clip was retained for this report. The report itself is
          unaffected and still requires the same human review.
        </p>
      </section>
    )
  }

  const { distress_label: distressLabel, distress_confidence: confidence, model_version: modelVersion, analyzed_at: analyzedAt } =
    incident.ai_classification
  const confidencePct = Math.round(confidence * 100)
  const isHighConfidence = confidence >= 0.7

  return (
    <section className="flex flex-col gap-3 rounded-md border border-border bg-card/40 p-3.5">
      <SectionTitle>Evidence</SectionTitle>

      <div className="flex flex-col gap-1.5">
        <p className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">Voice Recording</p>
        <AudioEvidencePlayer incidentId={incident.incident_id} />
      </div>

      {/* premium-finish polish pass: this used to be its own bordered,
          backgrounded box nested inside the Evidence card — a real "card
          inside card" the pass calls out directly. A top divider (matching
          every other sub-section split in this panel) carries the same
          "this is a distinct sub-group" signal without a second boundary. */}
      <div className="flex flex-col gap-2 border-t border-border/60 pt-2.5">
        <p className="text-[10.5px] font-semibold tracking-wide text-muted-foreground uppercase">AI Assessment</p>

        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Distress label</span>
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
              : 'Lower confidence — treat as a weaker signal alongside other context, not a standalone confirmation.'}
          </p>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Model version</span>
          <span className="font-mono text-xs text-foreground">{modelVersion}</span>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Analyzed at</span>
          <span className="text-xs text-foreground">{formatManilaTime(analyzedAt)}</span>
        </div>

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

      <p className="text-xs text-foreground">
        AI assists verification only. Final response decision is made by the dispatcher.
      </p>
    </section>
  )
}

function IncidentInformationSection({ incident }) {
  if (incident.dispatcher_notes === null && incident.incident_notes === null) {
    return null
  }

  return (
    <section className="flex flex-col gap-2">
      <SectionTitle>Incident Information</SectionTitle>
      <dl className="flex flex-col gap-2.5">
        {incident.dispatcher_notes !== null && <Field label="Dispatcher notes">{incident.dispatcher_notes}</Field>}
        {incident.incident_notes !== null && <Field label="Incident notes">{incident.incident_notes}</Field>}
      </dl>
    </section>
  )
}

function HistoryContent({ history }) {
  if (history.length === 0) {
    return <p className="text-[11px] text-muted-foreground">No status changes yet.</p>
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
        <p className="text-[11px] text-muted-foreground">No responders were matched/notified for this incident.</p>
      ) : (
        notifications.barangay_tanod.map((n) => (
          <div
            key={n.notification_id}
            className="flex items-center justify-between rounded-md bg-muted/40 px-2.5 py-1.5 text-xs"
          >
            <div className="flex flex-col">
              <span className="text-foreground">{n.full_name}</span>
              <span className="text-[10.5px] text-muted-foreground">
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
 * detail-panel information-hierarchy polish pass: previously every
 * section (Who, Where, Notes, History/Notifications) was its own
 * same-weight bordered/shadowed card, and the action area (Decision) sat
 * right under the header — so the panel read as a stack of independent
 * forms rather than one incident record. Restructured around a single
 * conceptual flow instead: identity/status header → flat, divider-
 * separated read sections (Who, Where, Incident Information, History,
 * Notifications) → the one genuinely bounded Evidence card (operationally
 * load-bearing, per the same pass's own instruction) → the Decision area,
 * now last — a dispatcher reads the record top to bottom, then acts.
 * `divide-y` + `first:pt-0` on the flat-section wrapper gives consistent
 * spacing/dividers without every section needing its own border or
 * background.
 */
export function IncidentDetailPanel({ incident, onUpdated, onClose }) {
  const elapsed = useElapsedSeconds(incident.created_at)
  const hasIncidentInformation = incident.dispatcher_notes !== null || incident.incident_notes !== null
  const isUrgent = needsReview(incident.status)

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

      <div className="flex-1 overflow-y-auto p-4 pt-5">
        <header className="mb-5 flex flex-col gap-2.5 rounded-md border border-border bg-card/60 p-3.5 pr-8">
          <div className="flex items-center justify-between gap-2">
            <span className="font-mono text-[11px] text-muted-foreground">
              #{incident.incident_id.slice(0, 8)}
            </span>
            <span className="text-xs text-muted-foreground">{triggerSourceLabel(incident.trigger_source)}</span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={statusBadgeVariant(incident.status)}>{humanizeEnum(incident.status)}</Badge>
            <Badge variant="outline">{verificationStateFor(incident.status)}</Badge>
          </div>
          <div className="flex items-baseline gap-2">
            <span
              className={cn(
                'font-mono text-2xl font-semibold tabular-nums',
                isUrgent ? 'text-destructive' : 'text-foreground'
              )}
            >
              {elapsed === null ? '—' : formatElapsed(elapsed)}
            </span>
            <span className="text-xs text-muted-foreground">since detected</span>
          </div>
        </header>

        <div className="flex flex-col divide-y divide-border/60">
          <div className="pb-4">
            <WhoSection reporter={incident.reporter} />
          </div>

          <div className="py-4">
            <WhereSection incident={incident} />
          </div>

          <div className="py-4">
            <EvidenceSection incident={incident} />
          </div>

          {hasIncidentInformation && (
            <div className="py-4">
              <IncidentInformationSection incident={incident} />
            </div>
          )}

          <div className="py-4">
            <Accordion type="multiple">
              <AccordionItem value="history">
                <AccordionTrigger>
                  <span className="flex items-center gap-1.5 text-xs font-semibold text-foreground normal-case">
                    History
                  </span>
                </AccordionTrigger>
                <AccordionContent>
                  <HistoryContent history={incident.status_history} />
                </AccordionContent>
              </AccordionItem>
              <AccordionItem value="notifications">
                <AccordionTrigger>
                  <span className="flex items-center gap-1.5 text-xs font-semibold text-foreground normal-case">
                    <Bell className="size-3.5 text-muted-foreground" />
                    Notifications
                  </span>
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
