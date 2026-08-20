<?php

namespace App\Providers;

use App\Policies\IncidentPolicy;
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
    }
}
