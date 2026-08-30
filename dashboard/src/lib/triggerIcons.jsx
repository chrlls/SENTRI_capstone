import { Activity, Bell, MessageSquareWarning, Mic } from 'lucide-react'

/**
 * Returns an already-instantiated icon element (not a component reference
 * assigned to a local variable and rendered as `<Icon/>`) — the latter
 * pattern trips `react-hooks/static-components`, which can't statically
 * prove a value pulled from a lookup table is referentially stable across
 * renders, even though this one always is. Shared by IncidentQueue's
 * cards and the map's hover-preview card — one icon meaning per
 * trigger_source, not two independently-chosen sets.
 */
export function triggerIconElement(triggerSource, className) {
  switch (triggerSource) {
    case 'manual_sos':
      return <Bell className={className} />
    case 'voice_distress':
      return <Mic className={className} />
    case 'keyword_detected':
      return <MessageSquareWarning className={className} />
    case 'movement_anomaly':
      return <Activity className={className} />
    default:
      return <Bell className={className} />
  }
}

/**
 * premium-finish polish pass: `humanizeEnum(trigger_source)` alone gave
 * "Manual Sos" / "Voice Distress" — parallel in casing but not in
 * vocabulary (one names how it was triggered, the other names what was
 * detected), which reads as slightly inconsistent copy next to each
 * other in the queue. Both are SOS reports; only the trigger differs —
 * "Manual SOS" / "Voice SOS" says exactly that, matches this project's
 * own precise-operational-language standard, and is the literal pair the
 * pass's own copy guidance lists.
 */
export function triggerSourceLabel(triggerSource) {
  switch (triggerSource) {
    case 'manual_sos':
      return 'Manual SOS'
    case 'voice_distress':
      return 'Voice SOS'
    case 'keyword_detected':
      return 'Keyword Detected'
    case 'movement_anomaly':
      return 'Movement Anomaly'
    default:
      return triggerSource
  }
}
