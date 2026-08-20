<?php

namespace App\Actions\Incidents;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

class ClassifyDistressAudio
{
    private const TIMEOUT_SECONDS = 8;

    /**
     * Calls ai-service's /classify synchronously. Per decisions/05 and /13,
     * no failure mode here (timeout, connection refused, 4xx, 5xx) may ever
     * bubble up as an exception the caller has to handle as a hard error —
     * every failure resolves to an "inconclusive" result so the incident
     * this is attached to is never blocked or delayed by it.
     */
    public function handle(UploadedFile $audio): array
    {
        try {
            $response = Http::timeout(self::TIMEOUT_SECONDS)
                ->attach('audio', file_get_contents($audio->getRealPath()), $audio->getClientOriginalName())
                ->post(rtrim(config('services.ai_service.url'), '/') . '/classify');
        } catch (Throwable $e) {
            Log::warning('AI classification call failed (connection error or timeout)', [
                'message' => $e->getMessage(),
            ]);

            return [
                'status' => 'inconclusive',
                'reason' => 'connection_failed',
            ];
        }

        if (! $response->successful()) {
            Log::warning('AI classification returned a non-200 response', [
                'http_status' => $response->status(),
                'body' => $response->body(),
            ]);

            return [
                'status' => 'inconclusive',
                'reason' => 'http_' . $response->status(),
            ];
        }

        $body = $response->json();

        return [
            'status' => 'completed',
            'distress_label' => (bool) $body['distress_label'],
            'distress_confidence' => (float) $body['distress_confidence'],
            'model_version' => (string) $body['model_version'],
        ];
    }
}
