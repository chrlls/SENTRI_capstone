<?php

use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

/**
 * Only PNP/admin may subscribe — same restriction NewIncident's
 * broadcastOn() relies on. A civilian/responder authenticating
 * successfully here would defeat Phase 2's per-incident read scoping by
 * letting them observe every incident's creation over the socket instead.
 */
Broadcast::channel('incidents.dashboard', function (User $user) {
    return in_array($user->role, ['pnp', 'admin'], true);
});
