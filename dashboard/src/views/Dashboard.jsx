import { createSignal, createMemo, createEffect, For, Show, onMount } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import StatsBar from '../components/StatsBar'
import AnimatedNumber from '../components/AnimatedNumber'
import { useAlerts } from '../stores/useAlerts'
import { useOrders } from '../stores/useOrders'
import EquityCurve from '../components/charts/EquityCurve'
import { useEquityCurve } from '../stores/useEquityCurve'

const RUNNING_PEAK_KEY = 'algo_dashboard_daily_pnl_hwm'

function calendarDayKey() {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function loadRunningPeak() {
  try {
    const raw = sessionStorage.getItem(RUNNING_PEAK_KEY)
    if (!raw) return 0
    const { date, value } = JSON.parse(raw)
    if (date !== calendarDayKey()) return 0
    return Number(value) || 0
  } catch {
    return 0
  }
}

function saveRunningPeak(n) {
  try {
    sessionStorage.setItem(RUNNING_PEAK_KEY, JSON.stringify({ date: calendarDayKey(), value: n }))
  } catch { /* ignore */ }
}

export default function Dashboard() {
  const {
    balance, stats, open, circuitBreaker, positionsConnected, positionsStale,
    closeOpenPosition, closingPositionId, marketStatus, mode, indices, recentSignals, system
  } = useDashboardContext()

  const [runningPeakPnl, setRunningPeakPnl] = createSignal(loadRunningPeak())
  const { alerts: liveAlerts } = useAlerts()
  const { orders: recentOrders, fetchOrders } = useOrders()
  const { data: equityCurveData, fetchCurve: fetchEquityCurve } = useEquityCurve()

  onMount(() => {
    fetchOrders()
    fetchEquityCurve()
  })

  createEffect(() => {
    const currentOpen = open() || []
    const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
    const realized = Number(stats()?.realized_pnl_rupees || 0)
    const total = realized + unrealized
    const serverPeak = Number(stats()?.peak_pnl || 0)
    const next = Math.max(loadRunningPeak(), runningPeakPnl(), total, serverPeak)
    if (next !== runningPeakPnl()) {
      setRunningPeakPnl(next)
      saveRunningPeak(next)
    }
  })

  const liveStats = createMemo(() => {
    const currentOpen = open() || []
    const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
    const realized = Number(stats()?.realized_pnl_rupees || 0)
    const total = realized + unrealized
    return {
      ...stats(),
      active_positions: currentOpen.length,
      unrealized_pnl_rupees: unrealized,
      total_pnl_rupees: total,
      peak_pnl: runningPeakPnl()
    }
  })

  const netPnl = () => liveStats().total_pnl_rupees || 0
  const totalTrades = () => stats()?.total_trades || 0
  const winners = () => stats()?.winners || 0
  const winRate = () => totalTrades() > 0 ? (winners() / totalTrades() * 100) : 0
  const losers = () => totalTrades() - winners()

  // Format Helper
  const inrFormat = (val) => {
    return (Number(val) || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })
  }

  const activeStrategies = () => {
    const sys = system()
    const list = []
    if (sys?.scheduler && sys.scheduler !== 'unknown') {
      list.push({ name: 'Scheduler', status: sys.scheduler === 'running' ? 'Running' : 'Stopped', pnl: null })
    }
    return list
  }

  const signalsFeed = createMemo(() => {
    return (recentSignals() || []).slice(0, 5)
  })

  const alertSeverityColor = (severity) => {
    if (severity === 'error') return 'text-rose-400 bg-rose-400'
    if (severity === 'warning') return 'text-amber-400 bg-amber-400'
    return 'text-sky-400 bg-sky-400'
  }

  const systemHealth = createMemo(() => {
    const sys = system() || {}
    return [
      { name: 'WebSocket Feed', status: sys.ws_market_feed ? 'Live' : 'Inactive', class: sys.ws_market_feed ? 'text-emerald-400' : 'text-rose-400' },
      { name: 'Order Updates', status: sys.ws_order_update ? 'Connected' : 'Inactive', class: sys.ws_order_update ? 'text-emerald-400' : 'text-gray-500' },
      { name: 'Risk Engine', status: sys.pnl_updater_running ? 'Operational' : 'Inactive', class: sys.pnl_updater_running ? 'text-emerald-400' : 'text-gray-500' },
      { name: 'Scheduler', status: sys.scheduler === 'running' ? 'Running' : 'Stopped', class: sys.scheduler === 'running' ? 'text-emerald-400' : 'text-gray-500' }
    ]
  })

  const openPositionsList = createMemo(() => {
    return open() || []
  })

  // Total Open Position P&L
  const totalOpenPnl = createMemo(() => {
    return openPositionsList().reduce((sum, p) => sum + Number(p.pnl || 0), 0)
  })

  // recentOrders now from useOrders() store

  return (
    <div class="space-y-6">

      {/* 2. Top StatsBar KPI Cards Row */}
      <StatsBar
        balance={balance()}
        stats={liveStats()}
        marketStatus={marketStatus()}
        mode={mode()}
        strategies={{
          running: activeStrategies().filter((s) => s.status === 'Running').length,
          total: activeStrategies().length
        }}
      />

      {/* 3. Middle Charts & Market Overview Row */}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Equity Curve Card */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[300px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Equity Curve (Today)</span>
            <span class="text-[9px] font-bold text-gray-500 bg-white/5 px-2 py-0.5 rounded-full uppercase">Today</span>
          </div>
          <div class="flex-1 flex items-center justify-between gap-6 py-4">
            <div class="flex-1 h-full relative flex items-center justify-center">
              <Show when={equityCurveData().length > 0} fallback={
                <span class="text-[9px] text-gray-500 animate-pulse uppercase tracking-widest font-black">Loading Equity Curve...</span>
              }>
                <EquityCurve data={equityCurveData} height={180} />
              </Show>
            </div>
            {/* Legend / Metrics side list */}
            <div class="w-28 space-y-2 border-l border-white/5 pl-4 shrink-0 flex flex-col justify-center">
              <div>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Net P&L</span>
                <div class="text-xs font-black text-data mt-0.5">
                  <AnimatedNumber value={netPnl()} currency decimals={0} showSign pnlColor />
                </div>
              </div>
              <div>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Win Rate</span>
                <div class="text-xs font-black text-white text-data mt-0.5">{winRate()}%</div>
              </div>
              <div>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Total Trades</span>
                <div class="text-xs font-black text-white text-data mt-0.5">{totalTrades()}</div>
              </div>
              <Show when={liveStats()?.peak_pnl}>
                <div>
                  <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Peak P&L</span>
                  <div class="text-xs font-black text-emerald-400 text-data mt-0.5">&plus;₹{inrFormat(liveStats().peak_pnl)}</div>
                </div>
              </Show>
            </div>
          </div>
        </div>

        {/* P&L Distribution Card */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[300px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">PnL Distribution</span>
          </div>
          <div class="flex-1 flex items-center justify-center gap-6 py-4">
            {/* SVG Donut Chart */}
            <div class="relative w-28 h-28 shrink-0">
              <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.03)" stroke-width="3" />
                <Show when={totalTrades() > 0}>
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5"
                    stroke-dasharray={`${winRate()} ${100 - winRate()}`} stroke-dashoffset="0" />
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5"
                    stroke-dasharray={`${100 - winRate()} ${winRate()}`} stroke-dashoffset={`-${winRate()}`} />
                </Show>
              </svg>
              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <span class="text-lg font-black text-white text-data">{totalTrades()}</span>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Total</span>
              </div>
            </div>
            <div class="flex-1 space-y-2 text-[10px] font-bold">
              <div class="flex items-center justify-between">
                <span class="text-gray-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-emerald-500" /> Win</span>
                <span class="text-white text-data">{winners()} ({winRate().toFixed(1)}%)</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-gray-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-rose-500" /> Loss</span>
                <span class="text-white text-data">{losers()} ({losers() > 0 && totalTrades() > 0 ? ((losers() / totalTrades()) * 100).toFixed(1) : 0}%)</span>
              </div>
            </div>
          </div>
        </div>

        {/* Market Overview Card */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[300px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-2">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Market Overview</span>
          </div>
          <div class="flex-1 divide-y divide-white/5 overflow-y-auto text-[10px]">
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">Nifty 50</span>
                <span class="text-gray-400 text-data mt-0.5">
                  <AnimatedNumber value={indices()?.nifty || 0} decimals={2} />
                </span>
              </div>
            </div>
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">Bank Nifty</span>
                <span class="text-gray-400 text-data mt-0.5">
                  <AnimatedNumber value={indices()?.banknifty || 0} decimals={2} />
                </span>
              </div>
            </div>
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">Sensex</span>
                <span class="text-gray-400 text-data mt-0.5">
                  <AnimatedNumber value={indices()?.sensex || 0} decimals={2} />
                </span>
              </div>
            </div>
            <div class="py-2.5 text-[9px] uppercase tracking-wider text-gray-500 font-black">
              Market: <span class={`${marketStatus()?.market_open ? 'text-emerald-400' : 'text-rose-400'}`}>{marketStatus()?.market_open ? 'Open' : 'Closed'}</span>
            </div>
          </div>
        </div>
      </div>

      {/* 4. Lower Active Strategies, Open Positions & Recent Orders Row */}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Active Strategies Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Active Strategies</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-x-auto mt-2">
            <Show when={activeStrategies().length > 0} fallback={
              <div class="text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No active strategies</div>
            }>
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2">Strategy</th>
                    <th class="py-2">Status</th>
                    <th class="py-2 text-right">PnL</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={activeStrategies()}>
                    {(s) => (
                      <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                        <td class="py-2.5 font-bold text-white">{s.name}</td>
                        <td class="py-2.5">
                          <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                            s.status === 'Running' ? 'text-emerald-400 bg-emerald-500/10' : 'text-gray-500 bg-white/5'
                          }`}>{s.status}</span>
                        </td>
                        <td class="py-2.5 text-right font-black text-data text-gray-500">&mdash;</td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </Show>
          </div>
        </div>

        {/* Open Positions Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Open Positions</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-x-auto mt-2">
            <Show when={openPositionsList().length > 0} fallback={
              <div class="text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No open positions</div>
            }>
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2">Instrument</th>
                    <th class="py-2 text-right">Qty</th>
                    <th class="py-2 text-right">LTP</th>
                    <th class="py-2 text-right">P&L</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={openPositionsList()}>
                    {(p) => (
                      <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                        <td class="py-2.5 font-bold text-white max-w-[120px] truncate" title={p.symbol}>{p.symbol}</td>
                        <td class="py-2.5 text-right text-data text-gray-400">
                          <AnimatedNumber value={p.qty} decimals={0} />
                        </td>
                        <td class="py-2.5 text-right text-data text-white">
                          <AnimatedNumber value={p.ltp} decimals={2} />
                        </td>
                        <td class="py-2.5 text-right font-black text-data">
                          <AnimatedNumber value={p.pnl} currency decimals={0} showSign pnlColor />
                        </td>
                      </tr>
                    )}
                  </For>
                  <tr class="font-black text-white">
                    <td class="py-3 uppercase tracking-wider text-gray-500">Total</td>
                    <td colspan="2"></td>
                    <td class="py-3 text-right text-data">
                      <AnimatedNumber value={totalOpenPnl()} currency decimals={0} showSign pnlColor />
                    </td>
                  </tr>
                </tbody>
              </table>
            </Show>
          </div>
        </div>

        {/* Recent Orders Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Recent Orders</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-x-auto mt-2">
            <Show when={recentOrders().length > 0} fallback={
              <div class="text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No recent orders</div>
            }>
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2">Symbol</th>
                    <th class="py-2 text-center">Side</th>
                    <th class="py-2 text-right">Qty</th>
                    <th class="py-2 text-right">Status</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={recentOrders()}>
                    {(o) => (
                      <tr class="border-b border-white/5">
                        <td class="py-2 font-bold text-white truncate max-w-[100px]">{o.symbol}</td>
                        <td class="py-2 text-center">
                          <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                            o.side === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                          }`}>{o.side}</span>
                        </td>
                        <td class="py-2 text-right text-gray-400">{o.quantity}</td>
                        <td class="py-2 text-right">
                          <span class={`text-[8px] font-black uppercase ${
                            o.status === 'exited' ? 'text-gray-500' : o.status === 'active' ? 'text-emerald-400' : 'text-amber-400'
                          }`}>{o.status}</span>
                        </td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </Show>
          </div>
        </div>
      </div>

      {/* 5. Bottom Strategy Signals, Alerts & System Health Row */}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Strategy Signals (Live) Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Strategy Signals (Live)</span>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[220px] mt-2 divide-y divide-white/5">
            <Show when={signalsFeed().length > 0} fallback={
              <div class="py-6 text-center text-[10px] text-gray-600 font-bold uppercase tracking-wider">No recent signals</div>
            }>
              <For each={signalsFeed()}>
                {(s) => (
                  <div class="py-2 flex items-center justify-between text-[10px]">
                    <div class="flex items-center gap-3">
                      <span class="text-gray-500 font-mono">{s.timestamp}</span>
                      <span class="font-bold text-white">{s.strategy}</span>
                    </div>
                    <div class="flex items-center gap-3">
                      <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                        s.signal?.includes('BUY') ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-gray-500/10 text-gray-400 border border-gray-500/20'
                      }`}>{s.signal}</span>
                      <span class="text-gray-400 uppercase tracking-wider">{s.symbol}</span>
                    </div>
                  </div>
                )}
              </For>
            </Show>
          </div>
        </div>

        {/* Alerts Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Alerts</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[220px] mt-2 divide-y divide-white/5">
            <Show when={liveAlerts().length > 0} fallback={
              <div class="py-6 text-center text-[10px] text-gray-600 font-bold uppercase tracking-wider">No alerts</div>
            }>
              <For each={liveAlerts()}>
                {(a) => (
                  <div class="py-2.5 flex items-start gap-3 text-[10px]">
                    <span class="text-gray-500 font-mono mt-0.5">{new Date(a.created_at).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })}</span>
                    <div class="flex-1">
                      <p class="text-white font-bold leading-snug">{a.message}</p>
                      <span class={`text-[8px] font-black uppercase mt-1 inline-block ${alertSeverityColor(a.severity).split(' ')[0]}`}>{a.type}</span>
                    </div>
                  </div>
                )}
              </For>
            </Show>
          </div>
        </div>

        {/* System Health Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">System Health</span>
            <span class="text-[8px] font-black uppercase text-emerald-400 flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-emerald-400" /></span>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[220px] mt-2 divide-y divide-white/5">
            <For each={systemHealth()}>
              {(h) => (
                <div class="py-2.5 flex items-center justify-between text-[10px]">
                  <span class="font-bold text-gray-400">{h.name}</span>
                  <div class="flex items-center gap-3">
                    <span class={`font-black uppercase text-[9px] ${h.class}`}>{h.status}</span>
                    <span class="text-gray-500 font-mono text-[9px]">{h.val}</span>
                  </div>
                </div>
              )}
            </For>
          </div>
        </div>
      </div>
    </div>
  )
}
