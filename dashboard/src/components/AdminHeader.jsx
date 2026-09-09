import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Bell, Menu, Moon, Search } from 'lucide-react'
import { useAuth } from '@/hooks/use-auth'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { ADMIN_NAV_ITEMS } from '@/lib/adminNav'

function initialsFor(fullName) {
  const parts = fullName.trim().split(/\s+/)
  const first = parts[0]?.[0] ?? ''
  const last = parts.length > 1 ? parts[parts.length - 1][0] : ''
  return (first + last).toUpperCase()
}

/**
 * Persistent top bar — search + theme/notifications/profile (presentational
 * only for now, same "ships the shell, wires the behavior later" approach
 * as the Overview page's mock data). The page title itself is NOT here —
 * it lives in each page's own content (AdminPageHeader), sitting between
 * this bar and that page's content grid, not squeezed inside fixed chrome.
 */
export function AdminHeader() {
  const { user } = useAuth()
  const [searchValue, setSearchValue] = useState('')

  return (
    <div className="flex h-16 shrink-0 items-center gap-3 border-b border-border bg-[#FFFEFF] px-4 lg:px-8">
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="icon" className="shrink-0 rounded-full md:hidden" aria-label="Open admin navigation">
            <Menu />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="w-64">
          {ADMIN_NAV_ITEMS.map((item) => (
            <DropdownMenuItem key={item.path} asChild>
              <Link to={item.path} className="flex items-center gap-2">
                <item.icon className="size-4" />
                {item.label}
              </Link>
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>

      <div className="relative max-w-md flex-1">
        <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          type="search"
          value={searchValue}
          onChange={(event) => setSearchValue(event.target.value)}
          placeholder="Search anything..."
          aria-label="Search"
          className="h-10 rounded-full pl-9"
        />
      </div>

      <div className="ml-auto flex shrink-0 items-center gap-1.5">
        <Button variant="ghost" size="icon" className="rounded-full" aria-label="Toggle color theme" title="Color theme (coming soon)">
          <Moon />
        </Button>
        <Button variant="ghost" size="icon" className="rounded-full" aria-label="Notifications" title="Notifications (coming soon)">
          <Bell />
        </Button>
        <Avatar title={user.full_name}>
          <AvatarFallback className="bg-(--sentri-obsidian) font-mono text-[10px] text-(--sentri-obsidian-tint)">
            {initialsFor(user.full_name)}
          </AvatarFallback>
        </Avatar>
      </div>
    </div>
  )
}
