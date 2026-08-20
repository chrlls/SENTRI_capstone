<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Only the dashboard's own origin is allowed, with credentials support
    | enabled — required for Sanctum SPA cookie mode (Decision 23). `*` is
    | deliberately not used: a wildcard origin cannot be combined with
    | `supports_credentials: true` per the CORS spec, and would defeat the
    | point of cookie-scoped auth anyway.
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    'allowed_origins' => [env('DASHBOARD_URL', 'http://localhost:5173')],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => true,

];
