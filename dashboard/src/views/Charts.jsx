import { createSignal, createMemo, createResource, For, Show, onMount, onCleanup } from 'solid-js'
import { A } from '@solidjs/router'
import { dashboardApiHeaders } from '../lib/dashboardApi'
import { useDashboard } from '../stores/useDashboard'
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
        </div>
      </header>

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
            <PriceChart candles={() => candles() || []} liveLtp={liveLtp} height={null} fullHeight />
          </div>
        </Show>
      </div>
    </div>
  )
}
