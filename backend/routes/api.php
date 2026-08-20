<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\IncidentController;
use Illuminate\Support\Facades\Route;

Route::post('/auth/register', [AuthController::class, 'register']);
Route::post('/auth/login', [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', [AuthController::class, 'user']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);

    Route::post('/incidents/manual-sos', [IncidentController::class, 'manualSos']);
    Route::post('/incidents/ai-assisted-sos', [IncidentController::class, 'aiAssistedSos']);
});
