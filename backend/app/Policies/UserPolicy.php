<?php

namespace App\Policies;

use App\Models\User;

class UserPolicy
{
    /**
     * Per docs/decisions/26-dispatcher-account-provisioning.md: only an
     * admin may provision a new pnp (dispatcher) account. PNP itself has
     * no provisioning authority over other accounts.
     */
    public function createDispatcher(User $user): bool
    {
        return $user->role === 'admin';
    }
}
