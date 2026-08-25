import { clsx } from "clsx";
import { twMerge } from "tailwind-merge"

export function cn(...inputs) {
  return twMerge(clsx(inputs));
}

/**
 * The API returns Postgres timestamptz strings ("2026-08-24 12:58:20.66396+00"
 * — space separator, colon-less offset), which `new Date(...)` doesn't
 * reliably parse across browsers. Normalizes to ISO 8601 first.
 */
export function parseApiTimestamp(timestamp) {
  if (!timestamp) {
    return null
  }

  const isoLike = timestamp.replace(' ', 'T').replace(/([+-]\d{2})$/, '$1:00')
  return new Date(isoLike)
}

const RELATIVE_UNITS = [
  { limit: 3600, divisor: 60, unit: 'm ago' },
  { limit: 86400, divisor: 3600, unit: 'h ago' },
  { limit: 604800, divisor: 86400, unit: 'd ago' },
]

export function formatRelativeTime(timestamp) {
  const date = parseApiTimestamp(timestamp)
  if (date === null || Number.isNaN(date.getTime())) {
    return 'unknown time'
  }

  const seconds = Math.max(0, (Date.now() - date.getTime()) / 1000)

  if (seconds < 60) {
    return 'just now'
  }

  for (const { limit, divisor, unit } of RELATIVE_UNITS) {
    if (seconds < limit) {
      return `${Math.floor(seconds / divisor)}${unit}`
    }
  }

  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

/** "dashboard_alerted" -> "Dashboard Alerted". Shared by every enum-ish field the API returns (status, trigger_source). */
export function humanizeEnum(value) {
  if (!value) {
    return '—'
  }

  return value
    .split('_')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}
