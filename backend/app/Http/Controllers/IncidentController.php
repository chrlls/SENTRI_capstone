<?php

namespace App\Http\Controllers;

use App\Actions\Incidents\ClassifyDistressAudio;
use App\Actions\Incidents\CreateAiAssistedSosIncident;
use App\Actions\Incidents\CreateManualSosIncident;
use App\Actions\Incidents\MatchRespondersToIncident;
use App\Actions\Incidents\NotifyRespondersOfIncident;
use App\Actions\Incidents\RecordVoiceAnalysisEvent;
use App\Http\Requests\AiAssistedSosRequest;
use App\Http\Requests\ManualSosRequest;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
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

        // Incident already exists at this point — matching and
        // notification are both downstream steps and must never turn a
        // created incident into a failed request (docs/decisions/01, /05,
        // /07).
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
        // the incident itself (docs/decisions/05, /13).
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
