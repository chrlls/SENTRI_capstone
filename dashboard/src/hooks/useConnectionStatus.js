import { useEffect, useState } from 'react'
import { getEcho } from '@/lib/echo'

/**
 * The real Pusher connection state backing Reverb (Decision 25), not a
 * decorative always-on dot — `getEcho()` returns the app's one lazily
 * created Echo singleton (shared with useIncidentStream), and
 * `.connector.pusher.connection` is pusher-js's real connection object,
 * whose `state` is one of 'initialized' | 'connecting' | 'connected' |
 * 'unavailable' | 'failed' | 'disconnected'. A dispatcher relying on this
 * indicator to know whether new incidents will actually arrive live
 * deserves the real state, not a hardcoded "connected".
 */
export function useConnectionStatus() {
  const [state, setState] = useState(() => getEcho().connector.pusher.connection.state)

  useEffect(() => {
    const connection = getEcho().connector.pusher.connection
    const handleStateChange = ({ current }) => setState(current)

    connection.bind('state_change', handleStateChange)
    return () => connection.unbind('state_change', handleStateChange)
  }, [])

  return state
}
