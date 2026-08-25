<?php

namespace App\Actions\Incidents;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class ListIncidentsForUser
{
    private const SELECT_COLUMNS = <<<'SQL'
        incident_id, reporter_id, trigger_source, status, incident_barangay_id,
        ST_Y(location::geometry) AS latitude,
        ST_X(location::geometry) AS longitude,
        ai_confidence_score, dispatched_by, dispatched_at,
        created_at, updated_at, resolved_at
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
            WHERE reporter_id = ?
            ORDER BY created_at DESC',
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
            WHERE incident_id IN (
                SELECT incident_id FROM incident_notifications
                WHERE notified_party_type = \'barangay_tanod\' AND notified_user_id = ?
            )
            ORDER BY created_at DESC',
            [$responderId]
        );
    }

    private function listAll(): array
    {
        return DB::select(
            'SELECT '.self::SELECT_COLUMNS.'
            FROM incidents
            ORDER BY created_at DESC'
        );
    }
}
