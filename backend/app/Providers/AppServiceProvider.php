<?php

namespace App\Providers;

use App\Policies\IncidentPolicy;
use App\Policies\UserPolicy;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // No Eloquent Incident model exists (raw SQL is used throughout
        // for PostGIS geography handling — see CreateManualSosIncident),
        // so this policy is registered as a plain named ability rather
        // than mapped via Gate::policy(Incident::class, ...).
        Gate::define('create-incident', [IncidentPolicy::class, 'create']);
        Gate::define('view-incident', [IncidentPolicy::class, 'view']);
        Gate::define('create-dispatcher', [UserPolicy::class, 'createDispatcher']);

        // Loaded directly (not via withRouting()'s `channels:` param, which
        // would also auto-register its own '/broadcasting/auth' route under
        // the 'web' middleware group — wrong for this API-only, Sanctum-only
        // app, and a duplicate of the one routes/api.php registers under
        // 'auth:sanctum'). This require only pulls in the
        // Broadcast::channel() authorization callbacks from
        // routes/channels.php, nothing route-related.
        require base_path('routes/channels.php');
    }
}
