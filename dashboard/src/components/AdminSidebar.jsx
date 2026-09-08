import { NavLink, useNavigate } from 'react-router-dom'
import { ArrowLeft, LogOut } from 'lucide-react'
import { useAuth } from '@/hooks/use-auth'
import { Badge } from '@/components/ui/badge'
import { cn, humanizeEnum } from '@/lib/utils'
import { ADMIN_NAV_GROUPS } from '@/lib/adminNav'
import sentriMark from '@/assets/sentri-interlock-reversed.svg'

function initialsFor(fullName) {
  const parts = fullName.trim().split(/\s+/)
  const first = parts[0]?.[0] ?? ''
  const last = parts.length > 1 ? parts[parts.length - 1][0] : ''
  return (first + last).toUpperCase()
}

/**
 * Dedicated Admin sidebar — a real, static navigation rail, not the
 * dispatcher console's floating map-oriented chrome (that layout is
 * DispatcherConsoleLayout/DispatcherCornerControls and is intentionally
 * not reused here; the admin interface is deliberate/administrative, not
 * a real-time operational console). Blue Obsidian rail against the
 * lighter content area next to it (`--sidebar-*` tokens, index.css) —
 * the brand's own dark-ground pairing (Visual Identity Guidelines §05),
 * using the reversed-white mark since the full-colour mark's obsidian
 * core would disappear against a matching obsidian background. Collapses
 * to an icon-only rail at `md`, full labeled sidebar at `lg`, hidden
 * entirely below `md` (AdminHeader's own dropdown covers navigation at
 * that width) — pure Tailwind breakpoint classes, no JS.
 */
export function AdminSidebar() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  async function handleLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <aside className="hidden h-svh w-16 shrink-0 flex-col bg-sidebar text-sidebar-foreground md:flex lg:w-72">
      <div className="flex h-16 shrink-0 items-center gap-3 border-b border-sidebar-border px-3 lg:px-5">
        <img src={sentriMark} alt="SENTRI" className="size-8 shrink-0" />
        <span className="hidden font-heading text-xl font-bold tracking-[0.2em] text-sidebar-foreground uppercase lg:inline">
          Sentri
        </span>
      </div>

      <nav className="flex flex-1 flex-col gap-6 overflow-y-auto px-2 py-5 lg:px-3" aria-label="Admin navigation">
        {ADMIN_NAV_GROUPS.map((group) => (
          <div key={group.label} className="flex flex-col gap-1">
            <span className="hidden px-2.5 font-mono text-[10px] font-medium tracking-[0.14em] text-sidebar-foreground/45 uppercase lg:block">
              {group.label}
            </span>
            {group.items.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                end={item.end}
                title={item.label}
                className={({ isActive }) =>
                  cn(
                    'group flex items-center gap-3 rounded-[3px] border-l-2 border-transparent px-2.5 py-2.5 text-sm font-medium text-sidebar-foreground/65 transition-colors',
                    'hover:bg-sidebar-accent hover:text-sidebar-foreground',
                    isActive && 'border-sidebar-primary bg-sidebar-accent text-sidebar-foreground'
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    <item.icon
                      className={cn('size-[18px] shrink-0', isActive ? 'text-sidebar-primary' : 'text-sidebar-foreground/50')}
                    />
                    <span className="hidden truncate lg:inline">{item.label}</span>
                    {item.comingSoon && (
                      <Badge
                        variant="outline"
                        className="ml-auto hidden shrink-0 rounded-full border-sidebar-border text-[10px] text-sidebar-foreground/60 lg:inline-flex"
                      >
                        Soon
                      </Badge>
                    )}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        ))}
      </nav>

      <div className="flex flex-col gap-2 border-t border-sidebar-border p-2 lg:p-3">
        <NavLink
          to="/"
          title="Back to dispatch console"
          className="flex items-center gap-3 rounded-[3px] px-2.5 py-2.5 text-sm font-medium text-sidebar-foreground/65 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground"
        >
          <ArrowLeft className="size-[18px] shrink-0 text-sidebar-foreground/50" />
          <span className="hidden truncate lg:inline">Dispatch console</span>
        </NavLink>

        <div className="flex items-center gap-3 px-2.5 py-1.5">
          <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-sidebar-accent font-mono text-[11px] font-medium text-sidebar-foreground">
            {initialsFor(user.full_name)}
          </span>
          <div className="hidden min-w-0 flex-1 flex-col lg:flex">
            <span className="truncate text-sm font-medium text-sidebar-foreground">{user.full_name}</span>
            <span className="font-mono text-[10px] text-sidebar-foreground/50 uppercase">{humanizeEnum(user.role)}</span>
          </div>
          <button
            type="button"
            onClick={handleLogout}
            aria-label="Sign out"
            title="Sign out"
            className="inline-flex shrink-0 rounded-[3px] p-1.5 text-sidebar-foreground/50 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground"
          >
            <LogOut className="size-4" />
          </button>
        </div>

        <span className="hidden px-2.5 font-mono text-[10px] text-sidebar-foreground/35 lg:block">
          SENTRI Admin · v0.1
        </span>
      </div>
    </aside>
  )
}
