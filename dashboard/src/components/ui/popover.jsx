import { Popover as PopoverPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Popover({ ...props }) {
  return <PopoverPrimitive.Root data-slot="popover" {...props} />
}

function PopoverTrigger({ ...props }) {
  return <PopoverPrimitive.Trigger data-slot="popover-trigger" {...props} />
}

function PopoverAnchor({ ...props }) {
  return <PopoverPrimitive.Anchor data-slot="popover-anchor" {...props} />
}

function PopoverContent({ className, align = "center", sideOffset = 6, container, ...props }) {
  // Portal into the admin light-theme scope when the page has one, so the
  // popover inherits its tokens rather than the dispatcher console's dark
  // :root (a portal otherwise escapes to <body>). No-op elsewhere.
  const themeScope =
    typeof document !== "undefined" ? document.querySelector(".admin-theme") : null

  return (
    <PopoverPrimitive.Portal container={container ?? themeScope ?? undefined}>
      <PopoverPrimitive.Content
        data-slot="popover-content"
        align={align}
        sideOffset={sideOffset}
        className={cn(
          "z-50 w-72 rounded-lg border border-border bg-popover p-4 text-popover-foreground shadow-md outline-none",
          className
        )}
        {...props}
      />
    </PopoverPrimitive.Portal>
  )
}

export { Popover, PopoverTrigger, PopoverAnchor, PopoverContent }
