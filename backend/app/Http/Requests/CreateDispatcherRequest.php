<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CreateDispatcherRequest extends FormRequest
{
    /**
     * Real enforcement is the 'create-dispatcher' Gate, checked in the
     * controller via Gate::authorize() — same split as every other
     * authorized endpoint in this app (e.g. IncidentController). Not
     * duplicated here.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Same rules as RegisterRequest for these four fields
     * (docs/decisions/26-dispatcher-account-provisioning.md), minus
     * 'role' (hardcoded to 'pnp' server-side, never client-supplied) and
     * 'agreement_accepted' (that field encodes the false-alarm-liability
     * agreement tied to self-reporting an incident — meaningless for an
     * account that only ever consumes the dispatcher console).
     */
    public function rules(): array
    {
        return [
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'phone_number' => ['required', 'string', 'max:20', Rule::unique('users', 'phone_number')],
            'password' => ['required', 'string', 'min:8'],
            'full_name' => ['required', 'string', 'max:150'],
        ];
    }
}
