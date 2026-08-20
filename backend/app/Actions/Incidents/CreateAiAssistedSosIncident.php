<?php

namespace App\Actions\Incidents;

use Illuminate\Support\Facades\DB;
use RuntimeException;

class CreateAiAssistedSosIncident
{
    /**
     * Inserts a voice_distress incident before any AI classification call,
     * per docs/decisions/13-ai-service-sync-contract.md: incident creation
     * must never wait on or be gated by the AI service response.
     */
    public function handle(string $reporterId, float $latitude, float $longitude): object
    {
        $result = DB::selectOne(
            <<<'SQL'
            WITH inserted AS (
                INSERT INTO incidents (reporter_id, trigger_source, location)
                VALUES (?, 'voice_distress', ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)
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
            throw new RuntimeException('AI-assisted SOS incident insert returned no row.');
        }

        return $result;
    }
}
