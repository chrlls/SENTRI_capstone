<?php

namespace App\Http\Controllers;

use App\Actions\Auth\AuthenticateUser;
use App\Actions\Auth\RegisterUser;
use App\Http\Requests\LoginRequest;
use App\Http\Requests\RegisterRequest;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\PersonalAccessToken;

class AuthController extends Controller
{
    private const LOGIN_MAX_ATTEMPTS = 5;

    private const LOGIN_DECAY_SECONDS = 3600;

    private const GENERIC_AUTH_FAILURE_MESSAGE = 'These credentials do not match our records.';

    public function register(RegisterRequest $request, RegisterUser $action): JsonResponse
    {
        try {
            $user = $action->handle($request->validated());
        } catch (QueryException $e) {
            Log::error('User registration insert failed', ['exception' => $e]);

            return response()->json(['error' => 'Failed to register.'], 500);
        }

        // Only reached after a successful registration — a legitimate
        // user isn't penalized for an earlier typo elsewhere in this
        // hour's budget.
        RateLimiter::clear($request->throttleKey());

        return response()->json([
            'user_id' => $user->user_id,
            'email' => $user->email,
            'phone_number' => $user->phone_number,
            'full_name' => $user->full_name,
            'role' => $user->role,
            'status' => $user->status,
            'agreement_accepted_at' => $user->agreement_accepted_at,
            'created_at' => $user->created_at,
        ], 201);
    }

    public function login(LoginRequest $request, AuthenticateUser $action): JsonResponse
    {
        $data = $request->validated();
        $throttleKey = $request->throttleKey();

        if (RateLimiter::tooManyAttempts($throttleKey, self::LOGIN_MAX_ATTEMPTS)) {
            return response()
                ->json(['message' => 'Too Many Attempts.'], 429)
                ->header('Retry-After', (string) RateLimiter::availableIn($throttleKey));
        }

        $user = $action->handle($data['email'], $data['password']);

        if ($user === null) {
            // Same increment, same response, whether the email doesn't
            // exist or the password was wrong — anything else here would
            // reopen the enumeration signal (docs/SECURITY_AUDIT.md).
            RateLimiter::hit($throttleKey, self::LOGIN_DECAY_SECONDS);

            return response()->json(['message' => self::GENERIC_AUTH_FAILURE_MESSAGE], 401);
        }

        RateLimiter::clear($throttleKey);

        // Decision 23 — dashboard (React SPA) requests are "stateful"
        // (session/cookie middleware ran, per statefulApi() in
        // bootstrap/app.php) because their origin matches
        // SANCTUM_STATEFUL_DOMAINS. Only those requests get a session
        // cookie; Flutter's requests have no session, so this is a no-op
        // for them and they keep authenticating via the token below exactly
        // as before — same endpoint, same response shape, two transport
        // mechanisms.
        if ($request->hasSession()) {
            Auth::login($user);
            $request->session()->regenerate();
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'token' => $token,
            'user' => [
                'user_id' => $user->user_id,
                'email' => $user->email,
                'full_name' => $user->full_name,
                'role' => $user->role,
                'status' => $user->status,
            ],
        ], 200);
    }

    /**
     * "Is there already a valid session" check for a client on page
     * load/refresh — needed by the dashboard's cookie-mode auth (Decision
     * 23) since it has no client-readable token to inspect. Works equally
     * for a bearer-token client, since auth:sanctum resolves the user the
     * same way regardless of transport.
     */
    public function user(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'user_id' => $user->user_id,
            'email' => $user->email,
            'full_name' => $user->full_name,
            'role' => $user->role,
            'status' => $user->status,
        ], 200);
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()->currentAccessToken();

        // A session-authenticated request (dashboard) resolves a
        // TransientToken, not a real personal_access_tokens row — nothing
        // to delete there, the session itself is what gets invalidated
        // below. A bearer-token request (Flutter) resolves a real
        // PersonalAccessToken, which must be revoked so the token can't be
        // reused after logout.
        if ($token instanceof PersonalAccessToken) {
            $token->delete();
        }

        if ($request->hasSession()) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();
        }

        return response()->json(['message' => 'Logged out.'], 200);
    }
}
