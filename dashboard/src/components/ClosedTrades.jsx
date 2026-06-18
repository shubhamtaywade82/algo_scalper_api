import { createSignal, createMemo, onMount, createEffect } from 'solid-js'
import { Show, For } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import { dashboardApiHeaders } from '../lib/dashboardApi'

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

function exitBadge(pos) {
  const reason = (pos.exit_reason || '').toLowerCase()

  if (reason.includes('premium_momentum')) return { label: 'PMF', cls: 'text-amber-400 border-amber-500/30' }
  if (reason.includes('stop_loss') || reason.includes('premium_r_stop')) {
    return { label: 'SL', cls: 'text-red-400 border-red-500/30' }
  }
  if (reason.includes('structure')) return { label: 'STRUCT', cls: 'text-orange-400 border-orange-500/30' }
  if (reason.includes('time')) return { label: 'TIME', cls: 'text-yellow-400 border-yellow-500/30' }
  if (reason.includes('trail')) return { label: 'TRAIL', cls: 'text-blue-400 border-blue-500/30' }
  if (reason.includes('take_profit') || reason.includes('profit_floor')) {
    return { label: 'TP', cls: 'text-emerald-400 border-emerald-500/30' }
  }
  if (reason.includes('manual')) return { label: 'MNL', cls: 'text-purple-400 border-purple-500/30' }

  const classification = pos.exit_classification
  if (classification === 'profit') return { label: 'TP', cls: 'text-emerald-400 border-emerald-500/30' }
  if (classification === 'loss') return { label: 'SL', cls: 'text-red-400 border-red-500/30' }
  if (classification === 'breakeven') return { label: 'BE', cls: 'text-yellow-400 border-yellow-500/30' }
  if (!pos.exit_reason) return { label: '—', cls: 'text-gray-600 border-gray-700' }

  return { label: reason.slice(0, 8).toUpperCase(), cls: 'text-gray-400 border-gray-700' }
}

const SORT_COLS = [
  { key: 'exited_at', label: 'Time' },
  { key: 'symbol', label: 'Asset' },
  { key: 'side', label: 'Side' },
  { key: 'quantity', label: 'Qty' },
  { key: 'entry_price', label: 'Entry' },
  { key: 'last_pnl_rupees', label: 'Net P&L' },
]

function SortHeader(props) {
  const isActive = () => props.sortBy === props.col
  const dir = () => props.sortDir

  return (
    <th
      class={`px-4 py-3 font-bold cursor-pointer select-none whitespace-nowrap hover:text-gray-300 transition-colors ${props.align === 'left' ? 'text-left' : props.align === 'center' ? 'text-center' : 'text-right'} ${isActive() ? 'text-gray-200' : 'text-gray-600'}`}
      onClick={() => props.onSort(props.col)}
    >
      {props.label}
      <Show when={isActive()}>
        <span class="ml-1 text-cyan-500">{dir() === 'asc' ? '↑' : '↓'}</span>
      </Show>
    </th>
  )
}

export default function ClosedTrades() {
  const ctx = useDashboardContext()

  const [positions, setPositions] = createSignal([])
  const [availableDates, setAvailableDates] = createSignal([])
  const [summary, setSummary] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  // Filters
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
      const res = await fetch(`/api/positions?${buildQuery()}`, { headers: dashboardApiHeaders() })
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
          <div class="w-1.5 h-6 bg-gray-600 rounded-full"></div>
          <h2 class="text-xs font-bold text-gray-400 uppercase tracking-[0.2em]">
            Completed Trades
            <span class="text-gray-600 ml-2 font-black text-data">[{positions().length}]</span>
          </h2>
        </div>
        <button
          onClick={fetchPositions}
          disabled={loading()}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40 transition-colors"
        >
          {loading() ? '↻ Loading...' : '↻ Refresh'}
        </button>
      </div>

      {/* Filters */}
      <div class="px-6 py-5 border-b border-white/5 bg-white/[0.005] flex flex-wrap items-end gap-4">
        {/* Date dropdown */}
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Date</label>
          <select
            value={selectedDate()}
            onChange={(e) => { setSelectedDate(e.target.value); fetchPositions() }}
            class="glass-select text-xs rounded-xl px-3 py-2 min-w-[140px]"
          >
            <For each={availableDates()}>
              {(d) => <option value={d}>{d}</option>}
            </For>
            <Show when={availableDates().length === 0}>
              <option value="">{selectedDate() || 'Today'}</option>
            </Show>
          </select>
        </div>

        {/* Index filter */}
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Index</label>
          <select
            value={indexKey()}
            onChange={(e) => setIndexKey(e.target.value)}
            class="glass-select text-xs rounded-xl px-3 py-2 min-w-[110px]"
          >
            <option value="">All</option>
            <option value="NIFTY">NIFTY</option>
            <option value="BANKNIFTY">BANKNIFTY</option>
            <option value="SENSEX">SENSEX</option>
          </select>
        </div>

        {/* Option type */}
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Type</label>
          <select
            value={optionType()}
            onChange={(e) => setOptionType(e.target.value)}
            class="glass-select text-xs rounded-xl px-3 py-2 min-w-[110px]"
          >
            <option value="">CE + PE</option>
            <option value="CE">CE</option>
            <option value="PE">PE</option>
          </select>
        </div>

        {/* Outcome */}
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Outcome</label>
          <select
            value={outcome()}
            onChange={(e) => setOutcome(e.target.value)}
            class="glass-select text-xs rounded-xl px-3 py-2 min-w-[125px]"
          >
            <option value="">All</option>
            <option value="profit">Profit</option>
            <option value="loss">Loss</option>
            <option value="breakeven">Breakeven</option>
          </select>
        </div>

        {/* Side */}
        <div class="flex flex-col gap-1.5">
          <label class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Side</label>
          <select
            value={side()}
            onChange={(e) => setSide(e.target.value)}
            class="glass-select text-xs rounded-xl px-3 py-2 min-w-[90px]"
          >
            <option value="">All</option>
            <option value="BUY">BUY</option>
            <option value="SELL">SELL</option>
          </select>
        </div>

        <div class="flex gap-2 ml-auto">
          <button
            onClick={applyFilter}
            class="px-5 py-2 bg-primary-600 hover:bg-primary-500 text-white text-[10px] font-black uppercase tracking-widest rounded-xl transition-all shadow-[0_4px_15px_rgba(59,130,246,0.15)] hover:shadow-[0_4px_20px_rgba(59,130,246,0.35)] cursor-pointer"
          >
            Apply
          </button>
          <button
            onClick={resetFilters}
            class="px-5 py-2 border border-white/10 hover:border-white/25 text-gray-400 hover:text-gray-200 text-[10px] font-black uppercase tracking-widest rounded-xl transition-all cursor-pointer"
          >
            Reset
          </button>
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
          <table class="w-full border-collapse">
            <thead>
              <tr class="text-[9px] uppercase tracking-widest border-b border-white/5 bg-white/[0.005]">
                <SortHeader col="symbol" label="Asset" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="side" label="Side" align="center" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="quantity" label="Qty" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="entry_price" label="Entry" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <th class="text-right px-4 py-3 font-bold text-gray-600">Exit</th>
                <SortHeader col="last_pnl_rupees" label="Net P&L" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <th class="text-right px-4 py-3 font-bold text-gray-600">% P/L</th>
                <th class="text-center px-4 py-3 font-bold text-gray-600">Source</th>
                <SortHeader col="exited_at" label="Time" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <For each={positions()}>
                {(pos) => {
                  const badge = exitBadge(pos)
                  return (
                    <tr class="group hover:bg-white/[0.02] transition-colors">
                      <td class="px-6 py-4">
                        <span class="text-xs font-bold text-gray-500 uppercase tracking-tight group-hover:text-gray-300 transition-colors">{pos.symbol}</span>
                      </td>
                      <td class="px-4 py-4 text-center">
                        <span class={`text-[9px] font-black px-2 py-0.5 rounded tracking-tighter uppercase inline-block min-w-[40px] opacity-70 group-hover:opacity-100 transition-opacity ${pos.side === 'BUY' ? 'bg-primary-900/30 text-primary-400 border border-primary-500/20' : 'bg-rose-900/30 text-rose-400 border border-rose-500/20'}`}>
                          {pos.side}
                        </span>
                      </td>
                      <td class="px-4 py-4 text-right text-gray-600 text-data text-xs">{pos.quantity}</td>
                      <td class="px-4 py-4 text-right text-gray-600 text-data text-xs">{inr(pos.entry_price)}</td>
                      <td class="px-4 py-4 text-right text-gray-500 text-data text-xs">{inr(pos.exit_price)}</td>
                      <td class={`px-4 py-4 text-right font-bold text-data text-xs ${pnlClass(pos.pnl)}`}>
                        {sign(pos.pnl)}₹{inr(pos.pnl)}
                      </td>
                      <td class={`px-4 py-4 text-right text-data font-medium text-xs ${pnlClass(pos.pnl_pct)}`}>
                        {sign(pos.pnl_pct)}{inr(pos.pnl_pct)}%
                      </td>
                      <td class="px-4 py-4 text-center">
                        <span class={`text-[9px] font-black px-1.5 py-0.5 rounded border tracking-widest ${badge.cls}`}>
                          {badge.label}
                        </span>
                      </td>
                      <td class="px-6 py-4 text-right text-gray-600 text-data text-[10px]">{formatTime(pos.exited_at)}</td>
                    </tr>
                  )
                }}
              </For>
            </tbody>
          </table>
        </div>
      </Show>
    </div>
  )
}
