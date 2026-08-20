<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

/**
 * docs/decisions/24-admin-provisioning-artisan-command.md — the only way
 * a 'pnp' or 'admin' row is ever created (Decision 19: no public
 * registration path for either role). Console-only by construction: an
 * Artisan command has no HTTP route, so this is unreachable over the
 * network regardless of what the dashboard/mobile clients expose.
 */
class CreateAdminCommand extends Command
{
    protected $signature = 'sentri:create-admin';

    protected $description = 'Provision a PNP or system-admin account (no self-registration path exists for these roles)';

    public function handle(): int
    {
        $this->info('SENTRI admin/PNP account provisioning');

        $email = $this->ask('Email');
        $phoneNumber = $this->ask('Phone number');
        $fullName = $this->ask('Full name');
        $role = $this->choice('Role', ['pnp', 'admin']);
        $password = $this->secret('Password');
        $passwordConfirmation = $this->secret('Confirm password');

        // Same Rule::unique('users', ...) construct RegisterRequest uses
        // for the same columns — not a hand-rolled duplicate check.
        $validator = Validator::make(
            [
                'email' => $email,
                'phone_number' => $phoneNumber,
                'full_name' => $fullName,
                'role' => $role,
                'password' => $password,
                'password_confirmation' => $passwordConfirmation,
            ],
            [
                'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
                'phone_number' => ['required', 'string', 'max:20', Rule::unique('users', 'phone_number')],
                'full_name' => ['required', 'string', 'max:150'],
                'role' => ['required', Rule::in(['pnp', 'admin'])],
                'password' => ['required', 'string', 'min:8', 'confirmed'],
            ],
        );

        if ($validator->fails()) {
            $this->error('Could not create account:');

            foreach ($validator->errors()->all() as $message) {
                $this->line("  - {$message}");
            }

            return self::FAILURE;
        }

        $data = $validator->validated();

        try {
            // Provisioned accounts are active immediately — unlike a
            // self-registered responder, there is no verification step
            // above an admin/PNP account; the admin role IS the verifier.
            // agreement_accepted_at/agreement_version are left NULL:
            // Decision 18's mandatory User Agreement is an end-user
            // acknowledgment about submitting emergency reports, which
            // doesn't apply to an operator account created at a terminal.
            $user = DB::selectOne(
                <<<'SQL'
                INSERT INTO users
                    (email, phone_number, password_hash, full_name, role, status)
                VALUES (?, ?, ?, ?, ?, 'active')
                RETURNING user_id, email, full_name, role
                SQL,
                [
                    $data['email'],
                    $data['phone_number'],
                    Hash::make($data['password']),
                    $data['full_name'],
                    $data['role'],
                ],
            );
        } catch (QueryException $e) {
            Log::error('sentri:create-admin insert failed', ['exception' => $e]);
            $this->error('Failed to create account. See the log for details.');

            return self::FAILURE;
        }

        $this->newLine();
        $this->info("Created {$user->role} account: {$user->full_name} <{$user->email}> ({$user->user_id})");

        return self::SUCCESS;
    }
}
