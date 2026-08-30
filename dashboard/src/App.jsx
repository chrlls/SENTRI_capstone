import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/use-auth'
import { DispatcherLoginPage } from '@/pages/DispatcherLoginPage'
import { DispatcherConsoleLayout } from '@/pages/DispatcherConsoleLayout'
import { IncidentDetailRoute } from '@/pages/IncidentDetailRoute'
import { CreateDispatcherPage } from '@/pages/CreateDispatcherPage'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { AdminRoute } from '@/components/AdminRoute'

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
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}

export default App
