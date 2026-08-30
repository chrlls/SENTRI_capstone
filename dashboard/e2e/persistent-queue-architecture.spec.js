import { test, expect } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const API_BASE_URL = 'http://localhost:8000'
const BACKEND_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../backend')

/**
 * Covers the persistent-queue architecture's two core claims (dispatcher-
 * console redesign, final phase): the map is a single instance that never
 * remounts when an incident's detail opens/closes (previously it did —
 * /incidents/:id was a sibling route, not nested under /), and the queue
 * stays visible and live while a detail panel is open (previously the
 * whole queue page unmounted). Fixture pattern mirrors the project's
 * other real-backend specs — fresh accounts per run, torn down after.
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
  const email = `e2e.pq-dispatcher.${suffix}@sentri.test`
  const password = randomBytes(12).toString('hex')

  const userId = runTinker(`
    echo DB::selectOne(
      "INSERT INTO users (email, phone_number, password_hash, full_name, role, status) VALUES (?, ?, ?, ?, 'pnp', 'active') RETURNING user_id",
      ['${email}', '+639172${suffix.slice(0, 6)}', bcrypt('${password}'), 'E2E Persistent-Queue Dispatcher (transient)']
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
  const civilianEmail = `e2e.pq-civilian.${uniqueSuffix}@sentri.test`
  createdCivilianEmails.push(civilianEmail)

  const registerResponse = await request.post(`${API_BASE_URL}/api/auth/register`, {
    data: {
      full_name: 'E2E Civilian',
      email: civilianEmail,
      phone_number: `+63919${uniqueSuffix}`,
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

  return { incidentId, civilianToken }
}

test('map instance persists (no remount) and the queue stays live while a detail panel is open', async ({
  page,
  request,
}) => {
  test.setTimeout(60000)

  await createIncident(request, { lat: 7.4478, lon: 125.8078 })

  await page.goto('/login')
  await page.getByPlaceholder('Email').fill(dispatcher.email)
  await page.getByPlaceholder('Password').fill(dispatcher.password)
  await page.getByRole('button', { name: 'Login' }).click()
  await page.waitForURL('/')

  const queue = page.getByLabel('Incident queue')
  await expect(queue.locator('button').first()).toBeVisible({ timeout: 15000 })
  // Let FitToIncidents' own effect (single-incident jumpTo zoom 15) and
  // the resulting 'zoom' event -> ZoomControl re-render fully settle
  // before manually zooming further — otherwise it can race with the
  // zoom-in clicks below.
  await page.waitForTimeout(2500)

  // --- Map instance must not remount when a detail opens ---
  // MapLibre migration: was read via the Leaflet tile <img> src's own
  // {z}/{y}/{x} URL (no such element exists for MapLibre's WebGL-rendered
  // vector tiles). Same underlying proof, adapted mechanism: zoom in past
  // MIN_ZOOM using the real Zoom In control, then confirm "Zoom out" is
  // enabled (aria-disabled="false") — meaning the map is above MIN_ZOOM,
  // a state a *remount* would immediately erase by resetting to
  // OVERVIEW_ZOOM (which equals MIN_ZOOM in IncidentMap.jsx, disabling
  // "Zoom out" again). A real, sustained "Zoom out enabled" reading
  // right after navigation is direct proof the same map instance
  // survived, not an assumption from the route config alone.
  const zoomInButton = page.getByRole('button', { name: 'Zoom in' })
  const zoomOutButton = page.getByRole('button', { name: 'Zoom out' })
  for (let i = 0; i < 5; i++) {
    if ((await zoomInButton.getAttribute('aria-disabled')) === 'true') {
      break
    }
    // A short per-click timeout with a retry, not one long blocking click:
    // the button's own enabled state is driven by a real 'zoom' event
    // listener (ZoomControl in IncidentMap.jsx), so a click landing in the
    // narrow window right after a jumpTo/flyTo fires but before that
    // listener's state update has re-rendered can transiently read as
    // "not enabled" — worth a quick retry, not a 60s stall.
    try {
      await zoomInButton.click({ timeout: 3000 })
    } catch {
      await page.waitForTimeout(500)
      continue
    }
    await page.waitForTimeout(350)
  }
  await expect(zoomOutButton).toHaveAttribute('aria-disabled', 'false')

  await queue.locator('button').first().click()
  await page.waitForURL(/\/incidents\/.+/)
  await expect(page.getByLabel('Close and return to queue')).toBeVisible({ timeout: 15000 })
  await page.waitForTimeout(1000) // let FocusSelectedIncident's flyTo settle

  await expect(zoomOutButton).toHaveAttribute('aria-disabled', 'false')

  // --- Queue stays visible while the panel is open ---
  await expect(queue.locator('button').first()).toBeVisible()
  const countBefore = await queue.locator('button').count()

  // --- Queue stays live (real Reverb broadcast, not a poll/reload) while the panel is open ---
  const { incidentId: streamedId } = await createIncident(request, { lat: 7.46, lon: 125.79 })
  await expect(queue.locator('button')).toHaveCount(countBefore + 1, { timeout: 10000 })

  // --- Deep link still works: a cold direct load of /incidents/:id renders
  // correctly with both the layout's list fetch and the route's own
  // incident fetch firing together (the banner-collision fix). ---
  await page.goto(`/incidents/${streamedId}`)
  await expect(page.getByLabel('Close and return to queue')).toBeVisible({ timeout: 15000 })
  await expect(queue.locator('button').first()).toBeVisible({ timeout: 15000 })
})
