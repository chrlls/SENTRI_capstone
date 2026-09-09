/**
 * Single source of truth for the dashboard's time window. The
 * Day / Week / Month / Year segment buttons and the calendar pill both
 * read and write one `period` object — they can never disagree.
 *
 *   { preset, rangeDays, endDaysAgo, from, to }
 *
 *   • preset      — 'day' | 'week' | 'month' | 'year', or null for a
 *                   hand-picked custom range (no segment highlighted).
 *   • rangeDays   — number of days in the window (drives the mock
 *                   generators in adminMockData.js).
 *   • endDaysAgo  — how many days before today the window ends (0 for
 *                   any preset and for a custom range ending today).
 *   • from / to   — the concrete window, for the pill's label.
 *
 * "today" is the runtime `new Date()` at 00:00, so the window slides with
 * the real clock — there is no frozen fixture date.
 */

const MS_PER_DAY = 86_400_000

/** Days-per-preset. Placeholder mapping for the mockup: Month ≈ 30, Year ≈ 365. */
const PRESET_DAYS = { day: 1, week: 7, month: 30, year: 365 }

export const PERIOD_PRESETS = [
  { key: 'day', label: 'Day' },
  { key: 'week', label: 'Week' },
  { key: 'month', label: 'Month' },
  { key: 'year', label: 'Year' },
]

function startOfDay(date) {
  const next = new Date(date)
  next.setHours(0, 0, 0, 0)
  return next
}

function daysBetween(earlier, later) {
  return Math.round((startOfDay(later).getTime() - startOfDay(earlier).getTime()) / MS_PER_DAY)
}

/** The window for a segment preset: `rangeDays` days ending today. */
export function presetPeriod(presetKey) {
  const rangeDays = PRESET_DAYS[presetKey] ?? PRESET_DAYS.week
  const to = startOfDay(new Date())
  const from = new Date(to.getTime() - (rangeDays - 1) * MS_PER_DAY)
  return { preset: presetKey, rangeDays, endDaysAgo: 0, from, to }
}

/**
 * The window for a hand-picked calendar range. No preset is highlighted.
 * `to` is clamped to today (the mock generators only reach back from
 * today); a range whose `to` is earlier than today is honoured via
 * `endDaysAgo`.
 */
export function customPeriod(range) {
  const today = startOfDay(new Date())
  const to = range?.to ? startOfDay(range.to > today ? today : range.to) : today
  const from = range?.from ? startOfDay(range.from > to ? to : range.from) : to
  return {
    preset: null,
    rangeDays: Math.max(1, daysBetween(from, to) + 1),
    endDaysAgo: Math.max(0, daysBetween(to, today)),
    from,
    to,
  }
}

export const DEFAULT_PERIOD = presetPeriod('week')
