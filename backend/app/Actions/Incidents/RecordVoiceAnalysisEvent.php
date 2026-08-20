<?php

namespace App\Actions\Incidents;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class RecordVoiceAnalysisEvent
{
    /**
     * Persists the clip (voice_analysis_events.audio_storage_ref is
     * NOT NULL) and the classification result. Only called after a
     * completed classification — an audio file is never written to disk
     * for a clip that was never successfully classified.
     */
    public function handle(
        string $incidentId,
        string $reporterId,
        UploadedFile $audio,
        bool $distressLabel,
        float $distressConfidence,
        string $modelVersion,
    ): object {
        $storedPath = Storage::disk('local')->putFile('sos-audio', $audio);

        $result = DB::selectOne(
            <<<'SQL'
            INSERT INTO voice_analysis_events
                (incident_id, user_id, audio_storage_ref, distress_label, distress_confidence, model_version)
            VALUES (?, ?, ?, ?, ?, ?)
            RETURNING analysis_id, incident_id, distress_label, distress_confidence, model_version, analyzed_at
            SQL,
            [$incidentId, $reporterId, $storedPath, $distressLabel, $distressConfidence, $modelVersion]
        );

        return $result;
    }
}
