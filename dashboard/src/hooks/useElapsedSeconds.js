import { useEffect, useState } from 'react'
import { parseApiTimestamp } from '@/lib/utils'

/**
 * Live seconds-elapsed-since-`timestamp`, re-rendering once a second.
 * The interval only forces a re-render (`setTick`) — the actual value is
 * recomputed from `Date.now()` each render, not accumulated, so it can
 * never drift from wall-clock time the way a naive `count + 1` timer
 * would after a background tab throttles `setInterval`.
 */
export function useElapsedSeconds(timestamp) {
  const [, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => setTick((tick) => tick + 1), 1000)
    return () => clearInterval(interval)
  }, [])

  const since = parseApiTimestamp(timestamp)
  if (since === null || Number.isNaN(since.getTime())) {
    return null
  }

  return Math.max(0, Math.floor((Date.now() - since.getTime()) / 1000))
}
