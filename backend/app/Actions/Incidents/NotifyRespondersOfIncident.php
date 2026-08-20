<?php

namespace App\Actions\Incidents;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

class NotifyRespondersOfIncident
{
    /**
     * PNP dashboard and barangay tanod are two independent channels
     * (docs/decisions/07-parallel-notification.md) — deliberately NOT
     * wrapped in a shared transaction. A shared transaction would mean one
     * channel's failure rolls back the other's already-successful insert,
     * which is exactly the "tanod waits on PNP or vice versa" coupling
     * Decision 07 rejects. Each channel gets its own try/catch so a
     * failure in one can never prevent or undo the other.
     */
    public function handle(string $incidentId, array $matchedResponders): array
    {
        // Each channel is called and its result captured as its own
        // statement, not inlined into one array-literal expression — if
        // they were inlined, an exception escaping the second call would
        // abort the whole expression and silently discard the first
        // channel's already-correct (and already-committed) result. That
        // would misreport a channel that actually succeeded as "failed",
        // which is exactly the kind of accidental coupling Decision 07
        // warns against, even though the underlying DB writes stay
        // decoupled either way.
        $dashboardResult = $this->notifyDashboard($incidentId);
        $tanodResult = $this->notifyTanods($incidentId, $matchedResponders);

        return [
            'pnp_dashboard' => $dashboardResult,
            'barangay_tanod' => $tanodResult,
        ];
    }

    private function notifyDashboard(string $incidentId): array
    {
        try {
            $row = DB::selectOne(
                <<<'SQL'
                INSERT INTO incident_notifications (incident_id, notified_party_type, delivery_status)
                VALUES (?, 'pnp_dashboard', 'queued')
                RETURNING notification_id
                SQL,
                [$incidentId]
            );

            return ['status' => 'completed', 'notification_id' => $row->notification_id];
        } catch (Throwable $e) {
            Log::error('Failed to create PNP dashboard notification', [
                'incident_id' => $incidentId,
                'exception' => $e,
            ]);

            return ['status' => 'failed'];
        }
    }

    /**
     * One incident_notifications row per matched responder — schema has no
     * mechanism for one row to reference multiple responders. Zero matched
     * responders is not a failure: it just means nothing is attempted.
     */
    private function notifyTanods(string $incidentId, array $matchedResponders): array
    {
        $notified = [];
        $failedResponderIds = [];

        // Outer try/catch makes this method self-contained the same way
        // notifyDashboard() is — nothing inside it, including a failure
        // that occurs outside the per-responder loop below, can escape and
        // prevent handle() from still returning the dashboard channel's
        // already-computed, independent result.
        try {
            foreach ($matchedResponders as $responder) {
                try {
                    $row = DB::selectOne(
                        <<<'SQL'
                        INSERT INTO incident_notifications
                            (incident_id, notified_party_type, notified_user_id, distance_meters, delivery_status)
                        VALUES (?, 'barangay_tanod', ?, ?, 'queued')
                        RETURNING notification_id
                        SQL,
                        [$incidentId, $responder->responder_id, $responder->distance_meters]
                    );

                    $notified[] = [
                        'notification_id' => $row->notification_id,
                        'responder_id' => $responder->responder_id,
                    ];
                } catch (Throwable $e) {
                    Log::error('Failed to create barangay tanod notification', [
                        'incident_id' => $incidentId,
                        'responder_id' => $responder->responder_id,
                        'exception' => $e,
                    ]);

                    $failedResponderIds[] = $responder->responder_id;
                }
            }
        } catch (Throwable $e) {
            Log::error('Unexpected failure while notifying barangay tanods', [
                'incident_id' => $incidentId,
                'exception' => $e,
            ]);

            return ['status' => 'failed', 'notified' => $notified, 'failed_responder_ids' => $failedResponderIds];
        }

        return [
            'status' => count($failedResponderIds) === 0 ? 'completed' : 'failed',
            'notified' => $notified,
            'failed_responder_ids' => $failedResponderIds,
        ];
    }
}
