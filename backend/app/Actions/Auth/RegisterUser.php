<?php

namespace App\Actions\Auth;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class RegisterUser
{
    /**
     * No agreement-text versioning system exists yet — this is the first
     * version there is, hardcoded until one is introduced.
     */
    private const AGREEMENT_VERSION = 'v1.0';

    /**
     * Civilians are active immediately (Decision 19). Responders register
     * through the same path but are left in the schema's own
     * 'pending_verification' default rather than promoted to 'active' —
     * that default already matches Decision 19's "account starts in an
     * unverified/pending state" wording, so it's set explicitly here
     * rather than silently relied upon. The privilege gate that actually
     * matters for matching/notification (docs/decisions/01, /07) is
     * responder_profiles.verification_status, inserted at its own
     * 'pending' default below — deliberately not set to 'verified' here.
     */
    public function handle(array $data): object
    {
        return DB::transaction(function () use ($data) {
            $status = $data['role'] === 'civilian' ? 'active' : 'pending_verification';

            $user = DB::selectOne(
                <<<'SQL'
                INSERT INTO users
                    (email, phone_number, password_hash, full_name, role, status, agreement_accepted_at, agreement_version)
                VALUES (?, ?, ?, ?, ?, ?, now(), ?)
                RETURNING user_id, email, phone_number, full_name, role, status, agreement_accepted_at, created_at
                SQL,
                [
                    $data['email'],
                    $data['phone_number'],
                    Hash::make($data['password']),
                    $data['full_name'],
                    $data['role'],
                    $status,
                    self::AGREEMENT_VERSION,
                ]
            );

            if ($data['role'] === 'responder') {
                // Self-registered responders are always barangay_tanod —
                // Decision 19's self-service path is explicitly scoped to
                // that type; pnp_officer/other_verified are not
                // self-registerable. verification_status and is_on_duty
                // are left at their schema defaults ('pending', false).
                DB::insert(
                    "INSERT INTO responder_profiles (responder_id, responder_type) VALUES (?, 'barangay_tanod')",
                    [$user->user_id]
                );
            }

            return $user;
        });
    }
}
