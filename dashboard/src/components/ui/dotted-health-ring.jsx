import { useEffect, useMemo, useState } from 'react'

import { cn } from '@/lib/utils'

/**
 * Two concentric dotted rings for the SENTRI Admin "System Health"
 * visualisation. The rings are built from individually positioned
 * circular dots (trig around a centre) — not an SVG stroke-dasharray /
 * progress circle.
 *
 *   • OUTER ring  #1362FE  — overall SENTRI system health (`systemHealth`)
 *   • INNER ring  #5991FE  — supporting-service health   (`serviceHealth`)
 *
 * Both stay in the SENTRI Admin blue palette; there is deliberately no
 * green "healthy" colour and no gradient between the two rings. Unfilled
 * dots use a low-opacity neutral. On mount the outer dots reveal in
 * sequence, then the inner dots, then the score, then the status line —
 * restrained, one pass, no continuous rotation. `prefers-reduced-motion`
 * drops the stagger and shows everything at once.
 */

const OUTER_COLOR = '#1362FE'
const INNER_COLOR = '#5991FE'

/** Ring radii as a percentage of the (square) container. */
const OUTER_RADIUS = 47
const INNER_RADIUS = 34

/** Per-dot reveal step and the gaps between phases, in ms. */
const DOT_STEP_MS = 12
const PHASE_GAP_MS = 140

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  )

  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)')
    const onChange = (event) => setReduced(event.matches)
    query.addEventListener('change', onChange)
    return () => query.removeEventListener('change', onChange)
  }, [])

  return reduced
}

/** Evenly spaced positions around a circle, starting at 12 o'clock and going clockwise. */
function ringPositions(count, radius) {
  return Array.from({ length: count }, (_, index) => {
    const angle = (index / count) * 2 * Math.PI - Math.PI / 2
    return {
      left: `${50 + radius * Math.cos(angle)}%`,
      top: `${50 + radius * Math.sin(angle)}%`,
    }
  })
}

function Ring({ count, radius, percent, color, dotClassName, startDelay, mounted, reduced }) {
  const positions = useMemo(() => ringPositions(count, radius), [count, radius])
  const activeCount = Math.round((Math.min(Math.max(percent, 0), 100) / 100) * count)

  return positions.map((position, index) => {
    const active = index < activeCount
    return (
      <span
        key={index}
        aria-hidden="true"
        className={cn(
          '-translate-x-1/2 -translate-y-1/2 absolute rounded-full transition-all duration-300 ease-out',
          mounted ? 'scale-100 opacity-100' : 'scale-50 opacity-0',
          !active && 'bg-foreground/10',
          dotClassName,
        )}
        style={{
          left: position.left,
          top: position.top,
          transitionDelay: reduced ? '0ms' : `${startDelay + index * DOT_STEP_MS}ms`,
          ...(active ? { backgroundColor: color } : null),
        }}
      />
    )
  })
}

export function DottedHealthRing({
  score = 96,
  label = 'HEALTH',
  status = 'All systems operational',
  systemHealth = 96,
  serviceHealth = 92,
  outerDotCount = 48,
  innerDotCount = 36,
  className,
}) {
  const reduced = usePrefersReducedMotion()
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true))
    return () => cancelAnimationFrame(id)
  }, [])

  const innerStart = outerDotCount * DOT_STEP_MS + PHASE_GAP_MS
  const scoreDelay = reduced ? 0 : innerStart + innerDotCount * DOT_STEP_MS + PHASE_GAP_MS
  const statusDelay = reduced ? 0 : scoreDelay + PHASE_GAP_MS + 120

  return (
    <div className={cn('flex flex-col items-center gap-4', className)}>
      <div
        role="img"
        aria-label={`System health score ${score} out of 100. ${status}.`}
        className="relative aspect-square w-full max-w-[300px]"
      >
        <Ring
          count={outerDotCount}
          radius={OUTER_RADIUS}
          percent={systemHealth}
          color={OUTER_COLOR}
          dotClassName="size-[7px]"
          startDelay={0}
          mounted={mounted}
          reduced={reduced}
        />
        <Ring
          count={innerDotCount}
          radius={INNER_RADIUS}
          percent={serviceHealth}
          color={INNER_COLOR}
          dotClassName="size-[5px]"
          startDelay={innerStart}
          mounted={mounted}
          reduced={reduced}
        />

        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span
            className={cn(
              'font-heading font-semibold text-4xl text-foreground tabular-nums transition-opacity duration-300',
              mounted ? 'opacity-100' : 'opacity-0',
            )}
            style={{ transitionDelay: `${scoreDelay}ms` }}
          >
            {score}
          </span>
          <span
            className={cn(
              'mt-1 font-medium text-[10px] text-muted-foreground uppercase tracking-[0.18em] transition-opacity duration-300',
              mounted ? 'opacity-100' : 'opacity-0',
            )}
            style={{ transitionDelay: `${scoreDelay}ms` }}
          >
            {label}
          </span>
        </div>
      </div>

      <div
        className={cn('flex items-center gap-2 transition-opacity duration-300', mounted ? 'opacity-100' : 'opacity-0')}
        style={{ transitionDelay: `${statusDelay}ms` }}
      >
        <span aria-hidden="true" className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: OUTER_COLOR }} />
        <span className="text-muted-foreground text-sm">{status}</span>
      </div>
    </div>
  )
}
