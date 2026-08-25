import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/use-auth'
import { DispatcherLoginPage } from '@/pages/DispatcherLoginPage'
import { IncidentQueuePage } from '@/pages/IncidentQueuePage'
import { IncidentDetailPage } from '@/pages/IncidentDetailPage'
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
            <Route path="/" element={<IncidentQueuePage />} />
            <Route path="/incidents/:id" element={<IncidentDetailPage />} />
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
