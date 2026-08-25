<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Fired once, right after an incident row is inserted (manual_sos or
 * voice_distress) — deliberately not fired again on later status changes,
 * per docs/decisions/25-realtime-reverb.md's "creation only for now" scope.
 * ShouldBroadcastNow (not ShouldBroadcast) sends synchronously: this
 * project has no real queue worker (QUEUE_CONNECTION=sync), so queuing the
 * broadcast job would just run it inline anyway.
 */
class NewIncident implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets;

    public function __construct(private readonly object $incident) {}

    /**
     * Private, not public — only PNP/admin dashboards may subscribe (see
     * routes/channels.php's authorization callback), consistent with
     * docs/decisions/21-role-based-authorization.md restricting incident
     * visibility. A public channel here would let anyone who guesses the
     * channel name observe every incident's creation, bypassing the same
     * read-access rules Phase 2 just enforced over HTTP.
     */
    public function broadcastOn(): array
    {
        return [new PrivateChannel('incidents.dashboard')];
    }

    public function broadcastAs(): string
    {
        return 'incident.created';
    }

    public function broadcastWith(): array
    {
        return [
            'incident_id' => $this->incident->incident_id,
            'reporter_id' => $this->incident->reporter_id,
            'trigger_source' => $this->incident->trigger_source,
            'status' => $this->incident->status,
            'incident_barangay_id' => $this->incident->incident_barangay_id,
            'latitude' => (float) $this->incident->latitude,
            'longitude' => (float) $this->incident->longitude,
            'created_at' => $this->incident->created_at,
        ];
    }
}
