import { useEffect, useRef } from 'react'
import { getEcho } from '@/lib/echo'

/**
 * Subscribes to the private `incidents.dashboard` channel
 * (docs/decisions/25-realtime-reverb.md) and invokes `onIncidentCreated`
 * for every real-time `incident.created` broadcast. The leading `.` in
 * the event name is required — NewIncident::broadcastAs() returns a bare
 * name with no namespace, and without the `.` Echo would prepend its
 * default `App.Events.` namespace and never match the real event name.
 */
export function useIncidentStream(onIncidentCreated) {
  const callbackRef = useRef(onIncidentCreated)

  // Assigning ref.current must happen outside render (react-hooks/refs) —
  // an effect with no dependency array runs after every render, which is
  // exactly the "keep this ref pointed at the latest callback" pattern.
  useEffect(() => {
    callbackRef.current = onIncidentCreated
  })

  useEffect(() => {
    const echo = getEcho()
    const channel = echo.private('incidents.dashboard')

    channel.listen('.incident.created', (incident) => {
      callbackRef.current(incident)
    })

    return () => {
      echo.leave('incidents.dashboard')
    }
  }, [])
}
