import { Outlet } from 'react-router-dom'
import { AdminSidebar } from '@/components/AdminSidebar'
import { AdminHeader } from '@/components/AdminHeader'

/**
 * Admin Dashboard shell — a separate, static sidebar + header layout, not
 * a reuse of DispatcherConsoleLayout's floating map-oriented chrome. Scoped
 * to `/admin/*` only (see App.jsx); `.admin-theme` (index.css) applies the
 * brand's light surface here without touching the dispatcher console's own
 * dark palette.
 */
export function AdminLayout() {
  return (
    <div className="admin-theme flex h-svh w-full bg-background text-foreground">
      <AdminSidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <AdminHeader />
        <main className="flex-1 overflow-y-auto p-4 lg:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
