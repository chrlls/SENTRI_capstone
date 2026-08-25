<?php

namespace App\Http\Controllers;

use App\Actions\Auth\CreateDispatcherAccount;
use App\Http\Requests\CreateDispatcherRequest;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;

class DispatcherController extends Controller
{
    /**
     * docs/decisions/26-dispatcher-account-provisioning.md: admin-only,
     * enforced by the Gate below, not merely hidden from a client UI.
     * Does not issue a token — the new dispatcher logs in separately
     * with their own credentials, same "created" vs. "session started"
     * separation as POST /api/auth/register.
     */
    public function store(CreateDispatcherRequest $request, CreateDispatcherAccount $action): JsonResponse
    {
        Gate::authorize('create-dispatcher');

        try {
            $user = $action->handle($request->validated());
        } catch (QueryException $e) {
            Log::error('Dispatcher account insert failed', ['exception' => $e]);

            return response()->json(['error' => 'Failed to create dispatcher account.'], 500);
        }

        return response()->json([
            'user_id' => $user->user_id,
            'email' => $user->email,
            'full_name' => $user->full_name,
            'role' => $user->role,
            'status' => $user->status,
        ], 201);
    }
}
