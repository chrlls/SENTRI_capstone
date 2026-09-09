import { useMemo, useState } from 'react'
import { ChevronDown, ChevronsUpDown, GripVertical, Search } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { cn, formatRelativeTime } from '@/lib/utils'

/**
 * Every column the table can show, in fixed left-to-right order. All of
 * them toggle from the Columns menu; DEFAULT_VISIBLE_COLUMNS are the ones
 * checked on first render. The row set is the same for every row, so a
 * field a given row doesn't carry shows as "—" rather than the table
 * restructuring per activity type.
 */
const ALL_COLUMNS = [
  { key: 'type', label: 'Type' },
  { key: 'activity', label: 'Activity' },
  { key: 'reference', label: 'Reference' },
  { key: 'by', label: 'By' },
  { key: 'time', label: 'Time' },
  { key: 'location', label: 'Location' },
  { key: 'status', label: 'Status' },
  { key: 'priority', label: 'Priority' },
  { key: 'triggerSource', label: 'Trigger Source' },
  { key: 'aiConfidence', label: 'AI Confidence' },
  { key: 'responder', label: 'Responder' },
  { key: 'verificationStatus', label: 'Verification Status' },
  { key: 'incidentId', label: 'Incident ID' },
  { key: 'user', label: 'User' },
  { key: 'role', label: 'Role' },
  { key: 'module', label: 'Module' },
]

const DEFAULT_VISIBLE_COLUMNS = ['type', 'activity', 'reference', 'by', 'time']
const COLUMN_BY_KEY = Object.fromEntries(ALL_COLUMNS.map((col) => [col.key, col]))

const MONO_COLUMNS = new Set(['reference', 'incidentId', 'time', 'aiConfidence'])
const SORTABLE_HEADERS = new Set(['type', 'time', 'priority'])

const FILTER_GROUPS = [
  { key: 'type', label: 'Activity type', options: ['All', 'Incident', 'Status', 'Verification', 'User', 'System'] },
  { key: 'by', label: 'Performed by', options: ['All', 'Admin', 'Dispatcher'] },
  { key: 'status', label: 'Status', options: ['All', 'Pending', 'Verified', 'Dispatched', 'Resolved', 'Rejected'] },
  { key: 'priority', label: 'Priority', options: ['All', 'Critical', 'High', 'Medium', 'Low'] },
  {
    key: 'location',
    label: 'Barangay',
    options: ['All', 'Apokon', 'Visayan Village', 'Magugpo', 'Mankilam', 'Canocotan', 'San Agustin'],
  },
]

const SORT_OPTIONS = [
  { key: 'newest', label: 'Newest first' },
  { key: 'oldest', label: 'Oldest first' },
  { key: 'type', label: 'Activity type' },
  { key: 'priority', label: 'Priority' },
]

const PRIORITY_RANK = { Critical: 0, High: 1, Medium: 2, Low: 3 }
const SEARCH_FIELDS = [
  'type', 'activity', 'reference', 'incidentId', 'responder', 'user', 'location', 'by', 'role', 'module', 'status',
  'priority', 'triggerSource', 'verificationStatus',
]
const DASH = '—'

const EMPTY_FILTERS = { type: 'All', by: 'All', status: 'All', priority: 'All', location: 'All' }

/** "2m ago" -> "2m" — the table only needs the magnitude; precise timestamps live in Audit Logs. */
function shortTime(iso) {
  return formatRelativeTime(iso).replace(/\s*ago$/, '')
}

function cellValue(row, key) {
  if (key === 'time') return shortTime(row.occurredAt)
  if (key === 'aiConfidence') return row.aiConfidence == null ? null : `${Math.round(row.aiConfidence * 100)}%`
  return row[key] ?? null
}

/**
 * The dashboard's single administrative-activity surface: responder
 * verifications, incident actions, status transitions, account and system
 * changes in one enterprise-style table — searchable, with optional
 * columns, filtering and sorting, all in local React state (no API).
 * Detail (full IDs, IPs, exact times) is deliberately left to Audit Logs.
 */
export function RecentActivity({ activity }) {
  const [search, setSearch] = useState('')
  const [filters, setFilters] = useState(EMPTY_FILTERS)
  const [sort, setSort] = useState('newest')
  const [visibleColumns, setVisibleColumns] = useState(() => new Set(DEFAULT_VISIBLE_COLUMNS))
  const [columnOrder, setColumnOrder] = useState(() => ALL_COLUMNS.map((col) => col.key))
  const [dragKey, setDragKey] = useState(null)
  const [dragOverKey, setDragOverKey] = useState(null)

  const columns = useMemo(
    () => columnOrder.filter((key) => visibleColumns.has(key)).map((key) => COLUMN_BY_KEY[key]),
    [columnOrder, visibleColumns],
  )

  const activeFilterCount = Object.values(filters).filter((value) => value !== 'All').length

  const rows = useMemo(() => {
    const query = search.trim().toLowerCase()

    let result = activity.filter((row) => {
      if (query) {
        const hit = SEARCH_FIELDS.some((field) => String(row[field] ?? '').toLowerCase().includes(query))
        if (!hit) return false
      }
      return (
        (filters.type === 'All' || row.type === filters.type) &&
        (filters.by === 'All' || row.by === filters.by) &&
        (filters.status === 'All' || row.status === filters.status) &&
        (filters.priority === 'All' || row.priority === filters.priority) &&
        (filters.location === 'All' || row.location === filters.location)
      )
    })

    const byNewest = (a, b) => new Date(b.occurredAt) - new Date(a.occurredAt)
    result = [...result]
    if (sort === 'oldest') result.sort((a, b) => new Date(a.occurredAt) - new Date(b.occurredAt))
    else if (sort === 'type') result.sort((a, b) => a.type.localeCompare(b.type) || byNewest(a, b))
    else if (sort === 'priority') {
      result.sort((a, b) => (PRIORITY_RANK[a.priority] ?? 99) - (PRIORITY_RANK[b.priority] ?? 99) || byNewest(a, b))
    } else result.sort(byNewest)

    return result
  }, [activity, search, filters, sort])

  const toggleColumn = (key) => {
    setVisibleColumns((current) => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const setFilter = (key, value) => setFilters((current) => ({ ...current, [key]: value }))

  const sortByHeader = (key) => {
    if (key === 'time') setSort((current) => (current === 'newest' ? 'oldest' : 'newest'))
    else setSort((current) => (current === key ? 'newest' : key))
  }

  /** Drop `fromKey` next to `toKey` in the full column order (keeps hidden columns in place too). */
  const moveColumn = (fromKey, toKey) => {
    if (!fromKey || !toKey || fromKey === toKey) return
    setColumnOrder((order) => {
      const from = order.indexOf(fromKey)
      const to = order.indexOf(toKey)
      if (from === -1 || to === -1) return order
      const next = [...order]
      next.splice(from, 1)
      next.splice(to, 0, fromKey)
      return next
    })
  }

  /** Keyboard reorder — Arrow Left/Right on a focused header shifts its column past the adjacent visible one. */
  const nudgeColumn = (key, direction) => {
    const visible = columns.map((col) => col.key)
    const target = visible[visible.indexOf(key) + direction]
    if (target) moveColumn(key, target)
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-end gap-2">
        <div className="relative w-full sm:w-60">
          <Search
            className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground"
            aria-hidden="true"
          />
          <Input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search activity..."
            aria-label="Search activity"
            className="h-9 rounded-lg pl-8 text-sm"
          />
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" className="rounded-lg">
                Columns
                <ChevronDown className="size-3.5" aria-hidden="true" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-52">
              <DropdownMenuLabel>Show columns</DropdownMenuLabel>
              <DropdownMenuSeparator />
              {ALL_COLUMNS.map((col) => (
                <DropdownMenuCheckboxItem
                  key={col.key}
                  checked={visibleColumns.has(col.key)}
                  onCheckedChange={() => toggleColumn(col.key)}
                  onSelect={(event) => event.preventDefault()}
                >
                  {col.label}
                </DropdownMenuCheckboxItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" className="rounded-lg">
                Filter
                {activeFilterCount > 0 && <span className="text-muted-foreground tabular-nums">({activeFilterCount})</span>}
                <ChevronDown className="size-3.5" aria-hidden="true" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-52">
              {FILTER_GROUPS.map((group, index) => (
                <div key={group.key}>
                  {index > 0 && <DropdownMenuSeparator />}
                  <DropdownMenuLabel>{group.label}</DropdownMenuLabel>
                  <DropdownMenuRadioGroup
                    value={filters[group.key]}
                    onValueChange={(value) => setFilter(group.key, value)}
                  >
                    {group.options.map((option) => (
                      <DropdownMenuRadioItem
                        key={option}
                        value={option}
                        onSelect={(event) => event.preventDefault()}
                      >
                        {option}
                      </DropdownMenuRadioItem>
                    ))}
                  </DropdownMenuRadioGroup>
                </div>
              ))}
              {activeFilterCount > 0 && (
                <>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onSelect={(event) => event.preventDefault()} onClick={() => setFilters(EMPTY_FILTERS)}>
                    Clear all filters
                  </DropdownMenuItem>
                </>
              )}
            </DropdownMenuContent>
          </DropdownMenu>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" className="rounded-lg">
                Sort
                <ChevronDown className="size-3.5" aria-hidden="true" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuRadioGroup value={sort} onValueChange={setSort}>
                {SORT_OPTIONS.map((option) => (
                  <DropdownMenuRadioItem key={option.key} value={option.key}>
                    {option.label}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {columns.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">
          No columns selected — pick columns from the Columns menu.
        </p>
      ) : (
      <div className="overflow-x-auto">
        <table className="w-full min-w-[680px] border-collapse text-sm">
          <thead>
            <tr className="border-b border-border text-left text-[11px] font-medium tracking-wide text-muted-foreground uppercase">
              {columns.map((col) => {
                const sortable = SORTABLE_HEADERS.has(col.key)
                const active = sort === col.key || (col.key === 'time' && (sort === 'newest' || sort === 'oldest'))
                return (
                  <th
                    key={col.key}
                    scope="col"
                    draggable
                    onDragStart={(event) => {
                      setDragKey(col.key)
                      event.dataTransfer.effectAllowed = 'move'
                    }}
                    onDragOver={(event) => {
                      event.preventDefault()
                      event.dataTransfer.dropEffect = 'move'
                      if (dragOverKey !== col.key) setDragOverKey(col.key)
                    }}
                    onDragLeave={() => setDragOverKey((key) => (key === col.key ? null : key))}
                    onDrop={(event) => {
                      event.preventDefault()
                      moveColumn(dragKey, col.key)
                      setDragKey(null)
                      setDragOverKey(null)
                    }}
                    onDragEnd={() => {
                      setDragKey(null)
                      setDragOverKey(null)
                    }}
                    onKeyDown={(event) => {
                      if (event.key === 'ArrowRight') {
                        event.preventDefault()
                        nudgeColumn(col.key, 1)
                      } else if (event.key === 'ArrowLeft') {
                        event.preventDefault()
                        nudgeColumn(col.key, -1)
                      }
                    }}
                    tabIndex={0}
                    aria-label={`${col.label} column. Drag, or press left or right arrow, to reorder.`}
                    className={cn(
                      'group/th cursor-grab py-2 pr-4 font-medium outline-none select-none active:cursor-grabbing focus-visible:text-foreground',
                      col.key === 'time' && 'text-right',
                      dragKey === col.key && 'opacity-40',
                      dragOverKey === col.key && dragKey !== col.key && 'shadow-[inset_2px_0_0_#1362FE]',
                    )}
                  >
                    <span className="inline-flex items-center gap-1">
                      <GripVertical
                        className="size-3 shrink-0 text-muted-foreground/40 transition-colors group-hover/th:text-muted-foreground"
                        aria-hidden="true"
                      />
                      {sortable ? (
                        <button
                          type="button"
                          onClick={() => sortByHeader(col.key)}
                          className={cn(
                            'inline-flex items-center gap-1 uppercase transition-colors hover:text-foreground',
                            active && 'text-foreground',
                          )}
                        >
                          {col.label}
                          <ChevronsUpDown className="size-3 opacity-60" aria-hidden="true" />
                        </button>
                      ) : (
                        col.label
                      )}
                    </span>
                  </th>
                )
              })}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((row) => (
              <tr key={row.key} className="transition-colors hover:bg-muted/40">
                {columns.map((col) => {
                  const value = cellValue(row, col.key)
                  return (
                    <td
                      key={col.key}
                      className={cn(
                        'py-3.5 pr-4 align-middle whitespace-nowrap',
                        col.key === 'activity' ? 'font-medium text-foreground' : 'text-muted-foreground',
                        MONO_COLUMNS.has(col.key) && 'font-mono text-xs tabular-nums',
                        col.key === 'time' && 'text-right',
                      )}
                    >
                      {value ?? DASH}
                    </td>
                  )
                })}
              </tr>
            ))}
            {rows.length === 0 && (
              <tr>
                <td colSpan={columns.length} className="py-12 text-center text-sm text-muted-foreground">
                  No activity matches the current search and filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      )}
    </div>
  )
}
