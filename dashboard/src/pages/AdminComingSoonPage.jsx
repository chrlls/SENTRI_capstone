import { useLocation } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { findActiveAdminNavItem } from '@/lib/adminNav'

/**
 * Shared placeholder for every Admin nav item that isn't built yet
 * (Monitoring, User Management, System Management, Audit, Reports) — the
 * sidebar/header IA is real per the audit's requirements table, the pages
 * behind it deliberately aren't (no backend contract exists for any of
 * them yet). Copy comes from the same adminNav config the sidebar/header
 * already render, so this never drifts from what those describe.
 */
export function AdminComingSoonPage() {
  const location = useLocation()
  const item = findActiveAdminNavItem(location.pathname)
  const Icon = item.icon

  return (
    <Card className="rounded-[14px] shadow-none">
      <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
        <span className="flex size-12 items-center justify-center rounded-[14px] bg-(--sentri-obsidian)/5 text-(--sentri-obsidian)">
          <Icon className="size-6" />
        </span>
        <div className="flex flex-col gap-1.5">
          <h2 className="font-heading text-base font-semibold text-foreground">{item.label} — coming in a later phase</h2>
          <p className="max-w-md text-sm text-muted-foreground">{item.description}</p>
        </div>
      </CardContent>
    </Card>
  )
}
