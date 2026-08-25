<?php

namespace App\Http\Controllers;

use App\Actions\Incidents\ClassifyDistressAudio;
use App\Actions\Incidents\CreateAiAssistedSosIncident;
use App\Actions\Incidents\CreateManualSosIncident;
use App\Actions\Incidents\GetIncidentDetail;
use App\Actions\Incidents\ListIncidentsForUser;
use App\Actions\Incidents\MatchRespondersToIncident;
use App\Actions\Incidents\NotifyRespondersOfIncident;
use App\Actions\Incidents\RecordVoiceAnalysisEvent;
use App\Events\NewIncident;
use App\Http\Requests\AiAssistedSosRequest;
use App\Http\Requests\ManualSosRequest;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;
use Throwable;

class IncidentController extends Controller
{
    public function manualSos(
        ManualSosRequest $request,
        CreateManualSosIncident $action,
        MatchRespondersToIncident $matchResponders,
        NotifyRespondersOfIncident $notifyResponders,
    ): JsonResponse {
        // docs/decisions/21-role-based-authorization.md: civilian/responder
        // only, regardless of verification status. PNP/admin rejected with
        // 403 — a dispatcher-logged report is a separate, unbuilt endpoint.
        Gate::authorize('create-incident');

        $data = $request->validated();

        try {
            $incident = $action->handle(
                reporterId: $request->user()->user_id,
                latitude: $data['latitude'],
                longitude: $data['longitude'],
            );
        } catch (QueryException $e) {
            Log::error('Manual SOS incident insert failed', ['exception' => $e]);

            return response()->json([
                'error' => 'Failed to create incident.',
            ], 500);
        }

        // Incident already exists at this point — matching, notification,
        // and the dashboard broadcast are all downstream steps and must
        // never turn a created incident into a failed request
        // (docs/decisions/01, /05, /07, /25).
        $this->broadcastNewIncident($incident);
        $matchedResponders = $this->matchResponders($matchResponders, $incident->incident_id);
        $notifications = $this->notifyResponders($notifyResponders, $incident->incident_id, $matchedResponders['responders']);

        return response()->json([
            'incident_id' => $incident->incident_id,
            'reporter_id' => $incident->reporter_id,
            'trigger_source' => $incident->trigger_source,
            'status' => $incident->status,
            'incident_barangay_id' => $incident->incident_barangay_id,
            'latitude' => (float) $incident->latitude,
            'longitude' => (float) $incident->longitude,
            'created_at' => $incident->created_at,
            'matched_responders' => $matchedResponders,
            'notifications' => $notifications,
        ], 201);
    }

    public function aiAssistedSos(
        AiAssistedSosRequest $request,
        CreateAiAssistedSosIncident $createIncident,
        ClassifyDistressAudio $classify,
        RecordVoiceAnalysisEvent $recordEvent,
        MatchRespondersToIncident $matchResponders,
        NotifyRespondersOfIncident $notifyResponders,
    ): JsonResponse {
        Gate::authorize('create-incident');

        $data = $request->validated();

        try {
            $incident = $createIncident->handle(
                reporterId: $request->user()->user_id,
                latitude: $data['latitude'],
                longitude: $data['longitude'],
            );
        } catch (QueryException $e) {
            Log::error('AI-assisted SOS incident insert failed', ['exception' => $e]);

            return response()->json([
                'error' => 'Failed to create incident.',
            ], 500);
        }

        // Incident already exists at this point — nothing below this line
        // may cause the response to report anything other than success for
        // the incident itself (docs/decisions/05, /13). The dashboard
        // broadcast fires here too, same as manual-sos, before the AI call —
        // the dashboard shouldn't wait on classification to learn an
        // incident exists.
        $this->broadcastNewIncident($incident);
        $classification = $classify->handle($request->file('audio'));

        $aiClassification = ['status' => $classification['status']];

        if ($classification['status'] === 'completed') {
            try {
                $event = $recordEvent->handle(
                    incidentId: $incident->incident_id,
                    reporterId: $request->user()->user_id,
                    audio: $request->file('audio'),
                    distressLabel: $classification['distress_label'],
                    distressConfidence: $classification['distress_confidence'],
                    modelVersion: $classification['model_version'],
                );

                $aiClassification['distress_label'] = (bool) $event->distress_label;
                $aiClassification['distress_confidence'] = (float) $event->distress_confidence;
                $aiClassification['model_version'] = $event->model_version;
            } catch (Throwable $e) {
                Log::error('Failed to persist voice_analysis_events after a completed classification', [
                    'incident_id' => $incident->incident_id,
                    'exception' => $e,
                ]);

                $aiClassification = ['status' => 'inconclusive', 'reason' => 'storage_failed'];
            }
        } else {
            $aiClassification['reason'] = $classification['reason'];
        }

        // Matching and notification both run regardless of AI
        // classification outcome — they depend only on the incident's
        // location/barangay, not on distress detection, and must not be
        // blocked by an AI failure either (docs/decisions/01, /05, /07, /13).
        $matchedResponders = $this->matchResponders($matchResponders, $incident->incident_id);
        $notifications = $this->notifyResponders($notifyResponders, $incident->incident_id, $matchedResponders['responders']);

        return response()->json([
            'incident_id' => $incident->incident_id,
            'reporter_id' => $incident->reporter_id,
            'trigger_source' => $incident->trigger_source,
            'status' => $incident->status,
            'incident_barangay_id' => $incident->incident_barangay_id,
            'latitude' => (float) $incident->latitude,
            'longitude' => (float) $incident->longitude,
            'created_at' => $incident->created_at,
            'ai_classification' => $aiClassification,
            'matched_responders' => $matchedResponders,
            'notifications' => $notifications,
        ], 201);
    }

    /**
     * Listing is scoped entirely inside ListIncidentsForUser's queries per
     * docs/decisions/21-role-based-authorization.md — every role can call
     * this endpoint, they just each see a different, already-restricted
     * result set. There is no "cannot list at all" case (unlike incident
     * creation), so no Gate check is needed here.
     */
    public function index(Request $request, ListIncidentsForUser $action): JsonResponse
    {
        $incidents = $action->handle($request->user());

        return response()->json([
            'incidents' => array_map($this->formatSummary(...), $incidents),
        ], 200);
    }

    /**
     * A civilian/responder requesting an incident outside their
     * Decision-21 scope gets the same 404 as a nonexistent incident_id —
     * chosen over 403 so an unauthorized caller can't distinguish "this
     * incident doesn't exist" from "it exists but isn't yours," which would
     * otherwise leak whether someone else has an active SOS report.
     */
    public function show(string $incidentId, Request $request, GetIncidentDetail $action): JsonResponse
    {
        $incident = $action->find($incidentId);

        if ($incident === null || Gate::denies('view-incident', $incident)) {
            return response()->json(['error' => 'Incident not found.'], 404);
        }

        $classification = $action->classification($incident->incident_id);
        $notifications = $action->notifications($incident->incident_id);

        return response()->json([
            ...$this->formatSummary($incident),
            'location_captured_at' => $incident->location_captured_at,
            'dispatcher_notes' => $incident->dispatcher_notes,
            'incident_notes' => $incident->incident_notes,
            'ai_classification' => $classification === null ? null : [
                'distress_label' => (bool) $classification->distress_label,
                'distress_confidence' => (float) $classification->distress_confidence,
                'model_version' => $classification->model_version,
                'audio_storage_ref' => $classification->audio_storage_ref,
                'analyzed_at' => $classification->analyzed_at,
            ],
            'notifications' => [
                'pnp_dashboard' => $notifications['pnp_dashboard'] === null ? null : [
                    'notification_id' => $notifications['pnp_dashboard']->notification_id,
                    'delivery_status' => $notifications['pnp_dashboard']->delivery_status,
                    'created_at' => $notifications['pnp_dashboard']->created_at,
                ],
                'barangay_tanod' => array_map(
                    fn (object $n) => [
                        'notification_id' => $n->notification_id,
                        'responder_id' => $n->responder_id,
                        'full_name' => $n->full_name,
                        'distance_meters' => $n->distance_meters === null ? null : (float) $n->distance_meters,
                        'delivery_status' => $n->delivery_status,
                        'created_at' => $n->created_at,
                    ],
                    $notifications['barangay_tanod']
                ),
            ],
        ], 200);
    }

    private function formatSummary(object $incident): array
    {
        return [
            'incident_id' => $incident->incident_id,
            'reporter_id' => $incident->reporter_id,
            'trigger_source' => $incident->trigger_source,
            'status' => $incident->status,
            'incident_barangay_id' => $incident->incident_barangay_id,
            'latitude' => (float) $incident->latitude,
            'longitude' => (float) $incident->longitude,
            'ai_confidence_score' => $incident->ai_confidence_score === null ? null : (float) $incident->ai_confidence_score,
            'dispatched_by' => $incident->dispatched_by,
            'dispatched_at' => $incident->dispatched_at,
            'created_at' => $incident->created_at,
            'updated_at' => $incident->updated_at,
            'resolved_at' => $incident->resolved_at,
        ];
    }

    /**
     * Broadcasting is a downstream, best-effort step, same as matching and
     * notification below: if Reverb is unreachable, that must never turn an
     * already-created incident into a failed request.
     */
    private function broadcastNewIncident(object $incident): void
    {
        try {
            event(new NewIncident($incident));
        } catch (Throwable $e) {
            Log::error('Failed to broadcast NewIncident event', [
                'incident_id' => $incident->incident_id,
                'exception' => $e,
            ]);
        }
    }

    /**
     * Matching is a downstream, best-effort step: an unexpected failure here
     * must never fail a request whose incident was already created
     * successfully (same principle as ClassifyDistressAudio's own failure
     * handling).
     */
    private function matchResponders(MatchRespondersToIncident $matchResponders, string $incidentId): array
    {
        try {
            $result = $matchResponders->handle($incidentId);

            return [
                'status' => 'completed',
                'matched_via' => $result['matched_via'],
                'responders' => $result['responders'],
            ];
        } catch (Throwable $e) {
            Log::error('Responder matching failed', [
                'incident_id' => $incidentId,
                'exception' => $e,
            ]);

            return [
                'status' => 'failed',
                'matched_via' => null,
                'responders' => [],
            ];
        }
    }

    /**
     * Notification is a downstream, best-effort step: an unexpected
     * failure here must never fail a request whose incident was already
     * created successfully. NotifyRespondersOfIncident already isolates
     * its two channels from each other internally (docs/decisions/07) —
     * this outer catch is only a safety net for something breaking before
     * either channel's own try/catch, e.g. a bad argument.
     */
    private function notifyResponders(
        NotifyRespondersOfIncident $notifyResponders,
        string $incidentId,
        array $matchedResponders,
    ): array {
        try {
            return $notifyResponders->handle($incidentId, $matchedResponders);
        } catch (Throwable $e) {
            Log::error('Responder notification failed', [
                'incident_id' => $incidentId,
                'exception' => $e,
            ]);

            return [
                'pnp_dashboard' => ['status' => 'failed'],
                'barangay_tanod' => ['status' => 'failed', 'notified' => [], 'failed_responder_ids' => []],
            ];
        }
    }
}
