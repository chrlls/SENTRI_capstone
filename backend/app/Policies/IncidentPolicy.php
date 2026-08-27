<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class IncidentPolicy
{
    /**
     * Per docs/decisions/21-role-based-authorization.md: SOS access is
     * "is this a human who might be in danger," not a role permission —
     * civilians and responders may create an incident regardless of
     * verification status. PNP/admin are excluded; a dispatcher-logged
     * report on behalf of someone else is a separate, not-yet-built
     * endpoint, not this one.
     */
    public function create(User $user): bool
    {
        return in_array($user->role, ['civilian', 'responder'], true);
    }

    /**
     * Read-access rules from docs/decisions/21-role-based-authorization.md's
     * table: a civilian sees only their own report, a responder only an
     * incident they were actually matched/notified for (checked directly
     * against incident_notifications, the same rows NotifyRespondersOfIncident
     * writes), PNP/admin see anything. $incident is the plain row object
     * returned by GetIncidentDetail — there is no Eloquent Incident model
     * (raw SQL is used throughout for PostGIS handling), so this takes a
     * stdClass rather than a model instance.
     *
     * Audio and location access intentionally reuse this same check
     * (documented as "no separate, stricter tier" in Decision 21) — callers
     * must not add a second, independent gate for those fields.
     */
    public function view(User $user, object $incident): bool
    {
        return match ($user->role) {
            'civilian' => $incident->reporter_id === $user->user_id,
            'responder' => $this->wasNotifiedForIncident($user->user_id, $incident->incident_id),
            'pnp', 'admin' => true,
            default => false,
        };
    }

    private function wasNotifiedForIncident(string $responderId, string $incidentId): bool
    {
        return DB::table('incident_notifications')
            ->where('incident_id', $incidentId)
            ->where('notified_party_type', 'barangay_tanod')
            ->where('notified_user_id', $responderId)
            ->exists();
    }

    /**
     * Per docs/decisions/27-dispatcher-incident-actions.md: only a human
     * PNP dispatcher or admin may move an incident's status — a civilian
     * or responder can never change it, including their own incident.
     * Role-only, unlike view() above: doesn't depend on which incident,
     * so it's cheap to check ahead of any incident lookup (see
     * UpdateIncidentStatusRequest::authorize() for why that ordering
     * matters here specifically).
     */
    public function updateStatus(User $user): bool
    {
        return in_array($user->role, ['pnp', 'admin'], true);
    }
}
