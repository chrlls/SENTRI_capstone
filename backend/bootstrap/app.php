<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Decision 23 — dashboard (React SPA) uses Sanctum cookie-mode
        // auth, not bearer tokens. statefulApi() makes the `api` group
        // apply session/cookie/CSRF middleware for requests originating
        // from a SANCTUM_STATEFUL_DOMAINS entry, while leaving bearer-token
        // clients (Flutter) completely unaffected.
        $middleware->statefulApi();

        // API-only backend (Decision 18) — Laravel never renders a login
        // page, so an unauthenticated request must always get a JSON 401,
        // never a redirect to a route that doesn't exist.
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
