import { test, expect } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const API_BASE_URL = 'http://localhost:8000'
const BACKEND_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../backend')

/**
 * docs/decisions/27-dispatcher-incident-actions.md's reconciliation
 * addendum: exercises the dispatcher_reviewing -> dispatched transition
 * through the real UI, including the required dispatcher_notes field.
 *
 * Fixtures: a fresh civilian is registered per run via the real
 * register endpoint (unique email). The pnp dispatcher has no
 * self-registration path (Decision 19/26) and this suite has no admin
 * credentials to call POST /api/admin/dispatchers, so it's created the
 * same way every pnp test account in this project's verification
 * history has been created — a direct INSERT into `users` via
 * `php artisan tinker` (see Decision 26/27's Verified sections) — just
 * invoked here in beforeAll/afterAll instead of by a human running it
 * manually. A prior version of this suite used a persistent hardcoded
 * fixture account (`e2e.dispatcher@sentri.test`); that account has been
 * deleted and this suite no longer depends on any long-lived credential
 * — everything created here (dispatcher, civilian, incident) is
 * generated fresh per run and torn down in afterAll.
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
      ['${email}', '+639170${suffix.slice(0, 6)}', bcrypt('${password}'), 'E2E Dispatcher (transient)']
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

async function createIncidentAwaitingReview(request) {
  const uniqueSuffix = Date.now().toString().slice(-9)
  const civilianEmail = `e2e.civilian.${uniqueSuffix}@sentri.test`
  createdCivilianEmails.push(civilianEmail)

  const registerResponse = await request.post(`${API_BASE_URL}/api/auth/register`, {
    data: {
      full_name: 'E2E Civilian',
      email: civilianEmail,
      phone_number: `+63917${uniqueSuffix}`,
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
    data: { latitude: 7.4478, longitude: 125.8078 },
  })
  const { incident_id: incidentId } = await incidentResponse.json()
  createdIncidentIds.push(incidentId)

  const dispatcherLogin = await request.post(`${API_BASE_URL}/api/auth/login`, {
    data: { email: dispatcher.email, password: dispatcher.password },
  })
  const { token: dispatcherToken } = await dispatcherLogin.json()

  // dashboard_alerted fires automatically on creation (this decision's own
  // fix) — one more PATCH puts it in dispatcher_reviewing, the exact
  // starting state this test exercises through the real UI from here on.
  const reviewResponse = await request.patch(`${API_BASE_URL}/api/incidents/${incidentId}/status`, {
    headers: { Authorization: `Bearer ${dispatcherToken}` },
    data: { status: 'dispatcher_reviewing' },
  })
  expect(reviewResponse.ok()).toBeTruthy()

  return incidentId
}

test('dispatcher can dispatch an incident with required notes through the real UI', async ({ page, request }) => {
  // The real Supabase-pooler round-trip this suite depends on is
  // documented above as occasionally slow; the persistent-queue redesign
  // added a confirm-dialog round trip and queue rendering on top of the
  // same real requests, tightening the default 30s budget.
  test.setTimeout(60000)

  const incidentId = await createIncidentAwaitingReview(request)

  await page.goto('/login')
  await page.getByPlaceholder('Email').fill(dispatcher.email)
  await page.getByPlaceholder('Password').fill(dispatcher.password)
  await page.getByRole('button', { name: 'Login' }).click()

  await page.waitForURL('/')

  await page.goto(`/incidents/${incidentId}`)

  // The real Supabase-hosted DB (ap-northeast-1 pooler) round-trip for
  // GetIncidentDetail's multiple queries occasionally exceeds Playwright's
  // 5s default under real network conditions — not a UI bug, an honest
  // remote-DB latency margin.
  // Scoped to the detail panel's own <header> — the persistent-queue
  // redesign (this same incident's row is simultaneously visible in the
  // left queue, by design) and the History section's real status_history
  // rows both also render "Dispatcher Reviewing" text, so a loose
  // page-wide exact match is now ambiguous; this targets only the header
  // status badge.
  await expect(page.locator('header').getByText('Dispatcher Reviewing', { exact: true })).toBeVisible({ timeout: 15000 })

  // exact:true — the redesigned page's profile-menu trigger has an
  // accessible name of "Dispatcher menu" (Phase 3/4), which a loose match
  // on "Dispatch" would ambiguously match too.
  const dispatchButton = page.getByRole('button', { name: 'Dispatch', exact: true })
  const notesInput = page.getByLabel('Dispatcher notes (required)').first()

  // Required-notes gating: the button must not be clickable before notes
  // are entered, matching the backend's own 422 rule.
  await expect(dispatchButton).toBeDisabled()

  await notesInput.fill('Responding unit en route (e2e test)')
  await expect(dispatchButton).toBeEnabled()

  await dispatchButton.click()

  // Phase 5: clicking the action button now opens a confirm dialog first
  // — the real PATCH doesn't fire until "Confirm" inside it is clicked.
  await expect(page.getByRole('alertdialog', { name: 'Confirm dispatch' })).toBeVisible()
  await page.getByRole('button', { name: 'Confirm' }).click()

  // Pending state, then success reflected in place without a reload.
  await expect(page.getByRole('button', { name: 'Dispatching…' })).toBeVisible()
  // Scoped to the detail panel's own <header> — the persistent-queue
  // redesign keeps this same incident's row visible in the left queue at
  // the same time (that's the point of the redesign), and its own status
  // badge also reads "Dispatched" once the transition lands, so a loose
  // page-wide match is now ambiguous.
  await expect(page.locator('header').getByText('Dispatched', { exact: true })).toBeVisible()
  await expect(page.getByText('Responding unit en route (e2e test)')).toBeVisible()
  await expect(page.getByText('No further actions')).not.toBeVisible()

  // The next valid actions (Resolve/False Alarm) replace Dispatch.
  // exact:true — the persistent-queue redesign's queue rows show
  // "Unresolved location" as a fallback barangay label, which loosely
  // (case-insensitive substring) matches "Resolve" too.
  await expect(page.getByRole('button', { name: 'Resolve', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'False Alarm' })).toBeVisible()
})
