import Echo from 'laravel-echo'
import Pusher from 'pusher-js'
import { apiRequest } from '@/lib/api'

let echoInstance = null

/**
 * Lazily created (only pages that actually subscribe to the incident
 * stream pay for opening a socket). Reverb speaks the Pusher protocol, so
 * `broadcaster: 'reverb'` still goes through Echo's Pusher connector —
 * `Pusher` must be passed explicitly since nothing here sets
 * `window.Pusher` globally (see laravel-echo's PusherConnector.connect()).
 *
 * `authorizer` replaces Echo's default XHR-based channel auth with the
 * same CSRF/cookie-based apiRequest() every other call in this app uses —
 * necessary for two reasons: (1) Echo's default `authEndpoint` is the
 * relative `/broadcasting/auth`, but this app's actual route lives at
 * `/api/broadcasting/auth` (docs/decisions/25-realtime-reverb.md's
 * routing fix), and (2) the default XHR auth doesn't send the
 * `X-XSRF-TOKEN` header or `credentials: include` this app's Sanctum SPA
 * cookie session (Decision 23) requires.
 */
export function getEcho() {
  if (echoInstance !== null) {
    return echoInstance
  }

  echoInstance = new Echo({
    broadcaster: 'reverb',
    Pusher,
    key: import.meta.env.VITE_REVERB_APP_KEY,
    wsHost: import.meta.env.VITE_REVERB_HOST,
    wsPort: import.meta.env.VITE_REVERB_PORT,
    wssPort: import.meta.env.VITE_REVERB_PORT,
    forceTLS: (import.meta.env.VITE_REVERB_SCHEME ?? 'https') === 'https',
    enabledTransports: ['ws', 'wss'],
    authorizer: (channel) => ({
      authorize: async (socketId, callback) => {
        try {
          const response = await apiRequest('/api/broadcasting/auth', {
            method: 'POST',
            body: JSON.stringify({ socket_id: socketId, channel_name: channel.name }),
          })

          if (!response.ok) {
            throw new Error(`Channel authorization failed (${response.status})`)
          }

          callback(null, await response.json())
        } catch (error) {
          callback(error, null)
        }
      },
    }),
  })

  return echoInstance
}

export function disconnectEcho() {
  if (echoInstance !== null) {
    echoInstance.disconnect()
    echoInstance = null
  }
}
