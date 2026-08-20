<?php

namespace App\Policies;

use App\Models\User;

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
}
