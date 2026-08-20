<?php

namespace App\Actions\Auth;

use App\Models\User;
use Illuminate\Support\Facades\Hash;

class AuthenticateUser
{
    /**
     * Returns null for BOTH "no such email" and "wrong password" — the
     * caller must not treat these two cases any differently, or it
     * reintroduces the exact user-enumeration signal this is meant to
     * prevent (docs/SECURITY_AUDIT.md).
     */
    public function handle(string $email, string $password): ?User
    {
        $user = User::where('email', $email)->first();

        if ($user === null || ! Hash::check($password, $user->password_hash)) {
            return null;
        }

        return $user;
    }
}
