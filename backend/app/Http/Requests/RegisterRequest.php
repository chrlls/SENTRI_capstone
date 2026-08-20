<?php

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\ThrottleRequestsException;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rule;

class RegisterRequest extends FormRequest
{
    private const MAX_ATTEMPTS = 3;

    private const DECAY_SECONDS = 3600;

    /**
     * Checked before validation runs, not just before the controller —
     * per docs/SECURITY_AUDIT.md, an attacker sending intentionally
     * invalid data must not be able to bypass the limit, so the lockout
     * itself has to be enforced ahead of, not just alongside, validation.
     */
    public function authorize(): bool
    {
        if (RateLimiter::tooManyAttempts($this->throttleKey(), self::MAX_ATTEMPTS)) {
            throw $this->throttleException();
        }

        return true;
    }

    public function rules(): array
    {
        return [
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'phone_number' => ['required', 'string', 'max:20', Rule::unique('users', 'phone_number')],
            'password' => ['required', 'string', 'min:8'],
            'full_name' => ['required', 'string', 'max:150'],
            // Per docs/decisions/19-account-provisioning-model.md: only
            // civilian and responder may be self-registered. pnp/admin
            // are rejected outright at the API level, not merely hidden
            // from a client UI.
            'role' => ['required', Rule::in(['civilian', 'responder'])],
            // Mandatory User Agreement acceptance (Decision 18) — the
            // 'accepted' rule requires true/"yes"/"on"/1.
            'agreement_accepted' => ['required', 'accepted'],
        ];
    }

    /**
     * Validation failures (bad email, weak password, disallowed role,
     * etc.) count against the limit too — otherwise an attacker could
     * send intentionally invalid data to probe the endpoint for free.
     */
    protected function failedValidation(Validator $validator): void
    {
        RateLimiter::hit($this->throttleKey(), self::DECAY_SECONDS);

        parent::failedValidation($validator);
    }

    public function throttleKey(): string
    {
        // IP only: unique:users validation already prevents duplicate
        // registrations for the same email, so keying by email would
        // never actually trigger.
        return 'register|' . $this->ip();
    }

    private function throttleException(): ThrottleRequestsException
    {
        $retryAfter = RateLimiter::availableIn($this->throttleKey());

        return new ThrottleRequestsException('Too Many Attempts.', null, [
            'Retry-After' => $retryAfter,
            'X-RateLimit-Limit' => self::MAX_ATTEMPTS,
            'X-RateLimit-Remaining' => 0,
        ]);
    }
}
