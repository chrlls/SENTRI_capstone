<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Deliberately minimal — every other incident read/write in this codebase
 * goes through raw parameterized SQL for PostGIS geography handling (see
 * IncidentPolicy's docblock). This model exists only so the status-update
 * endpoint (docs/decisions/27) can persist through Eloquent's normal save
 * path, which is what lets trg_incident_status_history fire per Phase 1's
 * verification — it is not used for incident creation or the geography
 * column, and nothing here attempts to cast `location`.
 */
class Incident extends Model
{
    protected $table = 'incidents';

    protected $primaryKey = 'incident_id';

    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'status',
        'dispatched_by',
        'dispatched_at',
        'dispatcher_notes',
        'resolved_at',
    ];

    protected function casts(): array
    {
        return [
            'dispatched_at' => 'datetime',
            'resolved_at' => 'datetime',
            'ai_confidence_score' => 'float',
        ];
    }
}
