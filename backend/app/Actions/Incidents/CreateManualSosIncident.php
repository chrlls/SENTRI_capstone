<?php

namespace App\Actions\Incidents;

use Illuminate\Support\Facades\DB;
use RuntimeException;

class CreateManualSosIncident
{
    /**
     * Inserts a manual_sos incident directly (no AI pipeline involvement,
     * per docs/decisions/05-manual-sos-never-gated.md). incident_barangay_id
     * is left for the resolve_incident_barangay() trigger to populate.
     */
    public function handle(string $reporterId, float $latitude, float $longitude): object
    {
        $result = DB::selectOne(
            <<<'SQL'
            WITH inserted AS (
                INSERT INTO incidents (reporter_id, trigger_source, location)
                VALUES (?, 'manual_sos', ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)
                RETURNING incident_id, reporter_id, trigger_source, status,
                          incident_barangay_id, location, created_at
            )
            SELECT incident_id, reporter_id, trigger_source, status, incident_barangay_id,
                   ST_Y(location::geometry) AS latitude,
                   ST_X(location::geometry) AS longitude,
                   created_at
            FROM inserted
            SQL,
            [$reporterId, $longitude, $latitude]
        );

        if ($result === null) {
            throw new RuntimeException('Manual SOS incident insert returned no row.');
        }

        return $result;
    }
}
