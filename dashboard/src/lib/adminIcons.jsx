import {
  Activity,
  BadgeCheck,
  Cpu,
  Database,
  LogIn,
  RadioTower,
  Server,
  Settings,
  ShieldAlert,
  ShieldCheck,
  UserPlus,
  Users,
} from 'lucide-react'

const ADMIN_ICON_MAP = {
  'user-plus': UserPlus,
  'badge-check': BadgeCheck,
  settings: Settings,
  'log-in': LogIn,
  server: Server,
  database: Database,
  cpu: Cpu,
  'radio-tower': RadioTower,
  'shield-alert': ShieldAlert,
  'shield-check': ShieldCheck,
  users: Users,
  activity: Activity,
}

/** Looks up an icon component by the mock data's string key (see adminMockData.js) — same pattern as lib/triggerIcons.jsx. */
export function adminIconFor(key) {
  return ADMIN_ICON_MAP[key] ?? Settings
}
