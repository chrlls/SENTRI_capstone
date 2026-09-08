import { matchPath } from 'react-router-dom'
import { Activity, FileBarChart2, LayoutDashboard, Settings, ShieldCheck, Users } from 'lucide-react'

/**
 * Single source of truth for the Admin Dashboard's information architecture
 * — read by both AdminSidebar (navigation) and AdminHeader (current page
 * title/description, matched against the route). Grouping and scope follow
 * the audited project requirements (TASK_CHECKLIST.md Objective 2,
 * decisions/19, decisions/24's still-open items): only Overview has a real
 * page this phase, everything else is a scoped placeholder so the intended
 * IA is visible without pretending unbuilt backend features exist.
 */
export const ADMIN_NAV_GROUPS = [
  {
    label: 'Admin',
    items: [
      {
        path: '/admin',
        end: true,
        label: 'Dashboard',
        description: 'System-wide status across accounts, responders, and platform health.',
        icon: LayoutDashboard,
      },
    ],
  },
  {
    label: 'Operations',
    items: [
      {
        path: '/admin/monitoring',
        label: 'Monitoring',
        description: 'Platform-wide operational monitoring — distinct from the live dispatcher console.',
        icon: Activity,
        comingSoon: true,
      },
    ],
  },
  {
    label: 'Management',
    items: [
      {
        path: '/admin/users',
        label: 'User Management',
        description: 'Manage PNP/dispatcher, responder, and admin accounts, including responder verification.',
        icon: Users,
        comingSoon: true,
      },
    ],
  },
  {
    label: 'System',
    items: [
      {
        path: '/admin/system',
        label: 'System Management',
        description: 'Platform configuration and system-level settings.',
        icon: Settings,
        comingSoon: true,
      },
    ],
  },
  {
    label: 'Security',
    items: [
      {
        path: '/admin/audit',
        label: 'Audit',
        description: 'Administrative activity and audit trail.',
        icon: ShieldCheck,
        comingSoon: true,
      },
    ],
  },
  {
    label: 'Reporting',
    items: [
      {
        path: '/admin/reports',
        label: 'Reports',
        description: 'Incident reports and statistical summaries.',
        icon: FileBarChart2,
        comingSoon: true,
      },
    ],
  },
]

export const ADMIN_NAV_ITEMS = ADMIN_NAV_GROUPS.flatMap((group) => group.items)

/** Shared by AdminHeader (title/description) and AdminComingSoonPage (placeholder copy) so both read the same route-to-item mapping instead of each re-deriving it. */
export function findActiveAdminNavItem(pathname) {
  return (
    ADMIN_NAV_ITEMS.find((item) => matchPath({ path: item.path, end: item.end ?? false }, pathname)) ??
    ADMIN_NAV_ITEMS[0]
  )
}
