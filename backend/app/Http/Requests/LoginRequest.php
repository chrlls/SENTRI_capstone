<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class LoginRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ];
    }

    /**
     * email+IP, not IP alone — precise enough that one attacker can't
     * lock out a legitimate user by deliberately failing login attempts
     * against their email from a different IP.
     */
    public function throttleKey(): string
    {
        return 'login|' . strtolower((string) $this->input('email')) . '|' . $this->ip();
    }
}
