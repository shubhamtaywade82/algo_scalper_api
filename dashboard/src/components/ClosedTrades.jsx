import { createSignal, createMemo, onMount, createEffect } from 'solid-js'
import { Show, For } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import Button from './ui/Button'
import Badge from './ui/Badge'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from './ui/Table'
import { exitBadge } from '../lib/exitBadge'

function inr(val, dec = 2) {
  if (val == null) return '—'
  return Math.abs(Number(val)).toLocaleString('en-IN', { minimumFractionDigits: dec, maximumFractionDigits: dec })
}

function pnlClass(val) {
  const n = Number(val)
  if (!n) return 'text-gray-500'
  return n > 0 ? 'text-emerald-400' : 'text-red-400'
}

function sign(val) {
  const n = Number(val)
  return n > 0 ? '+' : n < 0 ? '−' : ''
}

function formatTime(iso) {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: false })
  } catch {
    return '—'
  }
}

const SORT_COLS = [
  { key: 'exited_at', label: 'Time' },
  { key: 'symbol', label: 'Asset' },
  { key: 'side', label: 'Side' },
  { key: 'quantity', label: 'Qty' },
  { key: 'entry_price', label: 'Entry' },
  { key: 'last_pnl_rupees', label: 'Net P&L' },
]

const badgeVariantMap = {
  'text-emerald-400 border-emerald-500/30': 'success',
  'text-red-400 border-red-500/30': 'danger',
  'text-rose-400 border-rose-500/30': 'danger',
  'text-amber-400 border-amber-500/30': 'warning',
  'text-yellow-400 border-yellow-500/30': 'warning',
  'text-orange-400 border-orange-500/30': 'warning',
  'text-cyan-400 border-cyan-500/30': 'info',
  'text-blue-400 border-blue-500/30': 'info',
  'text-purple-400 border-purple-500/30': 'info',
  'text-gray-400 border-gray-700': 'outline',
  'text-gray-600 border-gray-700': 'outline',
}

function badgeVariant(cls) {
  return badgeVariantMap[cls] || 'outline'
}

function SortHeader(props) {
  const isActive = () => props.sortBy === props.col
  const dir = () => props.sortDir

  return (
    <TableHead
      class={`px-4 py-3 font-bold cursor-pointer select-none whitespace-nowrap hover:text-gray-300 transition-colors ${props.align === 'left' ? 'text-left' : props.align === 'center' ? 'text-center' : 'text-right'} ${isActive() ? 'text-gray-200' : 'text-gray-600'}`}
      onClick={() => props.onSort(props.col)}
    >
      {props.label}
      <Show when={isActive()}>
        <span class="ml-1 text-cyan-500">{dir() === 'asc' ? '↑' : '↓'}</span>
      </Show>
    </TableHead>
  )
}

export default function ClosedTrades() {
  const ctx = useDashboardContext()

  const [positions, setPositions] = createSignal([])
  const [availableDates, setAvailableDates] = createSignal([])
  const [summary, setSummary] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  const [selectedDate, setSelectedDate] = createSignal('')
  const [indexKey, setIndexKey] = createSignal('')
  const [optionType, setOptionType] = createSignal('')
  const [outcome, setOutcome] = createSignal('')
  const [side, setSide] = createSignal('')
  const [sortBy, setSortBy] = createSignal('exited_at')
  const [sortDir, setSortDir] = createSignal('desc')

  function buildQuery() {
    const p = new URLSearchParams()
    if (selectedDate()) p.set('date', selectedDate())
    if (indexKey()) p.set('index_key', indexKey())
    if (optionType()) p.set('option_type', optionType())
    if (outcome()) p.set('outcome', outcome())
    if (side()) p.set('side', side())
    p.set('sort_by', sortBy())
    p.set('sort_dir', sortDir())
    return p.toString()
  }

  async function fetchPositions() {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`/api/positions?${buildQuery()}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setPositions(data.closed || [])
      setAvailableDates(data.available_dates || [])
      setSummary(data.summary || null)
      if (!selectedDate() && data.summary?.date) {
        setSelectedDate(data.summary.date)
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  function handleSort(col) {
    if (sortBy() === col) {
      setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    } else {
      setSortBy(col)
      setSortDir('desc')
    }
    fetchPositions()
  }

  function applyFilter() {
    fetchPositions()
  }

  function resetFilters() {
    setIndexKey('')
    setOptionType('')
    setOutcome('')
    setSide('')
    setSortBy('exited_at')
    setSortDir('desc')
    fetchPositions()
  }

  onMount(fetchPositions)

  // Open positions hook refreshes `closed` on WS `position_exited` / poll; this table
  // keeps its own filtered fetch — re-run when global closed-set changes (by id).
  let prevClosedIds = null
  createEffect(() => {
    const list = ctx?.closed?.() || []
    const ids = list.map((c) => c.id).sort().join(',')
    if (prevClosedIds !== null && ids !== prevClosedIds) fetchPositions()
    prevClosedIds = ids
  })

  const totalPnl = createMemo(() => summary()?.total_pnl ?? 0)
  const profitCount = createMemo(() => summary()?.profit_count ?? 0)
  const lossCount = createMemo(() => summary()?.loss_count ?? 0)
  const totalCount = createMemo(() => summary()?.total ?? 0)

  return (
    <div class="glass rounded-2xl overflow-hidden mt-8 opacity-90 transition-opacity hover:opacity-100">
      {/* Header */}
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.01]">
        <div class="flex items-center gap-3">
          <div class="w-1.5 h-6 bg-gray-600 rounded-full" />
          <h2 class="text-xs font-bold text-gray-400 uppercase tracking-[0.2em]">
            Completed Trades
            <span class="text-gray-600 ml-2 font-black text-data">[{positions().length}]</span>
          </h2>
        </div>
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={fetchPositions}
          disabled={loading()}
          leftIcon={loading() ? undefined : <span>↻</span>}
        >
          {loading() ? '↻ Loading...' : '↻ Refresh'}
        </Button>
      </div>

      {/* Filters */}
      <div class="px-6 py-5 border-b border-white/5 bg-white/[0.005] flex flex-wrap items-end gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Date</label>
          <select
            value={selectedDate()}
            onChange={(e) => { setSelectedDate(e.target.value); fetchPositions() }}
            class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none min-w-[130px]"
          >
            <For each={availableDates()}>
              {(d) => <option value={d}>{d}</option>}
            </For>
            <Show when={availableDates().length === 0}>
              <option value="">{selectedDate() || 'Today'}</option>
            </Show>
          </select>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Index</label>
          <select
            value={indexKey()}
            onChange={(e) => setIndexKey(e.target.value)}
            class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
          >
            <option value="">All</option>
            <option value="NIFTY">NIFTY</option>
            <option value="BANKNIFTY">BANKNIFTY</option>
            <option value="SENSEX">SENSEX</option>
          </select>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Type</label>
          <select
            value={optionType()}
            onChange={(e) => setOptionType(e.target.value)}
            class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
          >
            <option value="">CE + PE</option>
            <option value="CE">CE</option>
            <option value="PE">PE</option>
          </select>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Outcome</label>
          <select
            value={outcome()}
            onChange={(e) => setOutcome(e.target.value)}
            class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
          >
            <option value="">All</option>
            <option value="profit">Profit</option>
            <option value="loss">Loss</option>
            <option value="breakeven">Breakeven</option>
          </select>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Side</label>
          <select
            value={side()}
            onChange={(e) => setSide(e.target.value)}
            class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
          >
            <option value="">All</option>
            <option value="BUY">BUY</option>
            <option value="SELL">SELL</option>
          </select>
        </div>

        <div class="flex gap-2 ml-auto">
          <Button
            variant="default"
            class="!bg-primary-600 hover:!bg-primary-500 text-[10px] font-black uppercase tracking-widest rounded-xl shadow-[0_4px_15px_rgba(59,130,246,0.15)] hover:shadow-[0_4px_20px_rgba(59,130,246,0.35)]"
            onClick={applyFilter}
          >
            Apply
          </Button>
          <Button
            variant="outline"
            class="text-[10px] font-black uppercase tracking-widest rounded-xl"
            onClick={resetFilters}
          >
            Reset
          </Button>
        </div>
      </div>

      {/* Summary bar */}
      <Show when={summary()}>
        <div class="px-6 py-3 border-b border-white/5 flex items-center gap-6 flex-wrap text-[10px]">
          <span class="font-black text-gray-500 uppercase tracking-widest">
            {summary()?.date}
          </span>
          <span class="text-gray-500">
            <span class="font-black text-gray-300">{totalCount()}</span> trades
          </span>
          <span class="text-emerald-400">
            <span class="font-black">{profitCount()}</span> wins
          </span>
          <span class="text-red-400">
            <span class="font-black">{lossCount()}</span> losses
          </span>
          <span class={`font-black ml-auto text-sm ${pnlClass(totalPnl())}`}>
            {sign(totalPnl())}₹{inr(totalPnl())}
          </span>
        </div>
      </Show>

      <Show when={error()}>
        <div class="px-6 py-3 text-rose-400 text-xs">⚠ {error()}</div>
      </Show>

      <Show when={positions().length === 0 && !loading()}>
        <div class="flex flex-col items-center justify-center py-16 text-gray-700">
          <p class="text-[10px] uppercase tracking-widest font-bold">No closed trades for this selection</p>
        </div>
      </Show>

      <Show when={loading() && positions().length === 0}>
        <div class="flex flex-col items-center justify-center py-16 text-gray-700">
          <p class="text-[10px] uppercase tracking-widest font-bold">Loading...</p>
        </div>
      </Show>

      <Show when={positions().length > 0}>
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="text-[9px] uppercase tracking-widest border-b border-white/5 bg-white/[0.005]">
                <SortHeader col="symbol" label="Asset" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="side" label="Side" align="center" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="quantity" label="Qty" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="entry_price" label="Entry" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <TableHead class="text-right px-4 py-3 font-bold text-gray-600">Exit</TableHead>
                <SortHeader col="last_pnl_rupees" label="Net P&L" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <TableHead class="text-right px-4 py-3 font-bold text-gray-600">% P/L</TableHead>
                <TableHead class="text-center px-4 py-3 font-bold text-gray-600">Source</TableHead>
                <SortHeader col="exited_at" label="Time" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
              </TableRow>
            </TableHeader>
            <TableBody class="divide-y divide-white/5">
              <For each={positions()}>
                {(pos) => {
                  const badge = exitBadge(pos)
                  return (
                    <TableRow class="group hover:bg-white/[0.02] transition-colors">
                      <TableCell class="px-6 py-4">
                        <span class="text-xs font-bold text-gray-500 uppercase tracking-tight group-hover:text-gray-300 transition-colors">{pos.symbol}</span>
                      </TableCell>
                      <TableCell class="px-4 py-4 text-center">
                        <Badge
                          variant={pos.side === 'BUY' ? 'info' : 'danger'}
                          class="text-[9px] font-black px-2 py-0.5 rounded tracking-tighter uppercase"
                        >
                          {pos.side}
                        </Badge>
                      </TableCell>
                      <TableCell class="px-4 py-4 text-right text-gray-600 text-data text-xs">{pos.quantity}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-gray-600 text-data text-xs">{inr(pos.entry_price)}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-gray-500 text-data text-xs">{inr(pos.exit_price)}</TableCell>
                      <TableCell class={`px-4 py-4 text-right font-bold text-data text-xs ${pnlClass(pos.pnl)}`}>
                        {sign(pos.pnl)}₹{inr(pos.pnl)}
                      </TableCell>
                      <TableCell class={`px-4 py-4 text-right text-data font-medium text-xs ${pnlClass(pos.pnl_pct)}`}>
                        {sign(pos.pnl_pct)}{inr(pos.pnl_pct)}%
                      </TableCell>
                      <TableCell class="px-4 py-4 text-center">
                        <Badge
                          variant={badgeVariant(badge.cls)}
                          class="text-[9px] font-black px-1.5 py-0.5 rounded tracking-widest"
                        >
                          {badge.label}
                        </Badge>
                      </TableCell>
                      <TableCell class="px-6 py-4 text-right text-gray-600 text-data text-[10px]">{formatTime(pos.exited_at)}</TableCell>
                    </TableRow>
                  )
                }}
              </For>
            </TableBody>
          </Table>
        </div>
      </Show>
    </div>
  )
}
