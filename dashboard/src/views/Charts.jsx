import { createSignal, createMemo, createResource, createEffect, For, Show, onMount, onCleanup } from 'solid-js'
import { A, useSearchParams } from '@solidjs/router'
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
// PriceChart consumes directly. Overlay entries (smc_*/ict_*/pa_*/setup_scan)
// gate the local SMC/ICT/PA canvas detectors ported from the dhanhq-charts
// engine; sma/ema are LineSeries overlays.
const DEFAULT_INDICATORS = [
  { id: 'sma20', type: 'sma', label: 'SMA', period: 20, color: '#fbbf24', enabled: true },
  { id: 'sma50', type: 'sma', label: 'SMA', period: 50, color: '#a78bfa', enabled: true },
  { id: 'ema21', type: 'ema', label: 'EMA', period: 21, color: '#38bdf8', enabled: false },
  { id: 'smc_ob', type: 'smc_ob', label: 'SMC Order Blocks', color: '#10b981', enabled: true },
  { id: 'smc_fvg', type: 'smc_fvg', label: 'SMC Fair Value Gaps', color: '#2dd4bf', enabled: false },
  { id: 'smc_eq', type: 'smc_eq', label: 'SMC Equilibrium & Zones', color: '#eab308', enabled: false },
  { id: 'smc_swing', type: 'smc_swing', label: 'SMC Swing Structure (BOS)', color: '#a855f7', enabled: false },
  { id: 'smc_liquidity', type: 'smc_liquidity', label: 'SMC Liquidity Pools', color: '#22d3ee', enabled: false },
  { id: 'ict_sessions', type: 'ict_sessions', label: 'ICT Kill Zones', color: '#9333ea', enabled: false },
  { id: 'ict_sb', type: 'ict_sb', label: 'Silver Bullet Windows', color: '#fbbf24', enabled: false },
  { id: 'ict_ote', type: 'ict_ote', label: 'OTE Zone', color: '#22d3ee', enabled: false },
  { id: 'ict_judas', type: 'ict_judas', label: 'Judas Swings', color: '#fb7185', enabled: false },
  { id: 'ict_amd', type: 'ict_amd', label: 'AMD Power of 3', color: '#fb923c', enabled: false },
  { id: 'pa_sd', type: 'pa_sd', label: 'Supply & Demand Zones', color: '#34d399', enabled: false },
  { id: 'pa_tl', type: 'pa_tl', label: 'Trendline Liquidity', color: '#34d399', enabled: false },
  { id: 'pa_cp', type: 'pa_cp', label: 'Candle Patterns', color: '#fbbf24', enabled: false },
  { id: 'setup_scan', type: 'setup_scan', label: 'Setup Scanner (CE/PE)', color: '#a3e635', enabled: false }
]

const THEMES = [
  { id: 'modern', label: 'Modern', config: { upColor: '#34d399', downColor: '#fb7185', borderVisible: false, wickUpColor: '#34d399', wickDownColor: '#fb7185' } },
  { id: 'hollow', label: 'Hollow', config: { upColor: 'transparent', downColor: '#fb7185', borderVisible: true, borderColor: '#34d399', borderUpColor: '#34d399', borderDownColor: '#fb7185', wickUpColor: '#34d399', wickDownColor: '#fb7185' } },
  { id: 'monochrome', label: 'Mono', config: { upColor: '#ffffff', downColor: '#52525b', borderVisible: false, wickUpColor: '#ffffff', wickDownColor: '#52525b' } },
  { id: 'cyberpunk', label: 'Cyber', config: { upColor: '#0ea5e9', downColor: '#ec4899', borderVisible: false, wickUpColor: '#0ea5e9', wickDownColor: '#ec4899' } }
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
  const [searchParams, setSearchParams] = useSearchParams()
  const initialSymbol = (searchParams.symbol || localStorage.getItem('chart_symbol') || 'NIFTY').toUpperCase()
  const [indexKey, setIndexKey] = createSignal(initialSymbol)
  
  const { optionsBuying } = useDashboard()

  const buyingState = createMemo(() => optionsBuying() ? optionsBuying()[indexKey().toLowerCase()] : null)
  
  const savedInterval = localStorage.getItem('chart_interval') || '5'
  const [interval, setInterval_] = createSignal(savedInterval)
  
  const savedThemeId = localStorage.getItem('chart_theme') || 'modern'
  const savedTheme = THEMES.find(t => t.id === savedThemeId) || THEMES[0]
  const [theme, setTheme] = createSignal(savedTheme)
  
  const savedIndicators = JSON.parse(localStorage.getItem('chart_indicators') || 'null') || DEFAULT_INDICATORS
  const [indicators, setIndicators] = createSignal(savedIndicators)
  
  const [showIndicatorPanel, setShowIndicatorPanel] = createSignal(false)

  createEffect(() => {
    localStorage.setItem('chart_symbol', indexKey())
    localStorage.setItem('chart_interval', interval())
    localStorage.setItem('chart_theme', theme().id)
    localStorage.setItem('chart_indicators', JSON.stringify(indicators()))
  })

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

  // Backbone refresh — picks up newly-closed bars. The actual real-time motion
  // comes from the WS LTP stream below. To prevent spamming the API and hitting
  // rate limits, we align the fetch exactly to the top of the minute (+2s buffer
  // to allow the broker to finalize the candle), and we ONLY fetch if the current
  // minute matches the boundary for the selected timeframe.
  let pollId

  function isCandleBoundary(intervalStr, date) {
    const ival = parseInt(intervalStr, 10) || 5
    if (ival === 1) return true
    if (ival === 5) return date.getMinutes() % 5 === 0
    if (ival === 15) return date.getMinutes() % 15 === 0
    if (ival === 60) return date.getMinutes() === 15 // Hourly candles close at xx:15 in India

    // Convert current time to IST to accurately calculate 25m boundaries from 09:15
    const utcMs = date.getTime() + (date.getTimezoneOffset() * 60000)
    const istDate = new Date(utcMs + (330 * 60000))
    const minsSinceOpen = (istDate.getHours() * 60 + istDate.getMinutes()) - (9 * 60 + 15)
    
    if (minsSinceOpen < 0) return true
    return minsSinceOpen % ival === 0
  }

  function scheduleNextMinuteFetch() {
    const now = new Date()
    const msUntilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds())
    
    pollId = setTimeout(() => {
      if (isCandleBoundary(interval(), new Date())) {
        refetch()
      }
      scheduleNextMinuteFetch()
    }, msUntilNextMinute + 2000)
  }

  onMount(() => {
    scheduleNextMinuteFetch()
  })
  onCleanup(() => clearTimeout(pollId))

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

          <div class="flex rounded-xl overflow-hidden border border-white/10 hidden md:flex">
            <For each={THEMES}>
              {opt => (
                <button
                  class={`px-3 py-2 text-xs font-bold uppercase tracking-wider transition-colors ${
                    theme().id === opt.id ? 'bg-indigo-500/20 text-indigo-300' : 'text-gray-400 hover:text-gray-200'
                  }`}
                  onClick={() => setTheme(opt)}
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
                <Show when={ind.period != null}>
                  <input
                    type="number"
                    min="1"
                    value={ind.period}
                    class="w-14 bg-transparent border border-white/10 rounded px-1.5 py-0.5 text-xs text-gray-200 text-center"
                    onInput={e => setIndicatorPeriod(ind.id, e.currentTarget.value)}
                  />
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>

      <div class="flex-1 min-h-0 p-4 relative">
        <Show when={candles.loading && !candles()}>
          <div class="h-full flex items-center justify-center text-sm text-gray-500">Loading candles…</div>
        </Show>
        <Show when={candles.error}>
          <div class="h-full flex items-center justify-center text-sm text-rose-400">
            Failed to load candles: {candles.error?.message}
          </div>
        </Show>
        <Show when={(candles() && candles().length > 0) || (!candles.loading && !candles.error)}>
          <div class="h-full rounded-2xl border border-white/5 bg-gray-900/40 overflow-hidden relative group">
            
            {/* Options Buying HUD Overlay */}
            <Show when={buyingState()}>
              <div class="absolute top-4 left-4 z-10 p-4 rounded-xl bg-gray-900/80 backdrop-blur-md border border-white/10 shadow-2xl pointer-events-none opacity-50 group-hover:opacity-100 transition-opacity">
                <div class="flex items-center gap-2 mb-3">
                  <div class="w-2 h-2 rounded-full bg-indigo-400 animate-pulse" />
                  <span class="text-xs font-bold text-gray-300 uppercase tracking-widest">Options Buyer Core</span>
                </div>
                
                <div class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
                  <div class="text-gray-500">Regime</div>
                  <div class={`font-mono font-bold text-right ${
                    buyingState().regime?.includes('BULL') ? 'text-emerald-400' :
                    buyingState().regime?.includes('BEAR') ? 'text-rose-400' : 'text-amber-400'
                  }`}>{buyingState().regime || 'UNKNOWN'}</div>

                  <div class="text-gray-500">Breakout State</div>
                  <div class={`font-mono font-bold text-right ${buyingState().breakout_ready ? 'text-emerald-400' : 'text-gray-400'}`}>
                    {buyingState().breakout_ready ? `[ARMED: ${buyingState().direction}]` : '[RANGING]'}
                  </div>

                  <div class="text-gray-500">ATR Compressed</div>
                  <div class={`font-mono font-bold text-right ${buyingState().compression_armed ? 'text-emerald-400' : 'text-gray-400'}`}>
                    {buyingState().compression_armed ? 'YES' : 'NO'}
                  </div>

                  <div class="text-gray-500">Daily ATR</div>
                  <div class="font-mono text-gray-300 text-right">{buyingState().daily_atr ? buyingState().daily_atr.toFixed(2) : '--'}</div>

                  <Show when={buyingState().support && buyingState().resistance}>
                    <div class="text-gray-500">Key Levels</div>
                    <div class="font-mono text-gray-300 text-right">
                      S: <span class="text-emerald-400">{buyingState().support?.toFixed(0)}</span> / R: <span class="text-rose-400">{buyingState().resistance?.toFixed(0)}</span>
                    </div>
                  </Show>

                  <Show when={buyingState().radar_strikes?.length > 0}>
                    <div class="text-gray-500">Radar Strikes</div>
                    <div class="font-mono text-indigo-300 text-right font-bold">
                      {buyingState().radar_strikes.map(s => typeof s === 'object' && s ? `${s.strike} ${s.type}` : s).join(', ')}
                    </div>
                  </Show>
                </div>
              </div>
            </Show>

            <PriceChart
              symbol={indexKey()}
              candles={() => candles() || []}
              liveLtp={liveLtp}
              indicators={indicators}
              positions={chartPositions}
              theme={theme().config}
              interval={interval()}
              support={() => buyingState()?.support}
              resistance={() => buyingState()?.resistance}
              radarStrikes={() => buyingState()?.radar_strikes || []}
              breakoutReady={() => buyingState()?.breakout_ready}
              direction={() => buyingState()?.direction}
              height={null}
              fullHeight
            />
          </div>
        </Show>
      </div>
    </div>
  )
}
