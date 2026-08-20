<?php

namespace App\Actions\Incidents;

use Illuminate\Support\Facades\DB;

class MatchRespondersToIncident
{
    private const RADIUS_METERS = 1500;

    /**
     * Step 1 (barangay-primary): on-duty tanods assigned to the incident's
     * own barangay. Step 2 (radius-fallback, 1500m) only runs if Step 1
     * returns zero rows — which also covers incident_barangay_id IS NULL,
     * since assigned_barangay_id = NULL never matches in SQL.
     *
     * Both steps also require verification_status = 'verified' (Decision
     * 19) — an on-duty-but-pending responder is excluded the same way an
     * off-duty one already is, not treated as an error.
     */
    public function handle(string $incidentId): array
    {
        $responders = $this->matchByBarangay($incidentId);

        if (count($responders) > 0) {
            return [
                'matched_via' => 'barangay_primary',
                'responders' => $responders,
            ];
        }

        return [
            'matched_via' => 'radius_fallback',
            'responders' => $this->matchByRadius($incidentId),
        ];
    }

    private function matchByBarangay(string $incidentId): array
    {
        return DB::select(
            <<<'SQL'
            SELECT rp.responder_id, u.full_name,
                   ST_Distance(rp.last_location, i.location) AS distance_meters
            FROM responder_profiles rp
            JOIN users u ON u.user_id = rp.responder_id
            CROSS JOIN incidents i
            WHERE i.incident_id = ?
              AND rp.is_on_duty = true
              AND rp.verification_status = 'verified'
              AND rp.responder_type = 'barangay_tanod'
              AND rp.assigned_barangay_id = i.incident_barangay_id
            ORDER BY distance_meters ASC
            SQL,
            [$incidentId]
        );
    }

    private function matchByRadius(string $incidentId): array
    {
        return DB::select(
            <<<'SQL'
            SELECT rp.responder_id, u.full_name,
                   ST_Distance(rp.last_location, i.location) AS distance_meters
            FROM responder_profiles rp
            JOIN users u ON u.user_id = rp.responder_id
            CROSS JOIN incidents i
            WHERE i.incident_id = ?
              AND rp.is_on_duty = true
              AND rp.verification_status = 'verified'
              AND rp.responder_type = 'barangay_tanod'
              AND ST_DWithin(rp.last_location, i.location, ?)
            ORDER BY distance_meters ASC
            SQL,
            [$incidentId, self::RADIUS_METERS]
        );
    }
}
