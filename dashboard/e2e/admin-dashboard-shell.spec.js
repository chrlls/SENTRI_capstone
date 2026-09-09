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
  // Pending responder verification is deliberately not a KPI card — it
  // surfaces only as the action strip inside Recent Activity (whose text
  // "N pending responder verifications" is asserted below).
  await expect(page.getByText('Pending Responder Verification', { exact: true })).toHaveCount(0)
  await expect(page.getByText('Incidents by trigger source')).toBeVisible()
  await expect(page.getByText('Time to dispatch')).toBeVisible()
  await expect(page.getByText('Incidents by barangay')).toBeVisible()
  await expect(page.getByText('System health')).toBeVisible()
  await expect(page.getByRole('img', { name: /System health score/ })).toBeVisible()
  // Responder queue + admin activity + status transitions are now one
  // unified, searchable/filterable/sortable Recent Activity table.
  await expect(page.getByRole('heading', { name: 'Administrative Activity' })).toBeVisible()
  await expect(page.getByText('Recent Activity')).toBeVisible()
  await expect(page.getByRole('link', { name: 'View audit logs' })).toBeVisible()
  await expect(page.getByPlaceholder('Search activity...')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Columns' })).toBeVisible()
  await expect(page.getByRole('button', { name: /^Filter/ })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sort' })).toBeVisible()
  await expect(page.getByRole('cell', { name: 'Incident → Resolved' })).toBeVisible()

  // Search narrows the table on local state alone.
  await page.getByPlaceholder('Search activity...').fill('INC-1039')
  await expect(page.getByRole('cell', { name: 'Incident → Resolved' })).toBeVisible()
  await expect(page.getByRole('cell', { name: 'Responder account approved' })).toHaveCount(0)
  await page.getByPlaceholder('Search activity...').clear()
  await expect(page.getByRole('cell', { name: 'Responder account approved' })).toBeVisible()

  // Columns can be reordered from the keyboard (Arrow keys on a header).
  const headerText = () => page.locator('section[aria-label="Administrative activity"] thead th').allInnerTexts()
  expect((await headerText()).map((t) => t.trim())).toEqual(['TYPE', 'ACTIVITY', 'REFERENCE', 'BY', 'TIME'])
  await page
    .locator('section[aria-label="Administrative activity"] thead th')
    .filter({ hasText: 'By' })
    .focus()
  await page.keyboard.press('ArrowLeft')
  expect((await headerText()).map((t) => t.trim())).toEqual(['TYPE', 'ACTIVITY', 'BY', 'REFERENCE', 'TIME'])

  // The period control (Day / Week / Month / Year) drives the time-series
  // charts; Week is selected by default. Both Chart.js and Recharts
  // animate the data transition, so wait for it to settle (past the
  // ~1500ms default) before reading/screenshotting final values.
  await expect(page.getByRole('button', { name: 'Week' })).toHaveAttribute('aria-pressed', 'true')
  await page.getByRole('button', { name: 'Month' }).click()
  await expect(page.getByRole('button', { name: 'Month' })).toHaveAttribute('aria-pressed', 'true')

  // The calendar pill is a view of the active preset's window, not an
  // independent default — switching presets must change what it shows,
  // and exactly one segment is highlighted at a time.
  const rangePill = page.getByRole('button', { name: /^Date range:/ })
  const monthPillText = await rangePill.innerText()
  await page.getByRole('button', { name: 'Week' }).click()
  await expect(page.getByRole('button', { name: 'Week' })).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByRole('button', { name: 'Month' })).toHaveAttribute('aria-pressed', 'false')
  expect(await rangePill.innerText()).not.toBe(monthPillText)
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

  // The admin sidebar no longer carries an in-rail link back to the
  // dispatcher console (removed by design), but the console route itself
  // is unchanged and still renders for an admin session.
  await page.goto('/')
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
  await expect(page.getByText('Recent Activity')).toBeVisible()
  await page.screenshot({ path: `${SCREENSHOT_DIR}/admin-overview-tablet.png` })

  await page.setViewportSize({ width: 390, height: 3400 })
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
  await expect(page.getByLabel('Open admin navigation')).toBeVisible()
  await page.screenshot({ path: `${SCREENSHOT_DIR}/admin-overview-mobile.png` })
})
