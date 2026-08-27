<?php

namespace App\Http\Requests;

use App\Models\Incident;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class UpdateIncidentStatusRequest extends FormRequest
{
    /**
     * docs/decisions/27-dispatcher-incident-actions.md: schema.sql encodes
     * only the single dispatch-requires-human rule (chk_dispatch_is_human);
     * which statuses may move to which is an application-layer decision,
     * made explicitly here rather than left implicit. Forward progression
     * through the enum's own documented lifecycle (detected →
     * dashboard_alerted → dispatcher_reviewing → dispatched → resolved),
     * allowing a caller to skip ahead to any later state in that order —
     * nothing in this codebase currently auto-promotes dashboard_alerted/
     * dispatcher_reviewing, so requiring every intermediate click would
     * make the endpoint unusable, not just stricter. false_alarm/cancelled
     * are reachable from any non-terminal state (a report can turn out
     * bogus, or get cancelled, at any point before resolution).
     * resolved is reachable only from dispatched — resolving implies
     * responders were actually sent; an incident that never needed a
     * response is false_alarm, not resolved. The three terminal states
     * have no outgoing transitions (no undo/revert — Decision 27's
     * explicit scope cut). The dashboard mirrors this exact table to
     * decide which action buttons to show; keep both in sync deliberately.
     */
    private const TRANSITIONS = [
        'detected' => ['dashboard_alerted', 'dispatcher_reviewing', 'dispatched', 'false_alarm', 'cancelled'],
        'dashboard_alerted' => ['dispatcher_reviewing', 'dispatched', 'false_alarm', 'cancelled'],
        'dispatcher_reviewing' => ['dispatched', 'false_alarm', 'cancelled'],
        'dispatched' => ['resolved', 'false_alarm', 'cancelled'],
        'resolved' => [],
        'false_alarm' => [],
        'cancelled' => [],
    ];

    /**
     * docs/decisions/27-dispatcher-incident-actions.md's reconciliation
     * addendum (adopted from Decision 29): these three target statuses
     * are where a dispatcher asserts something consequential about the
     * real world (this is real and I'm sending help / this was not a
     * real incident / this is closed) — the audit trail should always
     * carry a human-readable reason for each. dashboard_alerted →
     * dispatcher_reviewing and any → cancelled stay optional; requiring a
     * note there would be friction with no informational value. The
     * dashboard's lib/incidentStatus.js mirrors this exact list.
     */
    private const NOTES_REQUIRED_STATUSES = ['dispatched', 'resolved', 'false_alarm'];

    private ?Incident $incident = null;

    private bool $incidentLoaded = false;

    /**
     * Deliberately does the real Gate check here, unlike every other
     * FormRequest in this app (e.g. CreateDispatcherRequest, which
     * always returns true and defers to a controller-side
     * Gate::authorize() call). rules()/withValidator() below must
     * inspect this specific incident's current status to validate the
     * requested transition — if that lookup ran before authorization,
     * an unauthorized civilian/responder caller could learn a specific
     * incident's existence/current status from validation error
     * differences, which is exactly the class of leak Decision 21
     * deliberately designed around for incident reads. Checking the
     * role first, before any incident-specific lookup, avoids it. Still
     * funnels through the same named Gate as everywhere else — only the
     * call site moves.
     */
    public function authorize(): bool
    {
        return Gate::allows('update-incident-status');
    }

    public function rules(): array
    {
        return [
            'status' => ['required', 'string', Rule::in(array_keys(self::TRANSITIONS))],
            'dispatcher_notes' => ['nullable', 'string'],
        ];
    }

    /**
     * Only reached once authorize() has already confirmed pnp/admin
     * (see above) — safe to look up this specific incident here.
     */
    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            if ($validator->errors()->has('status')) {
                return;
            }

            $incident = $this->incident();

            if ($incident === null) {
                $validator->errors()->add('status', 'Incident not found.');

                return;
            }

            $allowed = self::TRANSITIONS[$incident->status] ?? [];
            $requestedStatus = $this->input('status');

            if (! in_array($requestedStatus, $allowed, true)) {
                $validator->errors()->add(
                    'status',
                    "Cannot transition from '{$incident->status}' to '{$requestedStatus}'.",
                );

                return;
            }

            $notes = $this->input('dispatcher_notes');

            if (in_array($requestedStatus, self::NOTES_REQUIRED_STATUSES, true) && (! is_string($notes) || trim($notes) === '')) {
                $validator->errors()->add(
                    'dispatcher_notes',
                    "dispatcher_notes is required when transitioning to '{$requestedStatus}'.",
                );
            }
        });
    }

    /**
     * Memoized so the controller can reuse the same lookup this class
     * already did for transition validation, instead of a second query.
     */
    public function incident(): ?Incident
    {
        if (! $this->incidentLoaded) {
            $this->incident = Incident::find($this->route('incident'));
            $this->incidentLoaded = true;
        }

        return $this->incident;
    }
}
