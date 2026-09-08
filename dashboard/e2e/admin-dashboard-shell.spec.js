import { test, expect } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const BACKEND_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../backend')
const SCREENSHOT_DIR = 'C:/Users/Charl/AppData/Local/Temp/claude/C--Users-Charl-SENTRI/a988d85b-aa8c-4c36-aa07-eeee33a071b4/scratchpad'

/**
 * Admin Dashboard shell (Phase 1): sidebar/header/Overview render for a
 * real admin session, a not-yet-built section renders its coming-soon
 * placeholder rather than a broken/blank page, and the dispatcher console
 * is unaffected by the one additive change made to it (the new "Admin
 * Dashboard" link in DispatcherCornerControls). Fixture pattern mirrors
 * dispatcher-queue-shell.spec.js — a fresh admin user created via tinker
 * per run, torn down in afterAll.
 */
function runTinker(phpCode) {
  return execFileSync('php', ['artisan', 'tinker', '--execute', phpCode], {
    cwd: BACKEND_DIR,
    encoding: 'utf-8',
  }).trim()
}

let admin

test.beforeAll(() => {
  const suffix = randomBytes(6).toString('hex')
  const email = `e2e.admin.${suffix}@sentri.test`
  const password = randomBytes(12).toString('hex')

  const userId = runTinker(`
    echo DB::selectOne(
      "INSERT INTO users (email, phone_number, password_hash, full_name, role, status) VALUES (?, ?, ?, ?, 'admin', 'active') RETURNING user_id",
      ['${email}', '+639172${suffix.slice(0, 6)}', bcrypt('${password}'), 'E2E Admin Shell (transient)']
    )->user_id;
  `)

  admin = { email, password, userId }
})

test.afterAll(() => {
  if (admin) {
    runTinker(`DB::table('users')->where('user_id', '${admin.userId}')->delete();`)
  }
})

async function loginAsAdmin(page) {
  await page.goto('/login')
  await page.getByPlaceholder('Email').fill(admin.email)
  await page.getByPlaceholder('Password').fill(admin.password)
  await page.getByRole('button', { name: 'Login' }).click()
  await page.waitForURL('/')
}

test('admin dashboard shell renders for a real admin session, dispatcher console unaffected', async ({ page }) => {
  test.setTimeout(60000)

  await loginAsAdmin(page)

  // Dispatcher console is still the landing page for an admin session,
  // unaffected by this phase's work.
  await expect(page.locator('.maplibregl-map')).toBeVisible()
  await expect(page.getByLabel('Dispatcher menu')).toBeVisible()

  // The one additive change to dispatcher chrome: a new admin-only link.
  await page.getByLabel('Dispatcher menu').click()
  await expect(page.getByRole('menuitem', { name: 'Admin Dashboard' })).toBeVisible()
  await page.getByRole('menuitem', { name: 'Admin Dashboard' }).click()
  await page.waitForURL('/admin')

  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByText('Registered Users')).toBeVisible()
  await expect(page.getByText('Verified Responders')).toBeVisible()
  await expect(page.getByText('False Alarm Rate')).toBeVisible()
  await expect(page.getByText('Incidents by trigger source')).toBeVisible()
  await expect(page.getByText('Time to dispatch')).toBeVisible()
  await expect(page.getByText('Incidents by barangay')).toBeVisible()
  await expect(page.getByText('Responder verification queue')).toBeVisible()
  await expect(page.getByText('Ederlyn Reyes')).toBeVisible()
  await expect(page.getByText('Recent administrative activity')).toBeVisible()

  // Date-range control drives the two time-series charts. Recharts
  // animates the transition between old and new data (kept on purpose,
  // not disabled — see IncidentTrendChart.jsx) — wait for it to settle
  // before reading/screenshotting final values, past its ~1500ms default
  // duration, rather than capturing a mid-transition interpolated frame.
  await page.getByRole('button', { name: 'Last 30 days' }).click()
  await page.getByRole('menuitem', { name: 'Last 7 days' }).click()
  await expect(page.getByRole('button', { name: 'Last 7 days' })).toBeVisible()
  await page.waitForTimeout(1800)

  // AdminLayout's content area scrolls inside its own <main> (h-svh +
  // overflow-y-auto on the outer shell), not the document body — a plain
  // `fullPage: true` screenshot only ever captures the first viewport-
  // height slice, never what's below the fold. Size the viewport tall
  // enough that everything fits without needing to scroll, so a single
  // screenshot actually shows the whole page.
  await page.setViewportSize({ width: 1280, height: 2500 })
  await page.screenshot({ path: `${SCREENSHOT_DIR}/admin-overview-desktop.png` })
  await page.setViewportSize({ width: 1280, height: 720 })

  // A not-yet-built section renders its coming-soon placeholder, not a
  // broken route.
  await page.getByRole('navigation', { name: 'Admin navigation' }).getByRole('link', { name: /User Management/ }).click()
  await page.waitForURL('/admin/users')
  await expect(page.getByText(/coming in a later phase/)).toBeVisible()

  // Back to the dispatcher console still works.
  await page.getByRole('link', { name: 'Dispatch console' }).click()
  await page.waitForURL('/')
  await expect(page.locator('.maplibregl-map')).toBeVisible()
})

test('admin dashboard is usable at tablet and mobile widths', async ({ page }) => {
  test.setTimeout(60000)

  await loginAsAdmin(page)
  await page.goto('/admin')
  // page.goto triggers a full reload (a real AuthProvider round-trip, not a
  // client-side route change), which the shared dev DB is occasionally slow
  // to answer under parallel workers — same caveat other specs in this
  // suite already document — so this first check gets a longer timeout.
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 15000 })

  // Same inner-<main>-scrolls-not-the-body caveat as the desktop
  // screenshot above — size tall enough to fit everything in one shot.
  await page.setViewportSize({ width: 834, height: 2700 })
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByText('Responder verification queue')).toBeVisible()
  await page.screenshot({ path: `${SCREENSHOT_DIR}/admin-overview-tablet.png` })

  await page.setViewportSize({ width: 390, height: 3400 })
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByLabel('Open admin navigation')).toBeVisible()
  await page.screenshot({ path: `${SCREENSHOT_DIR}/admin-overview-mobile.png` })
})
