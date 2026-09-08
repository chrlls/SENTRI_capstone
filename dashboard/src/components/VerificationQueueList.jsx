import { Link } from 'react-router-dom'
import { ExternalLink } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * Read-only preview, pairs with the Pending Responder Verification KPI
 * (which states the number; this is where an admin would go to actually
 * clear it) — no functioning approve/reject buttons here. That's real
 * User Management functionality needing a backend endpoint that doesn't
 * exist yet (Decision 19), and it's already the sidebar's own coming-soon
 * page's stated purpose; a second, half-working path to the same action
 * would be worse than a plain link. A wait past 14 days gets a visibly
 * different (amber, not crimson — this is a delay, not an emergency)
 * treatment, since a 47-day outlier sitting next to 2-9 day waits reads
 * as a real problem worth noticing, not just another row.
 */
export function VerificationQueueList({ items }) {
  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-col divide-y divide-border">
        {items.map((item) => (
          <li key={item.key} className="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
            <div className="flex flex-col gap-0.5">
              <span className="text-sm font-medium text-foreground">{item.name}</span>
              <span className="text-xs text-muted-foreground">{item.barangay}</span>
            </div>
            <span
              className={cn(
                'font-mono text-xs tabular-nums',
                item.daysWaiting > 14 ? 'font-semibold text-amber-700' : 'text-muted-foreground'
              )}
            >
              {item.daysWaiting}d waiting
            </span>
          </li>
        ))}
      </ul>
      <Link
        to="/admin/users"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-(--sentri-obsidian) hover:underline"
      >
        View all in User Management
        <ExternalLink className="size-3.5" />
      </Link>
    </div>
  )
}
