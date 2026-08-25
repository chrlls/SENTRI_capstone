import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/hooks/use-auth'

export function DispatcherHeader() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  async function handleLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <header className="flex h-12 shrink-0 items-center justify-between border-b border-border px-4">
      <span className="text-sm font-medium text-foreground">SENTRI Dispatch</span>
      <div className="flex items-center gap-3">
        {user.role === 'admin' && (
          <Button variant="ghost" size="sm" asChild>
            <Link to="/admin/create-dispatcher">Create dispatcher</Link>
          </Button>
        )}
        <span className="text-xs text-muted-foreground">
          {user.full_name} <span className="text-muted-foreground/70">({user.role})</span>
        </span>
        <Button variant="outline" size="sm" onClick={handleLogout}>
          Sign out
        </Button>
      </div>
    </header>
  )
}
