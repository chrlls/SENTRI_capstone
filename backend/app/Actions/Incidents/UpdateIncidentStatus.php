<?php

namespace App\Actions\Incidents;

use App\Models\Incident;
use Illuminate\Support\Facades\DB;

class UpdateIncidentStatus
{
    /**
     * Persists via Eloquent's normal save() path (not raw SQL) so the
     * existing trg_incident_status_history trigger fires — confirmed to
     * work correctly, including a single-row multi-column save, in
     * docs/decisions/27-dispatcher-incident-actions.md's Phase 1
     * verification. dispatched_by/dispatched_at are only ever set here,
     * server-side, from the authenticated dispatcher — never accepted as
     * request fields, so chk_dispatch_is_human is satisfied by
     * construction rather than by trusting the client.
     */
    public function handle(Incident $incident, string $status, ?string $dispatcherNotes, string $dispatcherId): Incident
    {
        $incident->status = $status;

        if ($dispatcherNotes !== null) {
            $incident->dispatcher_notes = $dispatcherNotes;
        }

        if ($status === 'dispatched') {
            $incident->dispatched_by = $dispatcherId;
            $incident->dispatched_at = now();
        }

        if ($status === 'resolved') {
            $incident->resolved_at = now();
        }

        $incident->save();

        $this->attributeHistoryRow($incident->incident_id, $status, $dispatcherId);

        return $incident->fresh();
    }

    /**
     * log_incident_status_change() (schema.sql) never sets changed_by on
     * the row it inserts — confirmed by reading the trigger function
     * directly — so every history row is changed_by NULL regardless of
     * who made the change, unless something updates it afterward. Every
     * transition through this action is human-driven by definition (it's
     * only ever reached via the pnp/admin-gated status endpoint), so the
     * row the trigger just inserted for this exact transition gets
     * attributed to the dispatcher who made it. Matched by incident_id +
     * new_status + still-NULL changed_by rather than a returned id, since
     * save() doesn't expose the trigger's own insert.
     */
    private function attributeHistoryRow(string $incidentId, string $newStatus, string $dispatcherId): void
    {
        DB::table('incident_status_history')
            ->where('incident_id', $incidentId)
            ->where('new_status', $newStatus)
            ->whereNull('changed_by')
            ->orderByDesc('changed_at')
            ->orderByDesc('history_id')
            ->limit(1)
            ->update(['changed_by' => $dispatcherId]);
    }
}
