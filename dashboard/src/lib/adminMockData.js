/**
 * Frontend presentation mock data for the Admin Dashboard Overview page
 * ONLY. None of this is sourced from the backend — no endpoint for account
 * counts, system health, or an admin activity feed exists yet (confirmed
 * against API_CONTRACTS.md/TASK_CHECKLIST.md during the pre-implementation
 * audit). Timestamps are computed relative to load time so they stay
 * plausible across sessions instead of drifting into the past. Replace this
 * file's role with real API calls once those endpoints are designed and
 * verified — do not extend it into a stand-in backend.
 *
 * ── Internally consistent demo scenario (presentation only) ─────────────
 * One coherent picture is modelled across every figure on the page so the
 * cards never contradict each other in a screenshot:
 *   • Tagum City SENTRI pilot, ~8 incidents/day typical.
 *   • Today is a deliberately busy day: 23 incidents (the "Incidents Today"
 *     KPI), up from 19 yesterday (its "vs yesterday" comparison). The
 *     trigger-source trend's last two points are pinned to exactly 19 and
 *     23 so the chart's right edge agrees with the KPI.
 *   • 30-day incident total ≈ 234 (sum of the trend series) ≈ 232 (sum of
 *     the by-barangay counts). They are tuned to agree, not derived from a
 *     shared source — keep them roughly level if you edit either.
 *   • False Alarm Rate 8.2% ≈ 19 of those ~234 incidents.
 *   • 6 pending responder verifications — surfaced only as the 6 rows in
 *     the Responder Verification Queue below, deliberately NOT as a KPI
 *     card (that count belongs with the queue it refers to).
 */

/**
 * Four KPI cards, one flat row. `previousValue`/`previousPeriod` drive a
 * real, derived trend (computed in AdminOverviewPage, not typed here)
 * rather than a hand-picked "15.5%" — matches SENTRI's own "Precision:
 * every value is exact, never approximate" principle.
 *
 * `goodDirection` ('up' or 'down') says which direction is favorable for
 * that specific metric — the trend indicator's color is derived by
 * comparing the *actual* direction against it (positive = matches,
 * caution = doesn't), not a static per-card label. That distinction
 * matters here: a falling false-alarm rate is good news and must render
 * as a positive (SENTRI blue), while a *rising* one is the genuinely-
 * negative case that renders red — so the color can't be hardcoded
 * independent of which way the number actually moved. `Incidents Today`
 * is the one exception — raw incident volume has no inherently good
 * direction, so it keeps an explicit `tone: 'neutral'` override.
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
    // A literal always-today metric: its "vs yesterday" comparison is
    // deliberately fixed and does NOT follow the Day/Week/Month/Year
    // toggle (unlike the chart section).
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
 * Colors are written explicitly per trigger source, here next to the data
 * they belong to, rather than left to a charting library's assign-by-
 * array-index — so the mapping survives the data being reordered or
 * filtered.
 *
 * The SENTRI brand blue (#1362FE) and a tint scale of it — Manual SOS on
 * the pure brand colour as the dominant channel, then progressively
 * lighter for Voice SOS, Movement Anomaly and Keyword Detected. Lines
 * stay solid; no area fills, gradients or unrelated hues. The darker
 * SENTRI navies (#031332 / #010919) are text colours, never lines. The
 * legend and an index-mode tooltip (every series' value on hover) carry
 * identity alongside the tint steps.
 */
export const TRIGGER_SOURCE_CONFIG = {
  manual_sos: { label: 'Manual SOS', color: '#1362FE' },
  voice_distress: { label: 'Voice SOS', color: '#4281FE' },
  movement_anomaly: { label: 'Movement Anomaly', color: '#71A0FE' },
  keyword_detected: { label: 'Keyword Detected', color: '#A0C0FE' },
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

/** Same day, with the year — the axis stays terse ("Sep 5"), the tooltip is explicit ("Sep 5, 2026"). */
function dayLabelFull(daysAgo) {
  const date = new Date()
  date.setDate(date.getDate() - daysAgo)
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

/**
 * Deterministic daily trigger-source series for the selected date range
 * (7/30/90 days). Three days are pinned rather than seeded, on purpose:
 *   • Today (daysAgo 0) totals exactly 23 — the "Incidents Today" KPI.
 *   • Yesterday (daysAgo 1) totals exactly 19 — that KPI's comparison.
 *   • daysAgo 2 is a deliberately quiet day (total 3) — a shared dip
 *     across all four lines, without faking an impossible all-zero day
 *     city-wide.
 * Seeded days: a ~3-incident manual baseline plus small per-source noise,
 * an occasional multi-incident surge (~1 day in 6) and an occasional
 * quiet day, so the shape reads like an actual deployment rather than a
 * smooth curve. Source mix works out to roughly Manual 60% / Voice 21% /
 * Movement 13% / Keyword 6%, and a 30-day window sums to ≈ 230 — kept
 * roughly level with ADMIN_BARANGAY_INCIDENTS' total by hand. All values
 * here are mock UI data, not real SENTRI statistics.
 */
const PINNED_TREND_DAYS = {
  0: { manual_sos: 14, voice_distress: 6, movement_anomaly: 1, keyword_detected: 2 },
  1: { manual_sos: 11, voice_distress: 5, movement_anomaly: 1, keyword_detected: 2 },
  2: { manual_sos: 2, voice_distress: 1, movement_anomaly: 0, keyword_detected: 0 },
}

const TRIGGER_KEYS = Object.keys(TRIGGER_SOURCE_CONFIG)

/** Per-source counts for a single day (`daysAgo` back from today) — pinned for days 0–2, otherwise seeded. Any daysAgo is valid, so a prior window can be summed the same way as the visible one. */
function trendRowFor(daysAgo) {
  if (PINNED_TREND_DAYS[daysAgo]) {
    return { ...PINNED_TREND_DAYS[daysAgo] }
  }
  const seed = daysAgo * 7.13
  const surge = seeded(seed + 4) > 0.84 ? 3 + Math.floor(seeded(seed + 5) * 4) : 0
  const quiet = seeded(seed + 6) > 0.82
  return {
    manual_sos: (quiet ? 1 : 2) + Math.floor(seeded(seed) * 4) + surge,
    voice_distress: (quiet ? 0 : 1) + Math.floor(seeded(seed + 1) * 2),
    movement_anomaly: Math.floor(seeded(seed + 2) * 3),
    keyword_detected: Math.floor(seeded(seed + 3) * 2),
  }
}

/**
 * `endDaysAgo` (default 0) is how many days before today the window ends —
 * 0 for every segment preset and for a custom range ending today; > 0
 * only when the user hand-picks a range that ends in the past. Existing
 * call sites pass a single arg and are unaffected.
 */
export function getIncidentTrendSeries(rangeDays, endDaysAgo = 0) {
  const rows = []
  for (let daysAgo = rangeDays - 1 + endDaysAgo; daysAgo >= endDaysAgo; daysAgo--) {
    rows.push({ date: dayLabel(daysAgo), dateFull: dayLabelFull(daysAgo), ...trendRowFor(daysAgo) })
  }
  return rows
}

/** Sum each trigger source across an inclusive daysAgo window. */
function sumWindow(startDaysAgo, endDaysAgo) {
  const totals = Object.fromEntries(TRIGGER_KEYS.map((key) => [key, 0]))
  for (let daysAgo = startDaysAgo; daysAgo <= endDaysAgo; daysAgo++) {
    const row = trendRowFor(daysAgo)
    for (const key of TRIGGER_KEYS) {
      totals[key] += row[key]
    }
  }
  return totals
}

/**
 * Aggregate companion to the trend chart: each trigger source's total and
 * share of incidents over the selected window, plus its percent change
 * against the window immediately before it (same length). Reads from the
 * same deterministic day generator as getIncidentTrendSeries — mock UI
 * data, not real SENTRI statistics (see this file's header).
 */
export function getTriggerSourceMix(rangeDays, endDaysAgo = 0) {
  const current = sumWindow(endDaysAgo, endDaysAgo + rangeDays - 1)
  const previous = sumWindow(endDaysAgo + rangeDays, endDaysAgo + 2 * rangeDays - 1)
  const total = TRIGGER_KEYS.reduce((sum, key) => sum + current[key], 0)

  return {
    total,
    sources: TRIGGER_KEYS.map((key) => {
      const count = current[key]
      const priorCount = previous[key]
      return {
        key,
        label: TRIGGER_SOURCE_CONFIG[key].label,
        color: TRIGGER_SOURCE_CONFIG[key].color,
        count,
        share: total === 0 ? 0 : count / total,
        deltaPct: priorCount === 0 ? null : Math.round(((count - priorCount) / priorCount) * 100),
      }
    }),
  }
}

/**
 * Deterministic daily dispatch-time series (minutes), median (p50) and
 * 90th percentile (p90). Day "5 days ago" is a deliberate wide-divergence
 * point baked in on purpose (a calm ~3.7min median next to a ~15min
 * tail) — a p90 that always hugs the median would prove nothing about
 * whether this chart is actually legible at half width.
 */
export function getDispatchTimeSeries(rangeDays, endDaysAgo = 0) {
  const rows = []
  for (let daysAgo = rangeDays - 1 + endDaysAgo; daysAgo >= endDaysAgo; daysAgo--) {
    if (daysAgo === 5) {
      // pinned wide-divergence day — P50/P90 formula untouched (Batch 1)
      rows.push({ date: dayLabel(daysAgo), p50: 3.7, p90: 15.2 })
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
 * Incidents by barangay over the last 30 days, sorted descending, counts
 * summing to ≈ 232 (kept roughly level with the 30-day trend series total
 * by hand — see getIncidentTrendSeries). The `unmapped` row is a real,
 * documented data gap, not a fabricated edge case — TASK_CHECKLIST.md
 * confirms Tagum City barangay boundary data isn't fully populated yet,
 * so a share of incidents genuinely can't resolve to a boundary. It
 * carries an explicit `unmapped: true` flag (rather than the chart
 * string-matching its label) so the chart can render it as a distinct,
 * clearly-labelled category instead of letting it look like a real
 * barangay. Named barangays reuse the ones in ADMIN_RECENT_ACTIVITY.
 */
export const ADMIN_BARANGAY_INCIDENTS = [
  { barangay: 'Poblacion District', count: 63 },
  { barangay: 'Magugpo Poblacion', count: 51 },
  { barangay: 'Visayan Village', count: 38 },
  { barangay: 'La Filipina', count: 29 },
  { barangay: 'Apokon', count: 21 },
  { barangay: 'Canocotan', count: 16 },
  { barangay: 'Unmapped incidents', count: 14, unmapped: true },
]

/**
 * Pending responder-verification backlog. The Recent Activity card no
 * longer lists these rows (a pending item is an open task, not a
 * historical event — it would misrepresent it to fold it into the feed);
 * only the count is surfaced there, as an action strip that links to the
 * verification management view. The rows themselves are what that view
 * (User Management, Decision 19 — no real backend endpoint yet) would
 * load. `name` / `barangay` / `daysWaiting` are kept for it.
 */
export const ADMIN_VERIFICATION_QUEUE = [
  { key: 'vq-1', name: 'Ramon Cruz', barangay: 'Poblacion District', daysWaiting: 2 },
  { key: 'vq-2', name: 'Liza Fernandez', barangay: 'Visayan Village', daysWaiting: 3 },
  { key: 'vq-3', name: 'Noel Bautista', barangay: 'Magugpo Poblacion', daysWaiting: 5 },
  { key: 'vq-4', name: 'Aira Mendoza', barangay: 'La Filipina', daysWaiting: 6 },
  { key: 'vq-5', name: 'Carlo Villanueva', barangay: 'Apokon', daysWaiting: 8 },
  { key: 'vq-6', name: 'Ederlyn Reyes', barangay: 'Canocotan', daysWaiting: 11 },
]

function minutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60_000).toISOString()
}

/**
 * One unified activity feed for the Recent Activity table — responder
 * verifications, incident actions, incident status transitions, account
 * changes and system events, newest first (the table re-sorts). Five
 * columns show by default (Type / Activity / Reference / By / Time); the
 * rest are opt-in columns, so every row carries the same field set and a
 * missing field just renders as "—" rather than the table restructuring
 * per row. Tagum City barangay context. Mock UI data — full IDs, IPs,
 * exact timestamps and deeper metadata are the Audit Logs page's job.
 */
export const ADMIN_RECENT_ACTIVITY = [
  {
    key: 'ra-1', type: 'Verification', activity: 'Responder account approved', reference: 'RESP-024',
    by: 'Admin', role: 'Admin', occurredAt: minutesAgo(2),
    location: 'Apokon', status: 'Verified', verificationStatus: 'Approved', responder: 'Ramon Cruz',
  },
  {
    key: 'ra-2', type: 'Incident', activity: 'Incident verified', reference: 'INC-1042',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(8),
    location: 'Apokon', status: 'Verified', priority: 'High', triggerSource: 'Voice SOS',
    aiConfidence: 0.88, incidentId: 'INC-1042',
  },
  {
    key: 'ra-3', type: 'Status', activity: 'Incident → Resolved', reference: 'INC-1039',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(14),
    location: 'Visayan Village', status: 'Resolved', priority: 'Low', triggerSource: 'Manual SOS',
    responder: 'Liza Fernandez', incidentId: 'INC-1039',
  },
  {
    key: 'ra-4', type: 'User', activity: 'New responder account created', reference: 'RESP-031',
    by: 'Admin', role: 'Admin', occurredAt: minutesAgo(21),
    status: 'Pending', verificationStatus: 'Under review', user: 'Noel Bautista',
  },
  {
    key: 'ra-5', type: 'Status', activity: 'Incident → Dispatched', reference: 'INC-1038',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(32),
    location: 'Magugpo', status: 'Dispatched', priority: 'Critical', triggerSource: 'Keyword Detected',
    aiConfidence: 0.95, responder: 'Carlo Villanueva', incidentId: 'INC-1038',
  },
  {
    key: 'ra-6', type: 'Verification', activity: 'Responder verification rejected', reference: 'RESP-022',
    by: 'Admin', role: 'Admin', occurredAt: minutesAgo(47),
    location: 'Canocotan', status: 'Rejected', verificationStatus: 'Rejected', responder: 'Aira Mendoza',
  },
  {
    key: 'ra-7', type: 'Incident', activity: 'Incident priority changed', reference: 'INC-1042',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(52),
    location: 'Apokon', status: 'Verified', priority: 'Critical', triggerSource: 'Voice SOS',
    aiConfidence: 0.88, incidentId: 'INC-1042',
  },
  {
    key: 'ra-8', type: 'Status', activity: 'Incident → Escalated', reference: 'INC-1035',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(62),
    location: 'Mankilam', status: 'Escalated', priority: 'Critical', triggerSource: 'Movement Anomaly',
    aiConfidence: 0.79, incidentId: 'INC-1035',
  },
  {
    key: 'ra-9', type: 'System', activity: 'AI threshold configuration updated', reference: 'SET-014',
    by: 'Admin', role: 'Admin', occurredAt: minutesAgo(68), module: 'AI Detection',
  },
  {
    key: 'ra-10', type: 'User', activity: 'Responder profile updated', reference: 'RESP-024',
    by: 'Admin', role: 'Responder', occurredAt: minutesAgo(120), user: 'Ramon Cruz',
  },
  {
    key: 'ra-11', type: 'System', activity: 'Notification configuration updated', reference: 'SET-011',
    by: 'Admin', role: 'Admin', occurredAt: minutesAgo(135), module: 'Notifications',
  },
  {
    key: 'ra-12', type: 'Incident', activity: 'Incident assigned to responder', reference: 'INC-1037',
    by: 'Dispatcher', role: 'Dispatcher', occurredAt: minutesAgo(190),
    location: 'San Agustin', status: 'Dispatched', priority: 'Medium', triggerSource: 'Manual SOS',
    responder: 'Ederlyn Reyes', incidentId: 'INC-1037',
  },
]
