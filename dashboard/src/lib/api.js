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

async function apiRequest(path, options = {}) {
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
