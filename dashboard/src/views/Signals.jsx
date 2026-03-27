import { createSignal, createMemo, onMount } from 'solid-js'
import { For, Show } from 'solid-js'

function formatTime(timestamp) {
  if (!timestamp) return '—'
  try {
    const d = new Date(timestamp)
    if (isNaN(d.getTime())) return '—'
    return d.toLocaleString('en-IN', {
      day: '2-digit', month: 'short',
      hour: '2-digit', minute: '2-digit', hour12: false
    })
  } catch {
    return '—'
  }
}

function getSignalClass(direction) {
  const dir = String(direction || '').toLowerCase()
  if (dir.includes('bullish') || dir.includes('buy')) return 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20'
  if (dir.includes('bearish') || dir.includes('sell')) return 'text-rose-400 bg-rose-500/10 border-rose-500/20'
  return 'text-gray-400 bg-gray-500/10 border-gray-500/20'
}

function getConfidenceClass(level) {
  const l = String(level || '').toLowerCase()
  if (l.includes('very_high')) return 'bg-emerald-500'
  if (l.includes('high')) return 'bg-emerald-400'
  if (l.includes('medium')) return 'bg-amber-400'
  if (l.includes('low')) return 'bg-rose-400'
  return 'bg-gray-500'
}

function getEntryOutcomeStyle(outcome) {
  switch (outcome) {
    case 'entered': return { cls: 'text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 rounded-full', label: '● ENTERED' }
    case 'blocked': return { cls: 'text-amber-400 bg-amber-500/10 border border-amber-500/20 rounded-full', label: '✗ BLOCKED' }
    case 'skipped': return { cls: 'text-gray-500 bg-gray-500/10 border border-gray-500/20 rounded-full', label: '◌ SKIPPED' }
    default: return { cls: 'text-gray-600', label: '— —' }
  }
}

const SORT_COLS = [
  { key: 'signal_timestamp', label: 'Time' },
  { key: 'index_key', label: 'Instrument' },
  { key: 'direction', label: 'Signal' },
  { key: 'confidence_score', label: 'Confidence' },
  { key: 'adx_value', label: 'ADX' },
]

function SortHeader(props) {
  const isActive = () => props.sortBy === props.col
  return (
    <th
      class={`p-4 text-[10px] font-black uppercase tracking-widest border-b border-white/5 cursor-pointer select-none hover:text-gray-300 transition-colors ${props.align === 'right' ? 'text-right' : props.align === 'center' ? 'text-center' : 'text-left'} ${isActive() ? 'text-gray-200' : 'text-gray-500'}`}
      onClick={() => props.onSort(props.col)}
    >
      {props.label}
      <Show when={isActive()}>
        <span class="ml-1 text-cyan-500">{props.sortDir === 'asc' ? '↑' : '↓'}</span>
      </Show>
    </th>
  )
}

const PER_PAGE_OPTIONS = [10, 25, 50, 100]

export default function Signals() {
  const [signals, setSignals] = createSignal([])
  const [meta, setMeta] = createSignal({ total: 0, page: 1, per_page: 25, pages: 0 })
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  // Filters
  const [indexKey, setIndexKey] = createSignal('')
  const [direction, setDirection] = createSignal('')
  const [entryOutcome, setEntryOutcome] = createSignal('')
  const [confidenceMin, setConfidenceMin] = createSignal('')
  const [dateFrom, setDateFrom] = createSignal('')
  const [dateTo, setDateTo] = createSignal('')

  // Sort + pagination
  const [sortBy, setSortBy] = createSignal('signal_timestamp')
  const [sortDir, setSortDir] = createSignal('desc')
  const [page, setPage] = createSignal(1)
  const [perPage, setPerPage] = createSignal(25)

  function buildQuery() {
    const p = new URLSearchParams()
    if (indexKey()) p.set('index_key', indexKey())
    if (direction()) p.set('direction', direction())
    if (entryOutcome()) p.set('outcome', entryOutcome())
    if (confidenceMin()) p.set('confidence_min', confidenceMin())
    if (dateFrom()) p.set('date_from', dateFrom())
    if (dateTo()) p.set('date_to', dateTo())
    p.set('sort_by', sortBy())
    p.set('sort_dir', sortDir())
    p.set('page', page())
    p.set('per_page', perPage())
    return p.toString()
  }

  async function fetchSignals() {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`/api/signals?${buildQuery()}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setSignals(data.signals || [])
      setMeta(data.meta || { total: 0, page: 1, per_page: 25, pages: 0 })
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
    setPage(1)
    fetchSignals()
  }

  function applyFilters() {
    setPage(1)
    fetchSignals()
  }

  function resetFilters() {
    setIndexKey('')
    setDirection('')
    setEntryOutcome('')
    setConfidenceMin('')
    setDateFrom('')
    setDateTo('')
    setSortBy('signal_timestamp')
    setSortDir('desc')
    setPage(1)
    fetchSignals()
  }

  function goToPage(p) {
    setPage(p)
    fetchSignals()
  }

  function changePerPage(val) {
    setPerPage(Number(val))
    setPage(1)
    fetchSignals()
  }

  onMount(fetchSignals)

  const processedSignals = createMemo(() =>
    signals().map(sig => {
      const outcome = sig.metadata?.entry_outcome || 'pending'
      const style = getEntryOutcomeStyle(outcome)
      return {
        ...sig,
        displayTime: formatTime(sig.signal_timestamp),
        displayStrategy: String(sig.metadata?.strategy || 'Supertrend').replace(/_/g, ' '),
        displayAdx: Number(sig.adx_value || 0).toFixed(1),
        displaySt: Number(sig.supertrend_value || 0).toFixed(0),
        displayConfidence: String(sig.confidence_level || '').replace(/_/g, ' '),
        signalClass: getSignalClass(sig.direction),
        confidenceBars: Math.round((Number(sig.confidence_score) || 0) * 5),
        confidenceClass: getConfidenceClass(sig.confidence_level),
        entryOutcome: outcome,
        entryBlockedReason: sig.metadata?.entry_blocked_reason || null,
        entryOutcomeCls: style.cls,
        entryOutcomeLabel: style.label
      }
    })
  )

  const pageNumbers = createMemo(() => {
    const total = meta().pages
    const cur = meta().page
    if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)
    const pages = new Set([1, total, cur])
    if (cur > 1) pages.add(cur - 1)
    if (cur < total) pages.add(cur + 1)
    return [...pages].sort((a, b) => a - b)
  })

  return (
    <div class="flex flex-col gap-6">
      {/* Title */}
      <div class="flex items-center justify-between px-2">
        <h2 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-amber-500"></span>
          Signal Intelligence
        </h2>
        <div class="flex items-center gap-3">
          <Show when={meta().total > 0}>
            <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter">
              {meta().total} signals
            </span>
          </Show>
          <button
            onClick={fetchSignals}
            disabled={loading()}
            class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40 transition-colors"
          >
            {loading() ? '↻ Loading...' : '↻ Refresh'}
          </button>
        </div>
      </div>

      {/* Filter panel */}
      <div class="glass rounded-2xl border border-white/5 px-6 py-4">
        <div class="flex flex-wrap items-end gap-4">
          {/* Index */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">Index</label>
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

          {/* Direction */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">Direction</label>
            <select
              value={direction()}
              onChange={(e) => setDirection(e.target.value)}
              class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
            >
              <option value="">All</option>
              <option value="bullish">Bullish</option>
              <option value="bearish">Bearish</option>
            </select>
          </div>

          {/* Entry Outcome */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">Entry Outcome</label>
            <select
              value={entryOutcome()}
              onChange={(e) => setEntryOutcome(e.target.value)}
              class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
            >
              <option value="">All</option>
              <option value="entered">Entered</option>
              <option value="blocked">Blocked</option>
              <option value="skipped">Skipped</option>
            </select>
          </div>

          {/* Confidence min */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">Min Confidence</label>
            <input
              type="number"
              value={confidenceMin()}
              onInput={(e) => setConfidenceMin(e.target.value)}
              placeholder="0.0 – 1.0"
              min="0" max="1" step="0.05"
              class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none w-28"
            />
          </div>

          {/* Date from */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">From</label>
            <input
              type="date"
              value={dateFrom()}
              onInput={(e) => setDateFrom(e.target.value)}
              class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
            />
          </div>

          {/* Date to */}
          <div class="flex flex-col gap-1">
            <label class="text-[9px] font-black text-gray-600 uppercase tracking-widest">To</label>
            <input
              type="date"
              value={dateTo()}
              onInput={(e) => setDateTo(e.target.value)}
              class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:ring-1 focus:ring-cyan-500 outline-none"
            />
          </div>

          <div class="flex gap-2 ml-auto">
            <button
              onClick={applyFilters}
              class="px-4 py-1.5 bg-cyan-700 hover:bg-cyan-600 text-white text-[10px] font-black uppercase tracking-widest rounded transition-colors"
            >
              Apply
            </button>
            <button
              onClick={resetFilters}
              class="px-4 py-1.5 border border-gray-700 hover:border-gray-500 text-gray-400 hover:text-gray-200 text-[10px] font-black uppercase tracking-widest rounded transition-colors"
            >
              Reset
            </button>
          </div>
        </div>
      </div>

      <Show when={error()}>
        <div class="text-rose-400 text-xs px-2">⚠ {error()}</div>
      </Show>

      {/* Table */}
      <div class="glass rounded-3xl overflow-hidden border border-white/5 shadow-2xl">
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="bg-white/[0.02]">
                <SortHeader col="signal_timestamp" label="Time" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="index_key" label="Instrument" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="direction" label="Signal" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <th class="p-4 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Strategy</th>
                <th class="p-4 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Entry</th>
                <SortHeader col="adx_value" label="Analysis" align="left" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
                <SortHeader col="confidence_score" label="Confidence" align="right" sortBy={sortBy()} sortDir={sortDir()} onSort={handleSort} />
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <Show when={loading()}>
                <tr>
                  <td colspan="7" class="p-12 text-center text-gray-600 text-xs uppercase tracking-widest">Loading...</td>
                </tr>
              </Show>
              <Show when={!loading()}>
                <For each={processedSignals()}>
                  {(sig) => (
                    <tr class="hover:bg-white/[0.03] transition-colors group">
                      <td class="p-4 pl-6">
                        <span class="text-xs font-bold text-gray-400 text-data">{sig.displayTime}</span>
                      </td>
                      <td class="p-4">
                        <div class="flex flex-col">
                          <span class="text-sm font-black text-white">{sig.index_key}</span>
                          <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter mt-0.5">{sig.timeframe}</span>
                        </div>
                      </td>
                      <td class="p-4">
                        <div class={`px-3 py-1 rounded-full border text-[10px] font-black uppercase inline-block tracking-widest ${sig.signalClass}`}>
                          {sig.direction}
                        </div>
                      </td>
                      <td class="p-4">
                        <span class="text-[10px] font-black text-gray-300 uppercase tracking-wide bg-white/5 px-2 py-1 rounded">{sig.displayStrategy}</span>
                      </td>
                      <td class="p-4">
                        <span
                          class={`px-3 py-1 text-[9px] font-black uppercase tracking-widest inline-block ${sig.entryOutcomeCls}`}
                          title={sig.entryBlockedReason || ''}
                        >
                          {sig.entryOutcomeLabel}
                        </span>
                      </td>
                      <td class="p-4">
                        <div class="flex items-center gap-3">
                          <div class="flex flex-col">
                            <span class="text-[9px] font-black text-gray-600 uppercase tracking-widest">ADX</span>
                            <span class="text-xs font-bold text-white text-data">{sig.displayAdx}</span>
                          </div>
                          <div class="w-[1px] h-6 bg-white/10"></div>
                          <div class="flex flex-col">
                            <span class="text-[9px] font-black text-gray-600 uppercase tracking-widest">ST</span>
                            <span class="text-xs font-bold text-white text-data">{sig.displaySt}</span>
                          </div>
                        </div>
                      </td>
                      <td class="p-4 pr-6 text-right">
                        <div class="flex items-center justify-end gap-3">
                          <span class="text-[10px] font-black text-gray-500 uppercase tracking-tighter">{sig.displayConfidence}</span>
                          <div class="flex gap-1">
                            <For each={[1, 2, 3, 4, 5]}>
                              {(i) => (
                                <div class={`w-1.5 h-4 rounded-full ${i <= sig.confidenceBars ? sig.confidenceClass : 'bg-white/5'}`}></div>
                              )}
                            </For>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </For>
                <Show when={processedSignals().length === 0}>
                  <tr>
                    <td colspan="7" class="p-20 text-center">
                      <div class="flex flex-col items-center gap-4">
                        <div class="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center">
                          <span class="text-gray-600">📭</span>
                        </div>
                        <span class="text-sm font-bold text-gray-600 uppercase tracking-[0.2em]">No signals match your filters</span>
                      </div>
                    </td>
                  </tr>
                </Show>
              </Show>
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <Show when={meta().pages > 1 || meta().total > 0}>
          <div class="flex items-center justify-between px-6 py-4 border-t border-white/5 bg-white/[0.005]">
            {/* Per-page selector */}
            <div class="flex items-center gap-2">
              <span class="text-[9px] font-black text-gray-600 uppercase tracking-widest">Per page</span>
              <select
                value={perPage()}
                onChange={(e) => changePerPage(e.target.value)}
                class="bg-gray-900 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1 focus:ring-1 focus:ring-cyan-500 outline-none"
              >
                <For each={PER_PAGE_OPTIONS}>
                  {(opt) => <option value={opt}>{opt}</option>}
                </For>
              </select>
            </div>

            {/* Page info + controls */}
            <div class="flex items-center gap-2">
              <span class="text-[10px] text-gray-600 mr-2">
                {(meta().page - 1) * meta().per_page + 1}–{Math.min(meta().page * meta().per_page, meta().total)} of {meta().total}
              </span>

              <button
                onClick={() => goToPage(meta().page - 1)}
                disabled={meta().page <= 1}
                class="px-2 py-1 text-[10px] font-black text-gray-400 hover:text-gray-100 border border-gray-700 hover:border-gray-500 rounded disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              >
                ← Prev
              </button>

              <For each={pageNumbers()}>
                {(p, i) => {
                  const prev = pageNumbers()[i() - 1]
                  const showEllipsis = prev != null && p - prev > 1
                  return (
                    <>
                      <Show when={showEllipsis}>
                        <span class="text-[10px] text-gray-700 px-1">…</span>
                      </Show>
                      <button
                        onClick={() => goToPage(p)}
                        class={`w-7 h-7 text-[10px] font-black rounded transition-colors ${p === meta().page ? 'bg-cyan-700 text-white' : 'text-gray-400 hover:text-gray-100 border border-gray-700 hover:border-gray-500'}`}
                      >
                        {p}
                      </button>
                    </>
                  )
                }}
              </For>

              <button
                onClick={() => goToPage(meta().page + 1)}
                disabled={meta().page >= meta().pages}
                class="px-2 py-1 text-[10px] font-black text-gray-400 hover:text-gray-100 border border-gray-700 hover:border-gray-500 rounded disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              >
                Next →
              </button>
            </div>
          </div>
        </Show>
      </div>
    </div>
  )
}
