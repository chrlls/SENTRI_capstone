import { test, expect } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const API_BASE_URL = 'http://localhost:8000'
const BACKEND_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../backend')

/**
 * Covers the map-centered dispatcher console shell (dispatcher-console
 * redesign, Phase 3): old DispatcherHeader top bar gone on `/`, floating
 * corner controls, needs-review rail, bottom filter strip toggling
 * marker visibility, and marker click-through to `/incidents/:id` still
 * working. Fixture pattern mirrors incident-status-actions.spec.js — a
 * fresh pnp/civilian pair created via tinker/register per run, torn down
 * in afterAll, nothing long-lived.
 */
function runTinker(phpCode) {
  return execFileSync('php', ['artisan', 'tinker', '--execute', phpCode], {
    cwd: BACKEND_DIR,
    encoding: 'utf-8',
  }).trim()
}

let dispatcher
const createdIncidentIds = []
const createdCivilianEmails = []

test.beforeAll(() => {
  const suffix = randomBytes(6).toString('hex')
  const email = `e2e.dispatcher.${suffix}@sentri.test`
  const password = randomBytes(12).toString('hex')

  const userId = runTinker(`
    echo DB::selectOne(
      "INSERT INTO users (email, phone_number, password_hash, full_name, role, status) VALUES (?, ?, ?, ?, 'pnp', 'active') RETURNING user_id",
      ['${email}', '+639171${suffix.slice(0, 6)}', bcrypt('${password}'), 'E2E Queue Shell Dispatcher (transient)']
    )->user_id;
  `)

  dispatcher = { email, password, userId }
})

test.afterAll(() => {
  if (createdIncidentIds.length > 0) {
    const idList = createdIncidentIds.map((id) => `'${id}'`).join(',')
    runTinker(`
      DB::table('incident_notifications')->whereIn('incident_id', [${idList}])->delete();
      DB::table('incident_status_history')->whereIn('incident_id', [${idList}])->delete();
      DB::table('incidents')->whereIn('incident_id', [${idList}])->delete();
    `)
  }

  if (createdCivilianEmails.length > 0) {
    const emailList = createdCivilianEmails.map((e) => `'${e}'`).join(',')
    runTinker(`DB::table('users')->whereIn('email', [${emailList}])->delete();`)
  }

  if (dispatcher) {
    runTinker(`DB::table('users')->where('user_id', '${dispatcher.userId}')->delete();`)
  }
})

async function createIncident(request, { lat, lon }) {
  const uniqueSuffix = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-9)
  const civilianEmail = `e2e.civilian.${uniqueSuffix}@sentri.test`
  createdCivilianEmails.push(civilianEmail)

  const registerResponse = await request.post(`${API_BASE_URL}/api/auth/register`, {
    data: {
      full_name: 'E2E Civilian',
      email: civilianEmail,
      phone_number: `+63918${uniqueSuffix}`,
      password: 'TestPass123!',
      password_confirmation: 'TestPass123!',
      agreement_accepted: true,
      role: 'civilian',
    },
  })
  expect(registerResponse.ok()).toBeTruthy()

  const civilianLogin = await request.post(`${API_BASE_URL}/api/auth/login`, {
    data: { email: civilianEmail, password: 'TestPass123!' },
  })
  const { token: civilianToken } = await civilianLogin.json()

  const incidentResponse = await request.post(`${API_BASE_URL}/api/incidents/manual-sos`, {
    headers: { Authorization: `Bearer ${civilianToken}` },
    data: { latitude: lat, longitude: lon },
  })
  const { incident_id: incidentId } = await incidentResponse.json()
  createdIncidentIds.push(incidentId)

  return incidentId
}

async function patchStatus(request, token, incidentId, status, notes) {
  const body = notes ? { status, dispatcher_notes: notes } : { status }
  const response = await request.patch(`${API_BASE_URL}/api/incidents/${incidentId}/status`, {
    headers: { Authorization: `Bearer ${token}` },
    data: body,
  })
  expect(response.ok()).toBeTruthy()
}

test('map-centered queue shell renders, filters, and marker click-through still reaches the detail page', async ({
  page,
  request,
}) => {
  // The real Supabase-pooler round-trip (ap-northeast-1) this fixture setup
  // depends on is documented elsewhere in this suite as occasionally slow —
  // the default 30s test timeout is too tight for this test's several
  // sequential real requests plus a real page load.
  test.setTimeout(60000)

  const dispatcherLoginResponse = await request.post(`${API_BASE_URL}/api/auth/login`, {
    data: { email: dispatcher.email, password: dispatcher.password },
  })
  const { token: dispatcherToken } = await dispatcherLoginResponse.json()

  await createIncident(request, { lat: 7.4478, lon: 125.8078 })
  const dispatchedId = await createIncident(request, { lat: 7.452, lon: 125.813 })
  await patchStatus(request, dispatcherToken, dispatchedId, 'dispatcher_reviewing')
  await patchStatus(request, dispatcherToken, dispatchedId, 'dispatched', 'Responding unit en route (e2e test)')

  await page.goto('/login')
  await page.getByPlaceholder('Email').fill(dispatcher.email)
  await page.getByPlaceholder('Password').fill(dispatcher.password)
  await page.getByRole('button', { name: 'Login' }).click()
  await page.waitForURL('/')

  // Old top bar is gone.
  await expect(page.locator('header')).toHaveCount(0)

  // MapLibre migration: was `.leaflet-container` — the map is now a single
  // MapLibre GL instance (`.maplibregl-map` is its own root container
  // class), not react-leaflet's MapContainer.
  await expect(page.locator('.maplibregl-map')).toBeVisible()
  await expect(page.getByLabel('Dispatcher menu')).toBeVisible()

  const allFilterButton = page.getByRole('button', { name: /^All/ })
  // Real Supabase-pooler round-trip (ap-northeast-1) is occasionally slow —
  // wait for the real fetched count, not a fixed sleep (same caveat as
  // incident-status-actions.spec.js).
  await expect(allFilterButton).toContainText(/[1-9]/, { timeout: 15000 })

  const dispatchedFilterButton = page.getByRole('button', { name: /^Dispatched/ })
  await expect(dispatchedFilterButton).toContainText(/[1-9]/)

  // MapLibre migration: was `.leaflet-marker-icon` — markers are now real
  // DOM elements created by maplibre-gl's own Marker class (`.maplibregl-
  // marker`), via the adapted map/Map.jsx MapMarker component, not
  // react-leaflet's <Marker>.
  const markerCount = () => page.locator('.maplibregl-marker').count()
  const allCount = await markerCount()

  // The dev DB is shared with other verification runs, so this doesn't
  // assume an exact marker count — only that the filter strip's own
  // displayed "Dispatched" count matches the real number of markers the
  // map actually renders once that filter is active, and that it's
  // strictly fewer than "All" (this run's own dispatched fixture is real
  // and present either way).
  const dispatchedLabel = await dispatchedFilterButton.textContent()
  const dispatchedExpectedCount = Number(dispatchedLabel.match(/\d+/)[0])

  await dispatchedFilterButton.click()
  await expect(page.locator('.maplibregl-marker')).toHaveCount(dispatchedExpectedCount)
  expect(dispatchedExpectedCount).toBeLessThan(allCount)

  // Profile menu shows real identity/role and a working sign-out entry.
  await page.getByLabel('Dispatcher menu').click()
  await expect(page.getByText('E2E Queue Shell Dispatcher (transient)')).toBeVisible()
  await expect(page.getByRole('menuitem', { name: /sign out/i })).toBeVisible()
  await page.keyboard.press('Escape')

  // Marker click-through to the (unstyled, not part of this phase) detail
  // page must still work after the layout restructure. Clicked while still
  // filtered to "Dispatched" rather than "All" — the shared dev DB has many
  // leftover fixtures sitting at the exact same default coordinate, which
  // stacks markers on top of each other and makes a blind first-marker
  // click flaky; this run's own dispatched fixture has a distinct
  // coordinate, so it's the only (or one of very few) marker visible here.
  // Let the marker's fitBounds transition (triggered by the filter switch
  // above) finish settling before Playwright's actionability check
  // requires the element to be positionally stable across frames.
  await page.waitForTimeout(400)
  await page.locator('.maplibregl-marker').first().click()
  await page.waitForURL(/\/incidents\/.+/)
  // The Phase 4 detail panel dropped the old raw "Incident ID" field in
  // favor of humanized reporter/status content — check for the panel's
  // close control instead, present whenever an incident loads regardless
  // of its specific data.
  await expect(page.getByLabel('Close and return to queue')).toBeVisible({ timeout: 15000 })
})
