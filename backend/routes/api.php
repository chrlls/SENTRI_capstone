<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\DispatcherController;
use App\Http\Controllers\IncidentController;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Route;

Route::post('/auth/register', [AuthController::class, 'register']);
Route::post('/auth/login', [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', [AuthController::class, 'user']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);

    Route::post('/incidents/manual-sos', [IncidentController::class, 'manualSos']);
    Route::post('/incidents/ai-assisted-sos', [IncidentController::class, 'aiAssistedSos']);

    Route::get('/incidents', [IncidentController::class, 'index']);
    Route::get('/incidents/{incident}', [IncidentController::class, 'show']);

    Route::post('/admin/dispatchers', [DispatcherController::class, 'store']);

    // Reverb/Echo private-channel subscription auth (routes/channels.php).
    // Overrides Broadcast::routes()'s own 'web' middleware default with an
    // empty array — this group's enclosing 'auth:sanctum' (plus statefulApi()
    // from bootstrap/app.php) already resolves the user for both Flutter
    // bearer tokens and the dashboard's session cookie, so stacking the
    // 'web' group on top would just duplicate/conflict with that.
    Broadcast::routes(['middleware' => []]);
});
