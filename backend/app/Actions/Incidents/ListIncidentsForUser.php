<?php

namespace App\Actions\Incidents;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class ListIncidentsForUser
{
    /**
     * barangay_name is joined here too (not just on the detail endpoint)
     * because the redesigned dispatcher rail/hover-preview cards render
     * from this list response and need a human-readable location, not
     * just incident_barangay_id's raw UUID.
     *
     * ai_confidence_score is sourced from voice_analysis.distress_confidence
     * via the LATERAL join below, not the incidents.ai_confidence_score
     * column — confirmed by grep (dispatcher-console redesign, Phase 4)
     * that nothing anywhere ever writes that column, so it's always NULL
     * regardless of a real completed classification exactly like
     * audio_duration_seconds's write gap found in Phase 2. This response
     * field keeps its existing name/shape (a real fix to what it should
     * already have meant, not a new field) so the hover-preview card can
     * show a real AI-confidence badge without a per-hover fetch.
     */
    private const SELECT_COLUMNS = <<<'SQL'
        incidents.incident_id, incidents.reporter_id, incidents.trigger_source,
        incidents.status, incidents.incident_barangay_id,
        ST_Y(incidents.location::geometry) AS latitude,
        ST_X(incidents.location::geometry) AS longitude,
        voice_analysis.distress_confidence AS ai_confidence_score,
        incidents.dispatched_by, incidents.dispatched_at,
        incidents.created_at, incidents.updated_at, incidents.resolved_at,
        barangay.barangay_name
        SQL;

    private const BARANGAY_JOIN = <<<'SQL'
        LEFT JOIN barangay_boundaries barangay ON barangay.barangay_id = incidents.incident_barangay_id
        SQL;

    private const VOICE_ANALYSIS_JOIN = <<<'SQL'
        LEFT JOIN LATERAL (
            SELECT distress_confidence
            FROM voice_analysis_events
            WHERE voice_analysis_events.incident_id = incidents.incident_id
            ORDER BY analyzed_at DESC
            LIMIT 1
        ) voice_analysis ON true
        SQL;

    /**
     * Scoped per docs/decisions/21-role-based-authorization.md's read-access
     * table — the WHERE clause enforces the scope directly in the query, not
     * a client-side filter over an unrestricted result set.
     */
    public function handle(User $user): array
    {
        return match ($user->role) {
            'civilian' => $this->listForReporter($user->user_id),
            'responder' => $this->listForMatchedResponder($user->user_id),
            'pnp', 'admin' => $this->listAll(),
            default => [],
        };
    }

    private function listForReporter(string $reporterId): array
    {
        return DB::select(
            'SELECT '.self::SELECT_COLUMNS.'
            FROM incidents
            '.self::BARANGAY_JOIN.'
            '.self::VOICE_ANALYSIS_JOIN.'
            WHERE incidents.reporter_id = ?
            ORDER BY incidents.created_at DESC',
            [$reporterId]
        );
    }

    /**
     * "Matched/notified" is checked directly against incident_notifications
     * — the same rows NotifyRespondersOfIncident writes — not re-derived via
     * MatchRespondersToIncident, since responder duty status/location can
     * change after the original match ran.
     */
    private function listForMatchedResponder(string $responderId): array
    {
        return DB::select(
            'SELECT '.self::SELECT_COLUMNS.'
            FROM incidents
            '.self::BARANGAY_JOIN.'
            '.self::VOICE_ANALYSIS_JOIN.'
            WHERE incidents.incident_id IN (
                SELECT incident_id FROM incident_notifications
                WHERE notified_party_type = \'barangay_tanod\' AND notified_user_id = ?
            )
            ORDER BY incidents.created_at DESC',
            [$responderId]
        );
    }

    private function listAll(): array
    {
        return DB::select(
            'SELECT '.self::SELECT_COLUMNS.'
            FROM incidents
            '.self::BARANGAY_JOIN.'
            '.self::VOICE_ANALYSIS_JOIN.'
            ORDER BY incidents.created_at DESC'
        );
    }
}
