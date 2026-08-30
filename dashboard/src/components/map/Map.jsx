// MapLibre GL v6's ESM build has no default export — everything is a
// named export. `MapLibreMap` is the library's own alias for `Map`
// (confirmed identical: `Map === MapLibreMap`), provided specifically to
// avoid colliding with this file's own exported `Map` React component
// and with JS's built-in global `Map` type.
import { MapLibreMap, Marker, Popup, setWorkerUrl } from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
// v6 loads its web worker from a separate file at runtime; bundlers
// (Vite included) can't rewrite that URL automatically, so it 404s/
// ERR_FAILEDs under Vite's dev-server dependency pre-bundling without
// this — confirmed as the actual failure via a real network-request
// listener before applying this fix, not assumed from a changelog. The
// `?url` import hands Vite the real resolved asset URL instead of trying
// to import the worker module itself.
import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url'

setWorkerUrl(maplibreWorkerUrl)
import {
  createContext,
  forwardRef,
  useCallback,
  useContext,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

/**
 * Adapted from the mapcn reference component (not an npm package — a
 * copy-paste primitive kit in the shadcn/21st.dev style, vendored and
 * trimmed for SENTRI's needs) for the MapLibre migration.
 *
 * Deliberately removed from the original: `theme`/`styles={{light,dark}}`
 * and the whole `useResolvedTheme`/`getDocumentTheme`/`getSystemTheme`/
 * MutationObserver machinery. That existed to pick a style based on OS/
 * site dark-mode state — irrelevant here, since SENTRI's dispatcher
 * console has no light mode (Decision 23) and the Operations/Satellite
 * choice is a dispatcher-driven content toggle, not a color-scheme
 * preference. Left in place, it would misleadingly suggest this map
 * responds to dark/light mode when it structurally can't. Replaced with
 * a single controlled `style` prop (a style URL string or a
 * StyleSpecification object) that IncidentMap.jsx computes from
 * LayerToggle's `activeLayer` state.
 *
 * Also restructured from the pasted source (which this project's own
 * react-hooks lint config — stricter than whatever the original was
 * written against — rejects outright as hard errors, not warnings):
 * every "read/write a ref during render" pattern (`ref.current = x`
 * inline in the component body, or a closure created inside a
 * render-phase `useMemo` that captures a ref) is moved into a proper
 * `useEffect`. This is a real fix, not a suppressed lint rule — refs are
 * genuinely not meant to be touched during render, and the effect-based
 * version behaves identically for every case this app actually exercises
 * (static marker/tooltip options, callbacks whose *identity* may change
 * across renders but whose *latest value* is all any handler ever needs).
 */

const MapContext = createContext(null)

function useMap() {
  const context = useContext(MapContext)
  if (!context) throw new Error('useMap must be used within a Map component')
  return context
}

function DefaultLoader() {
  return (
    <div className="absolute inset-0 z-10 flex items-center justify-center bg-background/50 backdrop-blur-xs">
      <div className="flex gap-1">
        <span className="size-1.5 animate-pulse rounded-full bg-muted-foreground/60" />
        <span className="size-1.5 animate-pulse rounded-full bg-muted-foreground/60 [animation-delay:150ms]" />
        <span className="size-1.5 animate-pulse rounded-full bg-muted-foreground/60 [animation-delay:300ms]" />
      </div>
    </div>
  )
}

function getViewport(map) {
  const center = map.getCenter()
  return {
    center: [center.lng, center.lat],
    zoom: map.getZoom(),
    bearing: map.getBearing(),
    pitch: map.getPitch(),
  }
}

const Map = forwardRef(function Map(
  { children, className, style, viewport, onViewportChange, loading = false, ...props },
  ref
) {
  const containerRef = useRef(null)
  const [mapInstance, setMapInstance] = useState(null)
  const [isLoaded, setIsLoaded] = useState(false)
  const [isStyleLoaded, setIsStyleLoaded] = useState(false)
  const styleTimeoutRef = useRef(null)
  const internalUpdateRef = useRef(false)
  const onViewportChangeRef = useRef(onViewportChange)

  useEffect(() => {
    onViewportChangeRef.current = onViewportChange
  }, [onViewportChange])

  useImperativeHandle(ref, () => mapInstance, [mapInstance])

  const clearStyleTimeout = useCallback(() => {
    if (styleTimeoutRef.current) {
      clearTimeout(styleTimeoutRef.current)
      styleTimeoutRef.current = null
    }
  }, [])

  // Mount-once: the MapLibre instance itself is created exactly once per
  // component lifetime. Style changes are handled by the separate
  // setStyle effect below, viewport changes by the separate jumpTo effect
  // — neither should tear down and recreate the whole map.
  useEffect(() => {
    if (!containerRef.current) {
      return
    }

    const map = new MapLibreMap({
      container: containerRef.current,
      style,
      renderWorldCopies: false,
      attributionControl: { compact: true },
      ...props,
      ...viewport,
    })

    const styleDataHandler = () => {
      clearStyleTimeout()
      styleTimeoutRef.current = setTimeout(() => setIsStyleLoaded(true), 100)
    }
    const loadHandler = () => setIsLoaded(true)
    const moveHandler = () => {
      if (!internalUpdateRef.current) {
        onViewportChangeRef.current?.(getViewport(map))
      }
    }

    map.on('load', loadHandler)
    map.on('styledata', styleDataHandler)
    map.on('move', moveHandler)
    setMapInstance(map)

    return () => {
      clearStyleTimeout()
      map.off('load', loadHandler)
      map.off('styledata', styleDataHandler)
      map.off('move', moveHandler)
      map.remove()
      setMapInstance(null)
      setIsLoaded(false)
      setIsStyleLoaded(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- deliberately mount-once; style/viewport changes are handled by their own effects below, not by recreating the map.
  }, [])

  useEffect(() => {
    if (!mapInstance || !style) {
      return
    }
    // Synchronously marking the style stale the instant setStyle() is
    // called (rather than waiting for a subsequent event) is the
    // legitimate case react-hooks/set-state-in-effect's own guidance
    // allows for: "update external systems with the latest state from
    // React" — mapInstance.setStyle is the external-system call, and
    // isStyleLoaded=false is that same call's own immediate, synchronous
    // consequence, not a derived/duplicated piece of state.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setIsStyleLoaded(false)
    mapInstance.setStyle(style)
  }, [style, mapInstance])

  useEffect(() => {
    if (!mapInstance || !viewport) {
      return
    }
    internalUpdateRef.current = true
    mapInstance.jumpTo(viewport)
    requestAnimationFrame(() => {
      internalUpdateRef.current = false
    })
  }, [mapInstance, viewport])

  const contextValue = useMemo(
    () => ({ map: mapInstance, isLoaded: isLoaded && isStyleLoaded }),
    [mapInstance, isLoaded, isStyleLoaded]
  )

  return (
    <MapContext.Provider value={contextValue}>
      <div ref={containerRef} className={cn('relative h-full w-full', className)}>
        {(!isLoaded || loading) && <DefaultLoader />}
        {mapInstance && children}
      </div>
    </MapContext.Provider>
  )
})

const MarkerContext = createContext(null)

function useMarkerContext() {
  const context = useContext(MarkerContext)
  if (!context) throw new Error('Marker components must be used within MapMarker')
  return context
}

/**
 * `zIndex` (added for SENTRI — not in the original mapcn source): the
 * MapLibre equivalent of Leaflet's `zIndexOffset`, needed so the
 * selected incident's marker renders above overlapping unselected ones.
 * MapLibre's Marker has no built-in z-index concept — it's a plain DOM
 * element positioned by CSS transform — so this sets the root marker
 * element's own `style.zIndex` directly.
 */
function MapMarker({
  longitude,
  latitude,
  zIndex,
  children,
  onClick,
  onMouseEnter,
  onMouseLeave,
  onDragStart,
  onDrag,
  onDragEnd,
  draggable = false,
  ...markerOptions
}) {
  const { map } = useMap()
  const callbacksRef = useRef({ onClick, onMouseEnter, onMouseLeave, onDragStart, onDrag, onDragEnd })

  useEffect(() => {
    callbacksRef.current = { onClick, onMouseEnter, onMouseLeave, onDragStart, onDrag, onDragEnd }
  })

  // One real Marker instance per mount, matching the original mapcn
  // source; position/draggable/zIndex are kept in sync imperatively via
  // the effects below instead of recreating the marker on every prop
  // change. Event listeners are wired up in a separate effect (not here)
  // so this factory never has to close over callbacksRef.
  const marker = useMemo(() => {
    return new Marker({ ...markerOptions, element: document.createElement('div'), draggable }).setLngLat([
      longitude,
      latitude,
    ])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const element = marker.getElement()
    const handleClick = (event) => callbacksRef.current.onClick?.(event)
    const handleMouseEnter = (event) => callbacksRef.current.onMouseEnter?.(event)
    const handleMouseLeave = (event) => callbacksRef.current.onMouseLeave?.(event)
    const handleDragStart = () => {
      const lngLat = marker.getLngLat()
      callbacksRef.current.onDragStart?.({ lng: lngLat.lng, lat: lngLat.lat })
    }
    const handleDrag = () => {
      const lngLat = marker.getLngLat()
      callbacksRef.current.onDrag?.({ lng: lngLat.lng, lat: lngLat.lat })
    }
    const handleDragEnd = () => {
      const lngLat = marker.getLngLat()
      callbacksRef.current.onDragEnd?.({ lng: lngLat.lng, lat: lngLat.lat })
    }

    element?.addEventListener('click', handleClick)
    element?.addEventListener('mouseenter', handleMouseEnter)
    element?.addEventListener('mouseleave', handleMouseLeave)
    marker.on('dragstart', handleDragStart)
    marker.on('drag', handleDrag)
    marker.on('dragend', handleDragEnd)

    return () => {
      element?.removeEventListener('click', handleClick)
      element?.removeEventListener('mouseenter', handleMouseEnter)
      element?.removeEventListener('mouseleave', handleMouseLeave)
      marker.off('dragstart', handleDragStart)
      marker.off('drag', handleDrag)
      marker.off('dragend', handleDragEnd)
    }
  }, [marker])

  useEffect(() => {
    if (!map) {
      return
    }
    marker.addTo(map)
    return () => marker.remove()
  }, [map, marker])

  useEffect(() => {
    if (marker.getLngLat().lng !== longitude || marker.getLngLat().lat !== latitude) {
      marker.setLngLat([longitude, latitude])
    }
  }, [marker, longitude, latitude])

  useEffect(() => {
    if (marker.isDraggable() !== draggable) {
      marker.setDraggable(draggable)
    }
  }, [marker, draggable])

  useEffect(() => {
    if (zIndex === undefined) {
      return
    }
    const element = marker.getElement()
    if (element && element.style.zIndex !== String(zIndex)) {
      element.style.zIndex = zIndex
    }
  }, [marker, zIndex])

  return <MarkerContext.Provider value={{ marker, map }}>{children}</MarkerContext.Provider>
}

function MarkerContent({ children, className }) {
  const { marker } = useMarkerContext()
  return createPortal(
    <div className={cn('relative cursor-pointer', className)}>{children || <DefaultMarkerIcon />}</div>,
    marker.getElement()
  )
}

function DefaultMarkerIcon() {
  return <div className="relative h-4 w-4 rounded-full border-2 border-white bg-blue-500 shadow-lg" />
}

function MarkerTooltip({ children, className, ...popupOptions }) {
  const { marker, map } = useMarkerContext()
  const container = useMemo(() => document.createElement('div'), [])
  const tooltip = useMemo(() => {
    return new Popup({ offset: 16, ...popupOptions, closeOnClick: true, closeButton: false }).setMaxWidth(
      'none'
    )
    // eslint-disable-next-line react-hooks/exhaustive-deps -- one Popup instance per mount, matching the original mapcn source; offset/maxWidth are kept in sync imperatively by the effects below.
  }, [])

  useEffect(() => {
    if (!map) {
      return
    }
    tooltip.setDOMContent(container)
    const handleMouseEnter = () => tooltip.setLngLat(marker.getLngLat()).addTo(map)
    const handleMouseLeave = () => tooltip.remove()
    const element = marker.getElement()
    element?.addEventListener('mouseenter', handleMouseEnter)
    element?.addEventListener('mouseleave', handleMouseLeave)
    return () => {
      element?.removeEventListener('mouseenter', handleMouseEnter)
      element?.removeEventListener('mouseleave', handleMouseLeave)
      tooltip.remove()
    }
  }, [container, map, marker, tooltip])

  // Re-applies offset/maxWidth to an already-open popup if either prop
  // changes live — an edge case SENTRI's own usage never actually
  // exercises (both are passed as static defaults), kept for parity with
  // the original source's intent. The dependency array itself is what
  // used to be a manual `prevOptions.current !== options` ref comparison
  // — expressing "only run when this value changes" via useEffect's own
  // dependency diffing instead of a hand-rolled one.
  useEffect(() => {
    if (!tooltip.isOpen()) {
      return
    }
    tooltip.setOffset(popupOptions.offset ?? 16)
  }, [tooltip, popupOptions.offset])

  useEffect(() => {
    if (!tooltip.isOpen() || !popupOptions.maxWidth) {
      return
    }
    tooltip.setMaxWidth(popupOptions.maxWidth)
  }, [tooltip, popupOptions.maxWidth])

  return createPortal(
    <div
      className={cn(
        'pointer-events-none rounded-md bg-foreground px-2 py-1 text-xs text-balance text-background shadow-md animate-in fade-in-0 zoom-in-95 duration-200 ease-out',
        className
      )}
    >
      {children}
    </div>,
    container
  )
}

function MarkerLabel({ children, className, position = 'top' }) {
  const positionClasses = { top: 'bottom-full mb-1', bottom: 'top-full mt-1' }
  return (
    <div
      className={cn(
        'absolute left-1/2 -translate-x-1/2 whitespace-nowrap text-[10px] font-medium text-foreground',
        positionClasses[position],
        className
      )}
    >
      {children}
    </div>
  )
}

// Same tradeoff this codebase's own shadcn-generated ui/badge.jsx and
// ui/button.jsx already accept: exporting a hook alongside components
// costs Fast Refresh a hot-swap (falls back to a full reload on edit) —
// a DX inconvenience, not a functional bug — and splitting `useMap` into
// its own file for this one export isn't worth the added indirection.
// eslint-disable-next-line react-refresh/only-export-components
export { Map, useMap, MapMarker, MarkerContent, MarkerTooltip, MarkerLabel }
