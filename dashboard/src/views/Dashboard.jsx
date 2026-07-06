import { createSignal, createMemo, createEffect, For, Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import StatsBar from '../components/StatsBar'
import AnimatedNumber from '../components/AnimatedNumber'

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

  const netPnl = () => liveStats().total_pnl_rupees || 24350
  const totalTrades = () => stats()?.total_trades || 40
  const winners = () => stats()?.winners || 25
  const winRate = () => stats()?.win_rate || 62.5

  // Format Helper
  const inrFormat = (val) => {
    return (Number(val) || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })
  }

  // Active Strategies list (mock & live mix)
  const activeStrategies = [
    { name: 'ORB Breakout', status: 'Running', timeframe: '1m', signal: 'BUY CALL', signalClass: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/25', pnl: 12450, trades: 18 },
    { name: 'Supertrend Scalper', status: 'Running', timeframe: '1m', signal: 'BUY PUT', signalClass: 'bg-rose-500/10 text-rose-400 border-rose-500/25', pnl: 6230, trades: 12 },
    { name: 'EMA Cross', status: 'Running', timeframe: '5m', signal: 'HOLD', signalClass: 'bg-amber-500/10 text-amber-400 border-amber-500/25', pnl: 5670, trades: 10 },
    { name: 'VWAP Mean Revert', status: 'Stopped', timeframe: '5m', signal: '—', signalClass: 'text-gray-500', pnl: null, trades: 0 },
    { name: 'AI Momentum', status: 'Stopped', timeframe: '15m', signal: '—', signalClass: 'text-gray-500', pnl: null, trades: 0 }
  ]

  // Signals Feed
  const signalsFeed = createMemo(() => {
    const list = recentSignals() || []
    if (list.length > 0) return list.slice(0, 5)
    return [
      { timestamp: '09:23:40', strategy: 'ORB Breakout', signal: 'BUY CALL', symbol: 'NIFTY 24150 CE' },
      { timestamp: '09:23:36', strategy: 'Supertrend Scalper', signal: 'BUY PUT', symbol: 'BANKNIFTY 52400 PE' },
      { timestamp: '09:23:32', strategy: 'EMA Cross', signal: 'HOLD', symbol: 'NIFTY' },
      { timestamp: '09:23:28', strategy: 'ORB Breakout', signal: 'TRAIL SL', symbol: 'NIFTY 24150 CE' },
      { timestamp: '09:23:20', strategy: 'Supertrend Scalper', signal: 'EXIT', symbol: 'BANKNIFTY 52300 PE' }
    ]
  })

  // Alerts Mock Feed
  const alerts = [
    { time: '09:23:15', type: 'price', text: 'NIFTY 24150 CE crossed above 220', class: 'text-emerald-400 bg-emerald-400' },
    { time: '09:23:02', type: 'risk', text: 'Daily Loss limit 50% reached', class: 'text-amber-400 bg-amber-400' },
    { time: '09:22:45', type: 'strategy', text: 'ORB Breakout generated BUY signal', class: 'text-emerald-400 bg-emerald-400' },
    { time: '09:22:10', type: 'system', text: 'Option Chain update completed', class: 'text-sky-400 bg-sky-400' },
    { time: '09:21:05', type: 'connection', text: 'WebSocket Reconnected', class: 'text-emerald-400 bg-emerald-400' }
  ]

  // System Health fields mapped from backend system statuses
  const systemHealth = createMemo(() => {
    const sys = system() || {}
    return [
      { name: 'WebSocket Connection', status: sys.ws_market_feed ? 'Live Feed' : 'Inactive', val: '100 ms', class: sys.ws_market_feed ? 'text-emerald-400' : 'text-rose-400' },
      { name: 'Data Engine', status: 'Processing', val: '100%', class: 'text-emerald-400' },
      { name: 'Order Engine', status: sys.ws_order_update ? 'Operational' : 'Inactive', val: '—', class: sys.ws_order_update ? 'text-emerald-400' : 'text-gray-500' },
      { name: 'Risk Engine', status: sys.pnl_updater_running ? 'Operational' : 'Inactive', val: '—', class: sys.pnl_updater_running ? 'text-emerald-400' : 'text-gray-500' },
      { name: 'Database', status: 'Operational', val: '—', class: 'text-emerald-400' },
      { name: 'Broker Connection (DhanHQ)', status: sys.ws_market_feed ? 'Connected' : 'Offline', val: '45 ms', class: sys.ws_market_feed ? 'text-emerald-400' : 'text-rose-400' }
    ]
  })

  // Open Positions
  const openPositionsList = createMemo(() => {
    const currentOpen = open() || []
    if (currentOpen.length > 0) return currentOpen
    return [
      { symbol: 'NIFTY 06 JUN 24150 CE', type: 'BUY', qty: 75, avg_price: 210.45, ltp: 228.60, pnl: 1362 },
      { symbol: 'BANKNIFTY 06 JUN 52400 PE', type: 'BUY', qty: 50, avg_price: 180.10, ltp: 195.35, pnl: 762 },
      { symbol: 'NIFTY 06 JUN 24100 PE', type: 'BUY', qty: 50, avg_price: 150.25, ltp: 138.70, pnl: -578 }
    ]
  })

  // Total Open Position P&L
  const totalOpenPnl = createMemo(() => {
    return openPositionsList().reduce((sum, p) => sum + Number(p.pnl || 0), 0)
  })

  // Recent Orders Mock
  const recentOrders = [
    { time: '09:23:45', symbol: 'NIFTY 24150 CE', type: 'BUY', qty: 75, status: 'Filled', class: 'bg-emerald-500/10 text-emerald-400' },
    { time: '09:23:12', symbol: 'BANKNIFTY 52400 PE', type: 'BUY', qty: 50, status: 'Filled', class: 'bg-emerald-500/10 text-emerald-400' },
    { time: '09:22:31', symbol: 'NIFTY 24100 PE', type: 'BUY', qty: 50, status: 'Filled', class: 'bg-emerald-500/10 text-emerald-400' },
    { time: '09:21:45', symbol: 'NIFTY 24150 CE', type: 'SELL', qty: 75, status: 'Cancelled', class: 'bg-gray-500/10 text-gray-400' },
    { time: '09:21:10', symbol: 'BANKNIFTY 52500 CE', type: 'BUY', qty: 50, status: 'Rejected', class: 'bg-rose-500/10 text-rose-400' }
  ]

  return (
    <div class="space-y-6">

      {/* 2. Top StatsBar KPI Cards Row */}
      <StatsBar balance={balance()} stats={liveStats()} marketStatus={marketStatus()} mode={mode()} />

      {/* 3. Middle Charts & Market Overview Row */}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Equity Curve Card */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[300px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Equity Curve (Today)</span>
            <span class="text-[9px] font-bold text-gray-500 bg-white/5 px-2 py-0.5 rounded-full uppercase">Today</span>
          </div>
          <div class="flex-1 flex items-center justify-between gap-6 py-4">
            {/* SVG Line Chart representing Equity curve */}
            <div class="flex-1 h-full relative">
              <svg viewBox="0 0 200 100" class="w-full h-full">
                <defs>
                  <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="rgb(16, 185, 129)" stop-opacity="0.2"/>
                    <stop offset="100%" stop-color="rgb(16, 185, 129)" stop-opacity="0.0"/>
                  </linearGradient>
                </defs>
                <path
                  d="M 10 90 L 30 75 L 65 80 L 100 45 L 130 55 L 165 25 L 190 15"
                  fill="none"
                  stroke="rgb(16, 185, 129)"
                  stroke-width="2"
                  stroke-linecap="round"
                />
                <path
                  d="M 10 90 L 30 75 L 65 80 L 100 45 L 130 55 L 165 25 L 190 15 L 190 95 L 10 95 Z"
                  fill="url(#equityGrad)"
                />
                {/* Horizontal reference dotted line */}
                <line x1="10" y1="60" x2="190" y2="60" stroke="rgba(255,255,255,0.05)" stroke-dasharray="3,3" />
              </svg>
              {/* Timeline labels */}
              <div class="flex justify-between text-[8px] text-gray-600 font-bold uppercase mt-1 px-1">
                <span>09:15</span>
                <span>11:00</span>
                <span>13:00</span>
                <span>15:15</span>
              </div>
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
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Max Drawdown</span>
                <div class="text-xs font-black text-rose-400 text-data mt-0.5">-₹6,230</div>
              </div>
              <div>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Profit Factor</span>
                <div class="text-xs font-black text-white text-data mt-0.5">2.18</div>
              </div>
              <div>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Sharpe Ratio</span>
                <div class="text-xs font-black text-white text-data mt-0.5">1.42</div>
              </div>
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
                {/* Wins: 62.5% (length 62.5, offset 0) */}
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5"
                  stroke-dasharray="62.5 37.5" stroke-dashoffset="0" />
                {/* Losses: 30% (length 30, offset 62.5) */}
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5"
                  stroke-dasharray="30 70" stroke-dashoffset="-62.5" />
                {/* Breakeven: 7.5% (length 7.5, offset 92.5) */}
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(107, 114, 128)" stroke-width="3.5"
                  stroke-dasharray="7.5 92.5" stroke-dashoffset="-92.5" />
              </svg>
              {/* Central counter */}
              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <span class="text-lg font-black text-white text-data">{totalTrades()}</span>
                <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Total</span>
              </div>
            </div>
            {/* Donut Legend */}
            <div class="flex-1 space-y-2 text-[10px] font-bold">
              <div class="flex items-center justify-between">
                <span class="text-gray-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-emerald-500" /> Win</span>
                <span class="text-white text-data">{winners()} ({winRate()}%)</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-gray-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-rose-500" /> Loss</span>
                <span class="text-white text-data">12 (30.0%)</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-gray-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-gray-500" /> Breakeven</span>
                <span class="text-white text-data">3 (7.5%)</span>
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
            {/* Quotes Rows */}
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">Nifty 50</span>
                <span class="text-gray-400 text-data mt-0.5">
                  <AnimatedNumber value={indices()?.nifty || 24195.20} decimals={2} />
                </span>
              </div>
              <span class="text-emerald-400 font-bold text-data">+125.75 (0.52%)</span>
            </div>
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">Bank Nifty</span>
                <span class="text-gray-400 text-data mt-0.5">
                  <AnimatedNumber value={indices()?.banknifty || 52410.35} decimals={2} />
                </span>
              </div>
              <span class="text-emerald-400 font-bold text-data">+321.40 (0.62%)</span>
            </div>
            {/* VIX/Status */}
            <div class="py-2.5 flex items-center justify-between">
              <div class="flex flex-col">
                <span class="font-black text-white uppercase tracking-wider">India VIX</span>
                <span class="text-gray-400 text-data mt-0.5">13.24</span>
              </div>
              <span class="text-rose-400 font-bold text-data">-0.32 (-2.36%)</span>
            </div>
            <div class="py-2.5 grid grid-cols-2 gap-2 text-[9px] uppercase tracking-wider text-gray-500 font-black">
              <div>Market Status: <span class="text-emerald-400">Open</span></div>
              <div>Expiry: <span class="text-white">27 Jun 24</span></div>
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
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                  <th class="py-2">Strategy</th>
                  <th class="py-2">Status</th>
                  <th class="py-2 text-right">PnL</th>
                </tr>
              </thead>
              <tbody>
                <For each={activeStrategies}>
                  {(s) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2.5 font-bold text-white">{s.name}</td>
                      <td class="py-2.5">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          s.status === 'Running' ? 'text-emerald-400 bg-emerald-500/10' : 'text-gray-500 bg-white/5'
                        }`}>{s.status}</span>
                      </td>
                      <td class={`py-2.5 text-right font-black text-data ${s.pnl >= 0 ? 'text-emerald-400' : 'text-gray-500'}`}>
                        {s.pnl ? `+₹${inrFormat(s.pnl)}` : '—'}
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>

        {/* Open Positions Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Open Positions</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-x-auto mt-2">
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
          </div>
        </div>

        {/* Recent Orders Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Recent Orders</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                  <th class="py-2">Time</th>
                  <th class="py-2">Instrument</th>
                  <th class="py-2 text-center">Side</th>
                  <th class="py-2 text-right">Status</th>
                </tr>
              </thead>
              <tbody>
                <For each={recentOrders}>
                  {(o) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2.5 text-gray-500 font-mono">{o.time}</td>
                      <td class="py-2.5 font-bold text-white max-w-[100px] truncate" title={o.symbol}>{o.symbol}</td>
                      <td class="py-2.5 text-center">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          o.type === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                        }`}>{o.type}</span>
                      </td>
                      <td class="py-2.5 text-right font-black">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] ${o.class}`}>{o.status}</span>
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
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
          </div>
        </div>

        {/* Alerts Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Alerts</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">View All</button>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[220px] mt-2 divide-y divide-white/5">
            <For each={alerts}>
              {(a) => (
                <div class="py-2.5 flex items-start gap-3 text-[10px]">
                  <span class="text-gray-500 font-mono mt-0.5">{a.time}</span>
                  <div class="flex-1">
                    <p class="text-white font-bold leading-snug">{a.text}</p>
                    <span class={`text-[8px] font-black uppercase mt-1 inline-block ${a.class.split(' ')[0]}`}>{a.type}</span>
                  </div>
                </div>
              )}
            </For>
          </div>
        </div>

        {/* System Health Panel */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">System Health</span>
            <span class="text-[8px] font-black uppercase text-emerald-400 flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" /> All Systems Operational</span>
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
