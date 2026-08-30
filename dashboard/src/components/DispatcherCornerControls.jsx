import { Link, useNavigate } from 'react-router-dom'
import { LogOut, UserPlus } from 'lucide-react'
import { useAuth } from '@/hooks/use-auth'
import { useConnectionStatus } from '@/hooks/useConnectionStatus'
import { Badge } from '@/components/ui/badge'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { cn, humanizeEnum } from '@/lib/utils'

const CONNECTION_META = {
  connected: { label: 'Live — connected', dotClassName: 'bg-emerald-500' },
  connecting: { label: 'Connecting…', dotClassName: 'bg-amber-500' },
  unavailable: { label: 'Connection unavailable', dotClassName: 'bg-destructive' },
  failed: { label: 'Connection failed', dotClassName: 'bg-destructive' },
  disconnected: { label: 'Disconnected', dotClassName: 'bg-muted-foreground' },
}

function initialsFor(fullName) {
  const parts = fullName.trim().split(/\s+/)
  const first = parts[0]?.[0] ?? ''
  const last = parts.length > 1 ? parts[parts.length - 1][0] : ''
  return (first + last).toUpperCase()
}

/**
 * Floating top-right replacement for the old DispatcherHeader top bar
 * (dispatcher-console redesign, Phase 3). Rendered once by
 * DispatcherConsoleLayout (persistent-queue architecture) — the map,
 * corner controls, and left queue all live there for the whole
 * authenticated session; only the contextual right-side detail panel
 * (IncidentDetailRoute, mounted via a nested route/Outlet) comes and goes.
 * DispatcherHeader.jsx itself is untouched: it still backs the admin-only
 * CreateDispatcherPage, which this redesign deliberately doesn't restyle
 * as a side effect (CLAUDE.md: don't carry dispatcher patterns onto admin
 * screens, don't redesign screens the task didn't ask about).
 */
export function DispatcherCornerControls() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const connectionState = useConnectionStatus()
  const connectionMeta = CONNECTION_META[connectionState] ?? {
    label: `Connection: ${connectionState}`,
    dotClassName: 'bg-muted-foreground',
  }

  async function handleLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className="absolute top-3.5 right-3.5 z-20 flex items-center gap-2.5">
      <span className="relative flex size-2" title={connectionMeta.label} aria-label={connectionMeta.label}>
        {connectionState === 'connected' && (
          <span
            className={cn(
              'absolute inset-0 -m-1 rounded-full opacity-50 motion-safe:animate-ping',
              connectionMeta.dotClassName
            )}
          />
        )}
        <span className={cn('relative size-2 rounded-full', connectionMeta.dotClassName)} />
      </span>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="Dispatcher menu"
            className="rounded-full shadow-elevation-2 outline-none transition-[filter,transform] hover:brightness-110 focus-visible:ring-2 focus-visible:ring-ring active:scale-95"
          >
            <Avatar>
              <AvatarFallback className="bg-popover text-foreground">
                {initialsFor(user.full_name)}
              </AvatarFallback>
            </Avatar>
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel className="flex flex-col items-start gap-1.5 px-1.5 py-1.5">
            <span className="text-sm font-medium text-foreground">{user.full_name}</span>
            <Badge variant="outline">{humanizeEnum(user.role)}</Badge>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          {user.role === 'admin' && (
            <DropdownMenuItem asChild>
              <Link to="/admin/create-dispatcher">
                <UserPlus /> Create dispatcher
              </Link>
            </DropdownMenuItem>
          )}
          <DropdownMenuItem variant="destructive" onClick={handleLogout}>
            <LogOut /> Sign out
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}
