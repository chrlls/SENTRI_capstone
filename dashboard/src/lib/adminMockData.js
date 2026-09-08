/**
 * Frontend presentation mock data for the Admin Dashboard Overview page
 * ONLY. None of this is sourced from the backend — no endpoint for account
 * counts, system health, or an admin activity feed exists yet (confirmed
 * against API_CONTRACTS.md/TASK_CHECKLIST.md during the pre-implementation
 * audit). Timestamps are computed relative to load time so they stay
 * plausible across sessions instead of drifting into the past. Replace this
 * file's role with real API calls once those endpoints are designed and
 * verified — do not extend it into a stand-in backend.
 */

/**
 * Five KPI cards, one flat row. `previousValue`/`previousPeriod` drive a
 * real, derived trend (computed in AdminOverviewPage, not typed here)
 * rather than a hand-picked "15.5%" — matches SENTRI's own "Precision:
 * every value is exact, never approximate" principle.
 *
 * `goodDirection` ('up' or 'down') says which direction is favorable for
 * that specific metric — the trend pill's color is derived by comparing
 * the *actual* direction against it (positive = matches, caution =
 * doesn't), not a static per-card label. That distinction matters here:
 * more pending verifications is always bad (goodDirection: 'down'), but
 * a falling false-alarm rate is good news and must render green, not
 * amber, so the color can't be hardcoded independent of which way the
 * number actually moved. `Incidents Today` is the one exception —
 * raw incident volume has no inherently good direction, so it keeps an
 * explicit `tone: 'neutral'` override instead of a `goodDirection`.
 *
 * `deltaMode: 'points'` (False Alarm Rate only) computes a plain
 * percentage-point difference instead of a relative percent-of-a-percent
 * change — treating a percentage value like a count would be
 * mathematically correct but reads as misleadingly tiny/odd; a point
 * difference ("+0.03pp") is the standard, honest way that kind of delta
 * is expressed.
 */
export const ADMIN_KPI_STATS = [
  {
    key: 'pending-verification',
    label: 'Pending Responder Verification',
    goodDirection: 'down',
    value: 6,
    previousValue: 5,
    previousPeriod: 'last week',
  },
  {
    key: 'verified-responders',
    label: 'Verified Responders',
    goodDirection: 'up',
    value: 48,
    previousValue: 43,
    previousPeriod: 'last month',
  },
  {
    key: 'registered-users',
    label: 'Registered Users',
    goodDirection: 'up',
    value: 312,
    previousValue: 284,
    previousPeriod: 'last month',
  },
  {
    key: 'incidents-today',
    label: 'Incidents Today',
    tone: 'neutral',
    value: 23,
    previousValue: 19,
    previousPeriod: 'yesterday',
  },
  {
    key: 'false-alarm-rate',
    label: 'False Alarm Rate',
    goodDirection: 'down',
    deltaMode: 'points',
    value: 8.2,
    previousValue: 9.5,
    previousPeriod: 'last month',
    suffix: '%',
  },
]

/**
 * Colors are written explicitly per trigger source, here next to the
 * data they belong to, rather than left to Recharts' default
 * assign-by-array-index behavior — so the mapping survives the data
 * being reordered or filtered. `manual_sos` is a distinct neutral gray
 * (it's the baseline "someone pressed the button" case); the three
 * AI-assisted/passive detection paths form one 3-step monochrome family
 * (light to dark = voice → keyword → movement) so they read as a related
 * group, distinct from the manual case. No Crimson Blaze anywhere here —
 * see index.css's --chart-1..5 comment for why.
 */
export const TRIGGER_SOURCE_CONFIG = {
  manual_sos: { label: 'Manual SOS', color: 'var(--chart-5)' },
  voice_distress: { label: 'Voice SOS', color: 'var(--chart-4)' },
  keyword_detected: { label: 'Keyword Detected', color: 'var(--chart-3)' },
  movement_anomaly: { label: 'Movement Anomaly', color: 'var(--chart-1)' },
}

/** sin-based deterministic pseudo-random, not Math.random() — same seed always produces the same value, so screenshots and the numbers in this file stay stable across runs. */
function seeded(seed) {
  const x = Math.sin(seed) * 10000
  return x - Math.floor(x)
}

function dayLabel(daysAgo) {
  const date = new Date()
  date.setDate(date.getDate() - daysAgo)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

/**
 * Deterministic daily trigger-source series for the selected date range
 * (7/30/90 days). Day "2 days ago" is a deliberate all-zero day, baked in
 * on purpose — confirms the stacked area chart renders a real gap/flat
 * baseline instead of assuming every day has clean, always-positive data.
 */
export function getIncidentTrendSeries(rangeDays) {
  const rows = []
  for (let daysAgo = rangeDays - 1; daysAgo >= 0; daysAgo--) {
    if (daysAgo === 2) {
      rows.push({ date: dayLabel(daysAgo), manual_sos: 0, voice_distress: 0, keyword_detected: 0, movement_anomaly: 0 })
      continue
    }
    const seed = daysAgo * 7.13
    rows.push({
      date: dayLabel(daysAgo),
      manual_sos: 3 + Math.floor(seeded(seed) * 6),
      voice_distress: 1 + Math.floor(seeded(seed + 1) * 4),
      keyword_detected: Math.floor(seeded(seed + 2) * 3),
      movement_anomaly: Math.floor(seeded(seed + 3) * 3),
    })
  }
  return rows
}

/**
 * Deterministic daily dispatch-time series (minutes), median (p50) and
 * 90th percentile (p90). Day "5 days ago" is a deliberate wide-divergence
 * point baked in on purpose (a calm ~3.7min median next to a ~21min
 * tail) — a p90 that always hugs the median would prove nothing about
 * whether this chart is actually legible at half width.
 */
export function getDispatchTimeSeries(rangeDays) {
  const rows = []
  for (let daysAgo = rangeDays - 1; daysAgo >= 0; daysAgo--) {
    if (daysAgo === 5) {
      rows.push({ date: dayLabel(daysAgo), p50: 3.7, p90: 21.4 })
      continue
    }
    const seed = daysAgo * 3.31
    const p50 = 2.5 + seeded(seed) * 3
    const p90 = p50 + 3 + seeded(seed + 1) * 5
    rows.push({ date: dayLabel(daysAgo), p50: Number(p50.toFixed(1)), p90: Number(p90.toFixed(1)) })
  }
  return rows
}

/**
 * Incidents by barangay, sorted descending. "Unresolved" is a real,
 * documented gap, not a fabricated edge case — TASK_CHECKLIST.md
 * confirms real Tagum City barangay boundary data isn't fully populated
 * yet, so a share of incidents genuinely can't resolve to a boundary.
 * Named barangays reuse the ones already established in
 * ADMIN_RECENT_ACTIVITY below, for consistency.
 */
export const ADMIN_BARANGAY_INCIDENTS = [
  { barangay: 'Poblacion District', count: 34 },
  { barangay: 'Magugpo Poblacion', count: 27 },
  { barangay: 'Visayan Village', count: 19 },
  { barangay: 'La Filipina', count: 14 },
  { barangay: 'Apokon', count: 9 },
  { barangay: 'Canocotan', count: 6 },
  { barangay: 'Unresolved (no boundary match)', count: 5 },
]

/**
 * Read-only preview for the Pending Responder Verification KPI — names,
 * barangay, days waiting, no functioning approve/reject actions (that's
 * User Management's job once it has a real backend endpoint, Decision
 * 19). Six rows, matching the KPI count exactly. The last row is a
 * deliberate outlier (47 days vs. 2-9 for the rest) baked in on purpose
 * to see whether a long-tail wait needs different visual treatment.
 */
export const ADMIN_VERIFICATION_QUEUE = [
  { key: 'vq-1', name: 'Ramon Cruz', barangay: 'Poblacion District', daysWaiting: 2 },
  { key: 'vq-2', name: 'Liza Fernandez', barangay: 'Visayan Village', daysWaiting: 3 },
  { key: 'vq-3', name: 'Noel Bautista', barangay: 'Magugpo Poblacion', daysWaiting: 4 },
  { key: 'vq-4', name: 'Aira Mendoza', barangay: 'La Filipina', daysWaiting: 6 },
  { key: 'vq-5', name: 'Carlo Villanueva', barangay: 'Apokon', daysWaiting: 9 },
  { key: 'vq-6', name: 'Ederlyn Reyes', barangay: 'Canocotan', daysWaiting: 47 },
]

function minutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60_000).toISOString()
}

export const ADMIN_RECENT_ACTIVITY = [
  {
    key: 'act-1',
    icon: 'user-plus',
    title: 'Dispatcher account created',
    description: 'New PNP dispatcher account provisioned — Unit 14, Poblacion District',
    actor: 'Admin — R. Santos',
    occurredAt: minutesAgo(12),
  },
  {
    key: 'act-2',
    icon: 'badge-check',
    title: 'Responder verification updated',
    description: 'Barangay tanod application approved — Visayan Village',
    actor: 'Admin — R. Santos',
    occurredAt: minutesAgo(47),
  },
  {
    key: 'act-3',
    icon: 'settings',
    title: 'System configuration updated',
    description: 'Realtime notification thresholds adjusted',
    actor: 'Admin — M. Dela Cruz',
    occurredAt: minutesAgo(126),
  },
  {
    key: 'act-4',
    icon: 'log-in',
    title: 'Administrative login recorded',
    description: 'Admin session started from Tagum City HQ',
    actor: 'Admin — M. Dela Cruz',
    occurredAt: minutesAgo(214),
  },
  {
    key: 'act-5',
    icon: 'user-plus',
    title: 'Dispatcher account created',
    description: 'New PNP dispatcher account provisioned — Unit 09, Magugpo Poblacion',
    actor: 'Admin — R. Santos',
    occurredAt: minutesAgo(365),
  },
]
