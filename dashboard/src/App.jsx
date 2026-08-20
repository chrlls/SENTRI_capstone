import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/use-auth'
import { DispatcherLoginPage } from '@/pages/DispatcherLoginPage'
import { Button } from '@/components/ui/button'

function DispatcherHomePlaceholder() {
  const { user, logout } = useAuth()

  return (
    <div className="flex min-h-svh flex-col items-center justify-center gap-4 bg-background px-4 text-center">
      <p className="text-sm text-muted-foreground">Signed in as</p>
      <p className="text-lg font-medium text-foreground">
        {user.full_name} <span className="text-muted-foreground">({user.role})</span>
      </p>
      <p className="max-w-xs text-sm text-muted-foreground">
        The incident queue and dispatcher console are not built yet — this is
        a placeholder confirming the session is live.
      </p>
      <Button variant="outline" onClick={logout}>
        Sign out
      </Button>
    </div>
  )
}

function AuthGate() {
  const { isAuthenticated, isLoading } = useAuth()

  if (isLoading) {
    return <div className="flex min-h-svh items-center justify-center bg-background" />
  }

  return isAuthenticated ? <DispatcherHomePlaceholder /> : <DispatcherLoginPage />
}

function App() {
  return (
    <AuthProvider>
      <AuthGate />
    </AuthProvider>
  )
}

export default App
