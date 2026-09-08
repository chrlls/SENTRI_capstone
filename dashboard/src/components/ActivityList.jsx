import { formatRelativeTime } from '@/lib/utils'
import { adminIconFor } from '@/lib/adminIcons'

/** Reusable admin activity feed — icon, title, description, actor + relative time (Plex Mono, matching the rest of the dashboard's metadata convention). */
export function ActivityList({ items }) {
  return (
    <ul className="flex flex-col divide-y divide-border">
      {items.map((item) => {
        const Icon = adminIconFor(item.icon)
        return (
          <li key={item.key} className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
            <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-[3px] bg-(--sentri-obsidian)/5 text-(--sentri-obsidian)">
              <Icon className="size-3.5" />
            </span>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <p className="text-sm font-medium text-foreground">{item.title}</p>
              <p className="text-sm text-muted-foreground">{item.description}</p>
              <p className="font-mono text-[11px] text-(--sentri-slate-label)">
                {item.actor} · {formatRelativeTime(item.occurredAt)}
              </p>
            </div>
          </li>
        )
      })}
    </ul>
  )
}
