const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8000'

/**
 * Thrown by login() carrying the API's own message, so the UI never
 * hardcodes a copy of the backend's generic-error string (which could
 * drift from what the backend actually returns).
 */
export class AuthError extends Error {
  constructor(message, status) {
    super(message)
    this.name = 'AuthError'
    this.status = status
  }
}

/**
 * Thrown by the incident endpoints on any non-2xx response. Callers branch
 * on `status` rather than message text: 401 means the session died mid-use
 * (ProtectedRoute only checks auth at route-match time, so a stale session
 * needs this to trigger a redirect itself); 404 means either the incident
 * doesn't exist or the caller isn't authorized to view it — deliberately
 * indistinguishable per docs/decisions/21-role-based-authorization.md, so
 * callers must not try to tell those two apart from this error alone.
 */
export class ApiError extends Error {
  constructor(message, status) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

function readXsrfTokenCookie() {
  const match = document.cookie.match(/(?:^|; )XSRF-TOKEN=([^;]*)/)
  return match ? decodeURIComponent(match[1]) : null
}

/**
 * Sanctum SPA cookie mode (Decision 23): must be called before any
 * state-changing request so the browser holds a session + XSRF-TOKEN
 * cookie pair to send back as the X-XSRF-TOKEN header below.
 */
async function ensureCsrfCookie() {
  await fetch(`${API_BASE_URL}/sanctum/csrf-cookie`, {
    credentials: 'include',
    headers: { Accept: 'application/json' },
  })
}

/**
 * Exported (not just used internally) so the Reverb Echo hook can issue
 * the `/api/broadcasting/auth` POST through the exact same CSRF/cookie
 * handling as every other authenticated request in this app, rather than
 * duplicating that logic in a second fetch wrapper.
 */
export async function apiRequest(path, options = {}) {
  const headers = new Headers(options.headers)
  headers.set('Accept', 'application/json')

  if (options.method && options.method !== 'GET') {
    headers.set('Content-Type', 'application/json')

    const xsrfToken = readXsrfTokenCookie()
    if (xsrfToken) {
      headers.set('X-XSRF-TOKEN', xsrfToken)
    }
  }

  return fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers,
    credentials: 'include',
  })
}

/**
 * "Is there already a valid session" check for page load/refresh.
 * Returns null on any non-2xx response (no session, or session expired)
 * rather than throwing — that's the expected, common case, not an error.
 */
export async function fetchCurrentUser() {
  const response = await apiRequest('/api/user')

  if (!response.ok) {
    return null
  }

  return response.json()
}

export async function login(email, password) {
  await ensureCsrfCookie()

  const response = await apiRequest('/api/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  })

  const data = await response.json().catch(() => null)

  if (!response.ok) {
    throw new AuthError(data?.message ?? 'Login failed.', response.status)
  }

  return data.user
}

export async function logout() {
  await apiRequest('/api/auth/logout', { method: 'POST' })
}

/**
 * Role-scoped by the backend itself (Decision 21) — a civilian/responder
 * token would only ever see their own/matched incidents; this app only
 * ever calls it with a pnp/admin dispatcher session, so callers here
 * always see every incident, unrestricted.
 */
export async function fetchIncidents() {
  const response = await apiRequest('/api/incidents')

  if (!response.ok) {
    throw new ApiError('Failed to load incidents.', response.status)
  }

  const data = await response.json()
  return data.incidents
}

/**
 * A 404 here means either the incident doesn't exist or this dispatcher
 * isn't authorized to view it — both cases are handled identically by
 * design (Decision 21), so this never tries to distinguish them.
 */
export async function fetchIncident(incidentId) {
  const response = await apiRequest(`/api/incidents/${incidentId}`)

  if (!response.ok) {
    throw new ApiError('Failed to load incident.', response.status)
  }

  return response.json()
}

/**
 * pnp/admin-only server-side (Decision 27's 'update-incident-status'
 * Gate, enforced inside UpdateIncidentStatusRequest itself rather than
 * the controller — see that class for why). dispatcherNotes is only
 * sent when non-empty; the backend leaves the column untouched when the
 * field is omitted rather than overwriting it with an empty string.
 */
export async function updateIncidentStatus(incidentId, status, dispatcherNotes) {
  await ensureCsrfCookie()

  const body = { status }
  if (dispatcherNotes) {
    body.dispatcher_notes = dispatcherNotes
  }

  const response = await apiRequest(`/api/incidents/${incidentId}/status`, {
    method: 'PATCH',
    body: JSON.stringify(body),
  })

  const data = await response.json().catch(() => null)

  if (!response.ok) {
    throw new ApiError(data?.message ?? 'Failed to update incident status.', response.status)
  }

  return data
}

/**
 * Admin-only server-side (Decision 26's 'create-dispatcher' Gate); this
 * client-side call succeeding or failing doesn't determine access, that
 * Gate does. Never issues a token — the new dispatcher logs in separately.
 */
export async function createDispatcher({ email, phoneNumber, password, fullName }) {
  await ensureCsrfCookie()

  const response = await apiRequest('/api/admin/dispatchers', {
    method: 'POST',
    body: JSON.stringify({
      email,
      phone_number: phoneNumber,
      password,
      full_name: fullName,
    }),
  })

  const data = await response.json().catch(() => null)

  if (!response.ok) {
    throw new ApiError(data?.message ?? 'Failed to create dispatcher account.', response.status)
  }

  return data
}

/**
 * The `incident.created` broadcast payload (App\Events\NewIncident) only
 * carries the fields available at creation time — narrower than
 * `fetchIncidents()`'s summary shape. Padding it out with the same
 * defaults a freshly created incident actually has in the database lets
 * list rendering code treat both sources identically.
 */
export function normalizeStreamedIncident(incident) {
  return {
    ...incident,
    ai_confidence_score: null,
    dispatched_by: null,
    dispatched_at: null,
    updated_at: incident.created_at,
    resolved_at: null,
  }
}
