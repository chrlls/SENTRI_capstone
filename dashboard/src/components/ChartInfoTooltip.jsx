import { useState } from 'react'
import { Info } from 'lucide-react'

import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

/**
 * Progressive-disclosure hint that sits beside a chart title. The one
 * explanatory sentence a chart needs lives here on hover/focus instead of
 * a permanent subtitle taking up vertical space under every card. Built
 * as its own component so the other dashboard charts can adopt the same
 * pattern. The trigger is a real focusable button with an accessible
 * name — not a decorative-only icon.
 *
 * The popover content is portalled into the `.admin-theme` element (read
 * once at mount — it is always already in the tree above this component)
 * rather than the document body, so it inherits this dashboard's light
 * token palette instead of the dispatcher console's dark root theme.
 */
export function ChartInfoTooltip({ label, description }) {
  const [themeRoot] = useState(() => document.querySelector('.admin-theme'))

  return (
    <Tooltip>
      <TooltipTrigger
        type="button"
        aria-label={label}
        className="inline-flex size-5 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:text-foreground focus-visible:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-card"
      >
        <Info className="size-3.5" aria-hidden="true" />
      </TooltipTrigger>
      <TooltipContent container={themeRoot}>{description}</TooltipContent>
    </Tooltip>
  )
}
