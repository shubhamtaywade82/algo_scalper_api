import { For, Show } from 'solid-js'
import AnimatedNumber from '../components/AnimatedNumber'

export default function Reports() {
  const [activeTab, setActiveTab] = createSignal('summary')
  const [activeTimeframe, setActiveTimeframe] = createSignal('daily')

  // KPI Period Metrics
  const metrics = [
    { label: 'Net P&L', val: 124560, pct: 24.35, prev: 98450, isPositive: true, isCurrency: true, path: 'M0,35 Q20,25 40,28 T80,10 T100,5' },
    { label: 'Total Return', val: 12.46, prev: 9.21, isPositive: true, suffix: '%', path: 'M0,30 Q25,32 50,20 T100,8' },
    { label: 'Total Trades', val: 76, prev: 62, isPositive: true, path: 'M0,35 Q20,38 40,25 T80,18 T100,10' },
    { label: 'Win Rate', val: 63.21, prev: 54.84, isPositive: true, suffix: '%', path: 'M0,32 Q30,30 60,18 T100,6' },
    { label: 'Profit Factor', val: 2.18, prev: 1.65, isPositive: true, path: 'M0,35 Q20,32 40,30 T80,15 T100,10' },
    { label: 'Max Drawdown', val: 18750, pct: 1.87, prev: 23450, isPositive: false, isCurrency: true, path: 'M0,5 Q20,15 40,12 T80,30 T100,45' },
    { label: 'Expectancy', val: 1639.47, prev: 1331.22, isPositive: true, isCurrency: true, path: 'M0,30 Q30,32 60,20 T100,12' }
  ]

  // Calendar days mock for May 2024
  const calendarDays = [
    { date: 29, pnl: 1200, label: '+1.2K' },
    { date: 30, pnl: -850, label: '-850' },
    { date: 1, pnl: 2100, label: '+2.1K' },
    { date: 2, pnl: 1800, label: '+1.8K' },
    { date: 3, pnl: -1300, label: '-1.3K' },
    { date: 6, pnl: 2500, label: '+2.5K' },
    { date: 7, pnl: 1400, label: '+1.4K' },
    { date: 8, pnl: -950, label: '-950' },
    { date: 9, pnl: 3200, label: '+3.2K' },
    { date: 10, pnl: 2100, label: '+2.1K' },
    { date: 13, pnl: -1100, label: '-1.1K' },
    { date: 14, pnl: 2300, label: '+2.3K' },
    { date: 15, pnl: 1600, label: '+1.6K' },
    { date: 16, pnl: -780, label: '-780' },
    { date: 17, pnl: 2900, label: '+2.9K' },
    { date: 20, pnl: 2200, label: '+2.2K' },
    { date: 21, pnl: -1500, label: '-1.5K' },
    { date: 22, pnl: 2400, label: '+2.4K' },
    { date: 23, pnl: 1900, label: '+1.9K' },
    { date: 24, pnl: -860, label: '-860' },
    { date: 27, pnl: 2200, label: '+2.2K' },
    { date: 28, pnl: 3100, label: '+3.1K' },
    { date: 29, pnl: 1800, label: '+1.8K' },
    { date: 30, pnl: 2000, label: '+2.0K' },
    { date: 31, pnl: -1200, label: '-1.2K' }
  ]

  // Recent Trades Mock
  const trades = [
    { time: '03 Jun 09:37:45', inst: 'NIFTY 06 JUN 22100 CE', type: 'BUY', qty: 75, entry: 134.50, exit: 142.80, pnl: 830, pnlPct: 6.17, dur: '22m 45s', strat: 'ORB Breakout' },
    { time: '03 Jun 09:21:10', inst: 'BANKNIFTY 06 JUN 52400 PE', type: 'BUY', qty: 50, entry: 180.10, exit: 195.35, pnl: 762, pnlPct: 8.47, dur: '28m 15s', strat: 'Supertrend Scalper' },
    { time: '03 Jun 10:12:00', inst: 'NIFTY 06 JUN 22150 CE', type: 'BUY', qty: 75, entry: 128.40, exit: 123.20, pnl: -390, pnlPct: -4.05, dur: '19m 30s', strat: 'ORB Breakout' },
    { time: '03 Jun 10:32:30', inst: 'NIFTY 06 JUN 22150 CE', type: 'SELL', qty: 75, entry: 128.40, exit: 123.20, pnl: -390, pnlPct: -4.05, dur: '14m 20s', strat: 'ORB Breakout' },
    { time: '03 Jun 11:05:00', inst: 'NIFTY 06 JUN 22200 CE', type: 'BUY', qty: 75, entry: 110.25, exit: 118.70, pnl: 635, pnlPct: 7.66, dur: '16m 10s', strat: 'EMA Cross' }
  ]

  // PnL by Strategy
  const strategyStats = [
    { strat: 'ORB Breakout', pnl: 62450, trades: 28, win: '67.88%', pf: '2.45' },
    { strat: 'Supertrend Scalper', pnl: 38210, trades: 18, win: '66.67%', pf: '2.10' },
    { strat: 'EMA Cross', pnl: 18900, trades: 12, win: '58.33%', pf: '1.78' },
    { strat: 'VWAP Revert', pnl: 7150, trades: 10, win: '50.00%', pf: '1.32' },
    { strat: 'AI Momentum', pnl: -2150, trades: 8, win: '37.50%', pf: '0.88' }
  ]

  // PnL by Instrument
  const instrumentStats = [
    { inst: 'NIFTY', pnl: 71450, trades: 42, win: '64.29%' },
    { inst: 'BANKNIFTY', pnl: 45860, trades: 22, win: '63.64%' },
    { inst: 'FINNIFTY', pnl: 12340, trades: 8, win: '62.50%' },
    { inst: 'SENSEX', pnl: -3090, trades: 4, win: '25.00%' }
  ]

  // Top Winning Trades
  const topWinners = [
    { inst: 'NIFTY 06 JUN 22100 CE', pnl: 2450, pct: 18.24 },
    { inst: 'BANKNIFTY 06 JUN 52400 PE', pnl: 2230, pct: 15.31 },
    { inst: 'NIFTY 06 JUN 22050 CE', pnl: 1980, pct: 13.45 },
    { inst: 'FINNIFTY 05 JUN 23100 CE', pnl: 1720, pct: 12.12 },
    { inst: 'NIFTY 06 JUN 22150 CE', pnl: 1650, pct: 11.28 }
  ]

  return (
    <div class="space-y-6">
      {/* Filters & Actions Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Date Range</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono">
              01 Apr 2024 - 03 Jun 2024
            </div>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Compare With</span>
            <select class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg">
              <option>01 Mar 2024 - 31 Mar 2024</option>
            </select>
          </div>
        </div>

        <div class="flex items-center gap-2.5">
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Schedule Report
          </button>
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Export
          </button>
          <button class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all">
            Generate Report
          </button>
        </div>
      </div>

      {/* Tabs Menu */}
      <div class="flex items-center gap-1.5 border-b border-white/5 pb-2 text-[10px] font-black uppercase tracking-wider overflow-x-auto">
        <button
          onClick={() => setActiveTab('summary')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'summary' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Performance Summary
        </button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Trade Analytics</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Strategy Performance</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Daily Analysis</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Monthly Analysis</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Instrument Analysis</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Risk Analysis</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300 shrink-0">Custom Reports</button>
      </div>

      {/* Performance KPI Cards */}
      <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-7 gap-4">
        <For each={metrics}>
          {(m) => (
            <div class="glass p-4 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
              <div>
                <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">{m.label}</span>
                <div class={`text-base font-black text-data ${m.isPositive ? 'text-emerald-400' : 'text-rose-400'}`}>
                  <AnimatedNumber value={m.val} currency={m.isCurrency} decimals={m.isCurrency ? 0 : 2} suffix={m.suffix} showSign={m.isPositive} />
                </div>
                <span class="text-[8px] text-gray-500 mt-1 block uppercase tracking-tighter">
                  vs prev: <AnimatedNumber value={m.prev} currency={m.isCurrency} decimals={0} />
                </span>
              </div>
              <div class="absolute bottom-2 right-2 w-14 h-6 opacity-35 group-hover:opacity-60 transition-opacity">
                <svg viewBox="0 0 100 50" class="w-full h-full">
                  <path
                    d={m.path}
                    fill="none"
                    stroke={m.isPositive ? 'rgb(52, 211, 153)' : 'rgb(239, 68, 68)'}
                    stroke-width="3"
                    stroke-linecap="round"
                  />
                </svg>
              </div>
            </div>
          )}
        </For>
      </div>

      {/* Charts & Breakdown Workspace */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Equity & Drawdown Curves (9 cols) */}
        <div class="lg:col-span-9 space-y-6">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Equity Curve */}
            <div class="glass p-5 rounded-2xl h-[280px] flex flex-col justify-between">
              <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
                <span class="font-black text-gray-400 uppercase tracking-widest">Equity Curve</span>
                <div class="flex items-center gap-2 text-[8px] font-bold">
                  <span class="text-emerald-400 flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500" /> Equity</span>
                  <span class="text-gray-600 flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-gray-500" /> Buy & Hold</span>
                </div>
              </div>
              <div class="flex-1 py-4 relative">
                <svg viewBox="0 0 250 100" class="w-full h-full">
                  <path d="M0,90 L50,92 L100,75 L150,80 L200,60 L250,55" fill="none" stroke="rgba(255,255,255,0.1)" stroke-width="1" />
                  <path d="M0,90 Q40,80 80,60 T160,55 T250,30" fill="none" stroke="rgb(16, 185, 129)" stroke-width="2" />
                </svg>
              </div>
            </div>

            {/* Drawdown Curve */}
            <div class="glass p-5 rounded-2xl h-[280px] flex flex-col justify-between">
              <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
                <span class="font-black text-gray-400 uppercase tracking-widest">Drawdown Curve</span>
                <span class="text-[8px] text-rose-500 font-bold uppercase">Max: 1.87%</span>
              </div>
              <div class="flex-1 py-4 relative">
                <svg viewBox="0 0 250 100" class="w-full h-full">
                  <path d="M0,5 Q50,20 100,15 T200,45 T250,60" fill="none" stroke="rgb(239, 68, 68)" stroke-width="1.5" />
                </svg>
              </div>
            </div>
          </div>
        </div>

        {/* Performance Breakdown & Calendar (3 cols) */}
        <div class="lg:col-span-3 space-y-6 flex flex-col justify-between h-full">
          {/* Performance Breakdown Donut */}
          <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[280px]">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest">Performance Breakdown</span>
            </div>
            <div class="flex-1 flex items-center justify-between gap-4 py-2">
              <div class="relative w-20 h-20 shrink-0">
                <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.02)" stroke-width="3" />
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5" stroke-dasharray="68 32" stroke-dashoffset="0" />
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5" stroke-dasharray="20 80" stroke-dashoffset="-68" />
                  <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(107, 114, 128)" stroke-width="3.5" stroke-dasharray="12 88" stroke-dashoffset="-88" />
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-[9px] font-black text-gray-400">Total</span>
                  <span class="text-[9px] font-black text-emerald-400">+124K</span>
                </div>
              </div>
              <div class="flex-1 space-y-1.5 text-[8px] font-black uppercase text-gray-500">
                <div class="flex justify-between">
                  <span>Win</span>
                  <span class="text-white">68.3%</span>
                </div>
                <div class="flex justify-between">
                  <span>Loss</span>
                  <span class="text-rose-500">20.5%</span>
                </div>
                <div class="flex justify-between">
                  <span>Others</span>
                  <span class="text-white">11.2%</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* P&L Calendar Row */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <div class="lg:col-span-8 glass p-5 rounded-2xl">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Recent Trades</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                  <th class="py-2.5">Time</th>
                  <th class="py-2.5">Instrument</th>
                  <th class="py-2.5 text-center">Type</th>
                  <th class="py-2.5 text-right font-black text-data">P&L</th>
                  <th class="py-2.5 text-right">Strategy</th>
                </tr>
              </thead>
              <tbody>
                <For each={trades}>
                  {(t) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2.5 text-gray-500 font-mono">{t.time}</td>
                      <td class="py-2.5 font-bold text-white max-w-[150px] truncate">{t.inst}</td>
                      <td class="py-2.5 text-center">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          t.type === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                        }`}>{t.type}</span>
                      </td>
                      <td class={`py-2.5 text-right font-black text-data ${t.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        <AnimatedNumber value={t.pnl} currency decimals={0} showSign pnlColor />
                      </td>
                      <td class="py-2.5 text-right text-gray-400 font-bold">{t.strat}</td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>

        {/* Daily P&L Calendar */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
            <span class="font-black text-gray-400 uppercase tracking-widest">Daily P&L Calendar</span>
            <span class="text-gray-500 font-mono">May 2024</span>
          </div>
          <div class="grid grid-cols-5 gap-2 mt-3 text-[10px]">
            <div class="text-center font-black text-gray-600 uppercase text-[8px]">Mon</div>
            <div class="text-center font-black text-gray-600 uppercase text-[8px]">Tue</div>
            <div class="text-center font-black text-gray-600 uppercase text-[8px]">Wed</div>
            <div class="text-center font-black text-gray-600 uppercase text-[8px]">Thu</div>
            <div class="text-center font-black text-gray-600 uppercase text-[8px]">Fri</div>
            <For each={calendarDays}>
              {(day) => (
                <div class={`p-1.5 rounded-lg border flex flex-col items-center justify-between min-h-[44px] ${
                  day.pnl >= 0 ? 'bg-emerald-500/5 border-emerald-500/20 text-emerald-400' : 'bg-rose-500/5 border-rose-500/20 text-rose-400'
                }`}>
                  <span class="text-[7px] text-gray-400 font-mono self-start">{day.date}</span>
                  <span class="text-[9px] font-black text-data">{day.label}</span>
                </div>
              )}
            </For>
          </div>
        </div>
      </div>

      {/* Bottom strategic data tables */}
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
        {/* PnL by Strategy */}
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Strategy</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase border-b border-white/5">
                  <th class="py-2.5">Strategy</th>
                  <th class="py-2.5 text-right">P&L</th>
                </tr>
              </thead>
              <tbody>
                <For each={strategyStats}>
                  {(s) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2 font-bold text-white">{s.strat}</td>
                      <td class={`py-2 text-right font-black text-data ${s.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        <AnimatedNumber value={s.pnl} currency decimals={0} showSign pnlColor />
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>

        {/* PnL by Instrument */}
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Instrument</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase border-b border-white/5">
                  <th class="py-2.5">Asset</th>
                  <th class="py-2.5 text-right">P&L</th>
                </tr>
              </thead>
              <tbody>
                <For each={instrumentStats}>
                  {(i) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2 font-bold text-white">{i.inst}</td>
                      <td class={`py-2 text-right font-black text-data ${i.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        <AnimatedNumber value={i.pnl} currency decimals={0} showSign pnlColor />
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>

        {/* Trade Outcome Distribution */}
        <div class="glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Outcome Distribution</span>
          </div>
          <div class="flex-1 flex items-center justify-around py-3">
            <div class="relative w-20 h-20">
              <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.02)" stroke-width="3" />
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5" stroke-dasharray="63 37" stroke-dashoffset="0" />
                <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5" stroke-dasharray="37 63" stroke-dashoffset="-63" />
              </svg>
              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <span class="text-xs font-black text-white text-data">76</span>
                <span class="text-[6px] text-gray-500 uppercase tracking-wider">Trades</span>
              </div>
            </div>
            <div class="space-y-1.5 text-[9px] font-bold">
              <div class="text-emerald-400">Wins: 48 (63%)</div>
              <div class="text-rose-400">Losses: 28 (37%)</div>
            </div>
          </div>
        </div>

        {/* Top Winning Trades */}
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Top Winning Trades</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase border-b border-white/5">
                  <th class="py-2.5">Contract</th>
                  <th class="py-2.5 text-right">P&L</th>
                </tr>
              </thead>
              <tbody>
                <For each={topWinners}>
                  {(w) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2 font-bold text-white max-w-[130px] truncate" title={w.inst}>{w.inst}</td>
                      <td class="py-2 text-right font-black text-emerald-400 text-data">
                        +₹{w.pnl.toLocaleString('en-IN')}
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Footer Info Note */}
      <p class="text-center text-[8px] font-black uppercase text-gray-600 tracking-widest py-4">
        All P&L shown is in INR. Costs include brokerage, STT, transaction charges and taxes.
      </p>
    </div>
  )
}
