import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/use-auth'

/**
 * UX-only gate, same relationship as every other frontend/backend
 * authorization pair in this app (docs/decisions/26): the real
 * enforcement is the 'create-dispatcher' Gate on the backend. Nested
 * under ProtectedRoute in App.jsx, so isAuthenticated/isLoading are
 * already resolved by the time this renders.
 */
export function AdminRoute() {
  const { user } = useAuth()

  if (user.role !== 'admin') {
    return <Navigate to="/" replace />
  }

  return <Outlet />
}
