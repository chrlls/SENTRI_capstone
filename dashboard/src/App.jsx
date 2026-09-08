import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/use-auth'
import { DispatcherLoginPage } from '@/pages/DispatcherLoginPage'
import { DispatcherConsoleLayout } from '@/pages/DispatcherConsoleLayout'
import { IncidentDetailRoute } from '@/pages/IncidentDetailRoute'
import { CreateDispatcherPage } from '@/pages/CreateDispatcherPage'
import { AdminLayout } from '@/pages/AdminLayout'
import { AdminComingSoonPage } from '@/pages/AdminComingSoonPage'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { AdminRoute } from '@/components/AdminRoute'

/**
 * The only lazy-loaded route in this app. AdminOverviewPage pulls in
 * Recharts (d3-scale/d3-shape/d3-array) for its charts — real weight that
 * every dispatcher session would otherwise download too, since nothing
 * else here uses route-level code splitting. Named export adapted to the
 * default export React.lazy() requires, rather than changing this page's
 * export convention to differ from every other page file.
 */
const AdminOverviewPage = lazy(() =>
  import('@/pages/AdminOverviewPage').then((module) => ({ default: module.AdminOverviewPage }))
)

/** An already-authenticated dispatcher visiting /login goes straight to the queue instead of seeing the form again. */
function LoginRoute() {
  const { isAuthenticated, isLoading } = useAuth()

  if (isLoading) {
    return <div className="flex min-h-svh items-center justify-center bg-background" />
  }

  return isAuthenticated ? <Navigate to="/" replace /> : <DispatcherLoginPage />
}

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginRoute />} />
          <Route element={<ProtectedRoute />}>
            {/* Persistent-queue architecture: /incidents/:id is nested under
                / rather than a sibling route, so both URLs share one
                DispatcherConsoleLayout instance (map, queue, corner
                controls) and only its own nested <Outlet/> changes —
                selecting/closing an incident's detail never remounts the
                map or the queue. AdminRoute stays a sibling, not nested
                here, so admin screens don't inherit dispatcher chrome. */}
            <Route path="/" element={<DispatcherConsoleLayout />}>
              <Route index element={null} />
              <Route path="incidents/:id" element={<IncidentDetailRoute />} />
            </Route>
            <Route element={<AdminRoute />}>
              <Route path="/admin/create-dispatcher" element={<CreateDispatcherPage />} />
              {/* Admin Dashboard shell (Phase 1): a separate AdminLayout, not
                  nested under DispatcherConsoleLayout above — only Overview
                  is a real page, the rest are scoped placeholders so the
                  full information architecture is visible without pretending
                  unbuilt backend features exist (see AdminComingSoonPage). */}
              <Route path="/admin" element={<AdminLayout />}>
                <Route
                  index
                  element={
                    <Suspense fallback={<div className="flex h-full items-center justify-center text-sm text-muted-foreground">Loading…</div>}>
                      <AdminOverviewPage />
                    </Suspense>
                  }
                />
                <Route path="monitoring" element={<AdminComingSoonPage />} />
                <Route path="users" element={<AdminComingSoonPage />} />
                <Route path="system" element={<AdminComingSoonPage />} />
                <Route path="audit" element={<AdminComingSoonPage />} />
                <Route path="reports" element={<AdminComingSoonPage />} />
              </Route>
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}

export default App
