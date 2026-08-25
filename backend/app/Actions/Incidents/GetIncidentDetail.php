<?php

namespace App\Actions\Incidents;

use Illuminate\Support\Facades\DB;

class GetIncidentDetail
{
    /**
     * Fetched unscoped by permission — the controller checks
     * 'view-incident' against the returned row afterward. Returns null on a
     * bad/nonexistent ID, which the controller treats identically to a
     * failed authorization check (both become a 404 — see Decision 21's
     * "Verified" note for why).
     */
    public function find(string $incidentId): ?object
    {
        return DB::selectOne(
            <<<'SQL'
            SELECT incident_id, reporter_id, trigger_source, status, incident_barangay_id,
                   ST_Y(location::geometry) AS latitude,
                   ST_X(location::geometry) AS longitude,
                   location_captured_at, ai_confidence_score,
                   dispatched_by, dispatched_at, dispatcher_notes, incident_notes,
                   created_at, updated_at, resolved_at
            FROM incidents
            WHERE incident_id = ?
            SQL,
            [$incidentId]
        );
    }

    /**
     * Most recent completed classification for this incident, if any.
     * Per Decision 21, audio access follows the same rule as the incident
     * itself — no separate check gates audio_storage_ref here, the
     * controller only calls this after 'view-incident' already passed.
     */
    public function classification(string $incidentId): ?object
    {
        return DB::selectOne(
            <<<'SQL'
            SELECT distress_label, distress_confidence, model_version,
                   audio_storage_ref, analyzed_at
            FROM voice_analysis_events
            WHERE incident_id = ?
            ORDER BY analyzed_at DESC
            LIMIT 1
            SQL,
            [$incidentId]
        );
    }

    /**
     * The real, persisted incident_notifications rows — not a re-run of
     * MatchRespondersToIncident, which reflects duty/location at request
     * time, not at the moment this incident was created.
     */
    public function notifications(string $incidentId): array
    {
        $dashboard = DB::selectOne(
            <<<'SQL'
            SELECT notification_id, delivery_status, created_at
            FROM incident_notifications
            WHERE incident_id = ? AND notified_party_type = 'pnp_dashboard'
            LIMIT 1
            SQL,
            [$incidentId]
        );

        $tanods = DB::select(
            <<<'SQL'
            SELECT n.notification_id, n.notified_user_id AS responder_id, u.full_name,
                   n.distance_meters, n.delivery_status, n.created_at
            FROM incident_notifications n
            JOIN users u ON u.user_id = n.notified_user_id
            WHERE n.incident_id = ? AND n.notified_party_type = 'barangay_tanod'
            ORDER BY n.distance_meters ASC
            SQL,
            [$incidentId]
        );

        return [
            'pnp_dashboard' => $dashboard,
            'barangay_tanod' => $tanods,
        ];
    }
}
