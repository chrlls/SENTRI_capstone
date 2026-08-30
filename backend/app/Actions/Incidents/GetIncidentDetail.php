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
    /**
     * reporter_id has a NOT NULL FK to users(user_id), so an inner join
     * here can never drop the incident row — same guarantee the
     * notifications() barangay_tanod join below already relies on for
     * responder names. incident_barangay_id is nullable (the
     * "unresolved" case), so that join stays LEFT.
     */
    /**
     * ai_confidence_score is sourced from voice_analysis.distress_confidence
     * via the LATERAL join, not the incidents.ai_confidence_score column —
     * confirmed by grep (Phase 4) that nothing ever writes that column, so
     * it's always NULL regardless of a real completed classification, the
     * same kind of gap Phase 2 found for audio_duration_seconds. This
     * response field keeps its existing name (a real fix, not a new field);
     * the fuller ai_classification object below remains the primary source
     * for the detail view, this just keeps the flat summary field honest
     * too, since updateStatus() reuses this same query and its response.
     */
    public function find(string $incidentId): ?object
    {
        return DB::selectOne(
            <<<'SQL'
            SELECT incidents.incident_id, incidents.reporter_id, incidents.trigger_source,
                   incidents.status, incidents.incident_barangay_id,
                   ST_Y(incidents.location::geometry) AS latitude,
                   ST_X(incidents.location::geometry) AS longitude,
                   incidents.location_captured_at,
                   voice_analysis.distress_confidence AS ai_confidence_score,
                   incidents.dispatched_by, incidents.dispatched_at,
                   incidents.dispatcher_notes, incidents.incident_notes,
                   incidents.created_at, incidents.updated_at, incidents.resolved_at,
                   barangay.barangay_name,
                   reporter.full_name AS reporter_full_name,
                   reporter.role AS reporter_role
            FROM incidents
            JOIN users reporter ON reporter.user_id = incidents.reporter_id
            LEFT JOIN barangay_boundaries barangay ON barangay.barangay_id = incidents.incident_barangay_id
            LEFT JOIN LATERAL (
                SELECT distress_confidence
                FROM voice_analysis_events
                WHERE voice_analysis_events.incident_id = incidents.incident_id
                ORDER BY analyzed_at DESC
                LIMIT 1
            ) voice_analysis ON true
            WHERE incidents.incident_id = ?
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
                   audio_storage_ref, audio_duration_seconds, analyzed_at
            FROM voice_analysis_events
            WHERE incident_id = ?
            ORDER BY analyzed_at DESC
            LIMIT 1
            SQL,
            [$incidentId]
        );
    }

    /**
     * Full transition history, oldest first (a timeline reads top-to-bottom
     * chronologically). changed_by is nullable (system-generated
     * transitions, e.g. the dashboard_alerted auto-transition — Decision
     * 27's addendum), so this stays a LEFT JOIN; the controller maps a
     * null changed_by_name to "System".
     */
    public function statusHistory(string $incidentId): array
    {
        return DB::select(
            <<<'SQL'
            SELECT h.history_id, h.old_status, h.new_status, h.changed_by,
                   u.full_name AS changed_by_name, h.changed_at, h.reason
            FROM incident_status_history h
            LEFT JOIN users u ON u.user_id = h.changed_by
            WHERE h.incident_id = ?
            ORDER BY h.changed_at ASC
            SQL,
            [$incidentId]
        );
    }

    /**
     * Read path only — nothing in this codebase writes to
     * keyword_match_events yet (no keyword-matching pipeline exists),
     * confirmed by grep before adding this method. Will always return an
     * empty array until that pipeline is built; the endpoint exposes the
     * column shape now so the frontend doesn't need a second change when
     * it does.
     */
    public function keywordMatches(string $incidentId): array
    {
        return DB::select(
            <<<'SQL'
            SELECT match_id, matched_phrase, transcript_snippet, language, matched_at
            FROM keyword_match_events
            WHERE incident_id = ?
            ORDER BY matched_at ASC
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
