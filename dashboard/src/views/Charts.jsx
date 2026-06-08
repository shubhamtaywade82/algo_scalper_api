import { createSignal, createMemo, createResource, For, Show, onMount, onCleanup } from 'solid-js'
import { A } from '@solidjs/router'
import { dashboardApiHeaders } from '../lib/dashboardApi'
import { useDashboard } from '../stores/useDashboard'
import { usePositions } from '../stores/usePositions'
import PriceChart from '../components/charts/PriceChart'

const INDICES = ['NIFTY', 'BANKNIFTY', 'SENSEX']
const LTP_KEY = { NIFTY: 'nifty', BANKNIFTY: 'banknifty', SENSEX: 'sensex' }
const INTERVALS = [
  { value: '1', label: '1m' },
  { value: '5', label: '5m' },
  { value: '15', label: '15m' },
  { value: '25', label: '25m' },
  { value: '60', label: '1h' }
]

// Default indicator catalog — each entry is a self-contained config the
// PriceChart consumes directly. Add a new overlay by appending here AND
// registering its compute fn in PriceChart's INDICATOR_COMPUTE map.
const DEFAULT_INDICATORS = [
  { id: 'sma20', type: 'sma', label: 'SMA', period: 20, color: '#fbbf24', enabled: true },
  { id: 'sma50', type: 'sma', label: 'SMA', period: 50, color: '#a78bfa', enabled: true },
  { id: 'ema21', type: 'ema', label: 'EMA', period: 21, color: '#38bdf8', enabled: false }
]

async function fetchCandles({ indexKey, interval }) {
  const res = await fetch(`/api/candles/${indexKey}?interval=${interval}&days=5`, {
    headers: dashboardApiHeaders()
  })
  if (!res.ok) throw new Error(`candles fetch failed: ${res.status}`)
  const data = await res.json()
  return data.candles || []
}

/**
 * Fullscreen charting workspace — own layout, deliberately outside AppShell
 * (no Header/footer chrome, no DashboardContext dependency). Lives at /charts.
 */
export default function Charts() {
  const [indexKey, setIndexKey] = createSignal('NIFTY')
  const [interval, setInterval_] = createSignal('5')
  const [indicators, setIndicators] = createSignal(DEFAULT_INDICATORS)
  const [showIndicatorPanel, setShowIndicatorPanel] = createSignal(false)

  function toggleIndicator(id) {
    setIndicators(list => list.map(i => (i.id === id ? { ...i, enabled: !i.enabled } : i)))
  }
  function setIndicatorPeriod(id, period) {
    const n = Number(period)
    if (!Number.isFinite(n) || n < 1) return
    setIndicators(list => list.map(i => (i.id === id ? { ...i, period: Math.round(n) } : i)))
  }

  const [candles, { refetch }] = createResource(
    () => ({ indexKey: indexKey(), interval: interval() }),
    fetchCandles
  )

  // Backbone refresh — picks up newly-closed bars / late prints. The actual
  // real-time motion comes from the WS LTP stream below, not this poll.
  let pollId
  onMount(() => {
    pollId = setInterval(() => refetch(), 15000)
  })
  onCleanup(() => clearInterval(pollId))

  // Live LTP via ActionCable (DashboardChannel) — same feed Header/Terminal use.
  // Drives the forming candle's close + price line every tick for true real-time motion.
  const { indices } = useDashboard()
  const liveLtp = createMemo(() => {
    const key = LTP_KEY[indexKey()]
    const val = indices()?.[key]
    return val == null ? null : Number(val)
  })

  // Active positions whose underlying matches the chart's selected index —
  // overlaid on PriceChart as entry-price lines + entry-time arrow markers.
  const { open: openPositions } = usePositions()
  const chartPositions = createMemo(() =>
    (openPositions() || []).filter(p => (p.index_key || '').toUpperCase() === indexKey())
  )

  return (
    <div class="h-screen w-screen flex flex-col bg-gray-950 text-gray-100 overflow-hidden">
      <header class="flex items-center justify-between gap-4 px-5 py-3 border-b border-white/5 shrink-0">
        <div class="flex items-center gap-4">
          <A
            href="/"
            class="text-[11px] font-bold uppercase tracking-[0.2em] text-gray-500 hover:text-gray-300 transition-colors"
          >
            ← Terminal
          </A>
          <h1 class="text-lg font-black tracking-tight text-white">Charts</h1>
        </div>

        <div class="flex items-center gap-3">
          <div class="flex rounded-xl overflow-hidden border border-white/10">
            <For each={INDICES}>
              {idx => (
                <button
                  class={`px-4 py-2 text-xs font-bold uppercase tracking-wider transition-colors ${
                    indexKey() === idx ? 'bg-primary-500/20 text-primary-300' : 'text-gray-400 hover:text-gray-200'
                  }`}
                  onClick={() => setIndexKey(idx)}
                >
                  {idx}
                </button>
              )}
            </For>
          </div>

          <div class="flex rounded-xl overflow-hidden border border-white/10">
            <For each={INTERVALS}>
              {opt => (
                <button
                  class={`px-3 py-2 text-xs font-bold uppercase tracking-wider transition-colors ${
                    interval() === opt.value ? 'bg-primary-500/20 text-primary-300' : 'text-gray-400 hover:text-gray-200'
                  }`}
                  onClick={() => setInterval_(opt.value)}
                >
                  {opt.label}
                </button>
              )}
            </For>
          </div>

          <button
            class={`px-4 py-2 rounded-xl border text-xs font-bold uppercase tracking-wider transition-colors ${
              showIndicatorPanel() ? 'bg-primary-500/20 border-primary-500/30 text-primary-300' : 'border-white/10 text-gray-400 hover:text-gray-200'
            }`}
            onClick={() => setShowIndicatorPanel(v => !v)}
          >
            Indicators
          </button>
        </div>
      </header>

      <Show when={showIndicatorPanel()}>
        <div class="flex flex-wrap items-center gap-4 px-5 py-3 border-b border-white/5 bg-gray-900/40 shrink-0">
          <For each={indicators()}>
            {ind => (
              <div class={`flex items-center gap-2 px-3 py-1.5 rounded-lg border transition-colors ${ind.enabled ? 'border-white/10 bg-white/[0.03]' : 'border-white/5 opacity-50'}`}>
                <button
                  class="flex items-center gap-1.5"
                  onClick={() => toggleIndicator(ind.id)}
                  title={ind.enabled ? 'Disable' : 'Enable'}
                >
                  <span class="w-2.5 h-2.5 rounded-full" style={{ background: ind.color }} />
                  <span class="text-xs font-bold text-gray-300">{ind.label}</span>
                </button>
                <input
                  type="number"
                  min="1"
                  value={ind.period}
                  class="w-14 bg-transparent border border-white/10 rounded px-1.5 py-0.5 text-xs text-gray-200 text-center"
                  onInput={e => setIndicatorPeriod(ind.id, e.currentTarget.value)}
                />
              </div>
            )}
          </For>
        </div>
      </Show>

      <div class="flex-1 min-h-0 p-4">
        <Show when={candles.loading}>
          <div class="h-full flex items-center justify-center text-sm text-gray-500">Loading candles…</div>
        </Show>
        <Show when={candles.error}>
          <div class="h-full flex items-center justify-center text-sm text-rose-400">
            Failed to load candles: {candles.error?.message}
          </div>
        </Show>
        <Show when={!candles.loading && !candles.error}>
          <div class="h-full rounded-2xl border border-white/5 bg-gray-900/40 overflow-hidden">
            <PriceChart
              candles={() => candles() || []}
              liveLtp={liveLtp}
              indicators={indicators}
              positions={chartPositions}
              height={null}
              fullHeight
            />
          </div>
        </Show>
      </div>
    </div>
  )
}
