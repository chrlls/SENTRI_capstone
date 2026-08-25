<?php

namespace App\Actions\Auth;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class CreateDispatcherAccount
{
    /**
     * Per docs/decisions/26-dispatcher-account-provisioning.md: an admin
     * creating the account IS the verification, so the row is 'active'
     * immediately, no pending step. role is a hardcoded literal in the
     * SQL itself, never derived from input — same pattern as
     * CreateAdminCommand's 'admin' literal. agreement_accepted_at/
     * agreement_version are left NULL for the same reason CreateAdminCommand
     * leaves them NULL: this is an operator account created by an admin,
     * not an end-user acknowledging the SOS-reporting agreement.
     */
    public function handle(array $data): object
    {
        return DB::selectOne(
            <<<'SQL'
            INSERT INTO users
                (email, phone_number, password_hash, full_name, role, status)
            VALUES (?, ?, ?, ?, 'pnp', 'active')
            RETURNING user_id, email, full_name, role, status
            SQL,
            [
                $data['email'],
                $data['phone_number'],
                Hash::make($data['password']),
                $data['full_name'],
            ]
        );
    }
}
