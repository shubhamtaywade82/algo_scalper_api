import { For, Show, onMount, createMemo, createSignal } from 'solid-js'
import { useEquityCurve } from '../stores/useEquityCurve'
import { useReports } from '../stores/useReports'
import EquityCurve from '../components/charts/EquityCurve'
import DrawdownChart from '../components/charts/DrawdownChart'
import AnimatedNumber from '../components/AnimatedNumber'

export default function Reports() {
  const [activeTab, setActiveTab] = createSignal('summary')
  const [sinceDate, setSinceDate] = createSignal('')
  const [untilDate, setUntilDate] = createSignal('')

  const { data: curveData, fetchCurve } = useEquityCurve()
  const { summary, daily, trades: reportTrades, byStrategy, byInstrument, loading, error, fetchAll } = useReports()

  onMount(() => {
    fetchCurve()
    fetchAll()
  })

  const metrics = createMemo(() => {
    const s = summary()
    if (!s) return []
    return [
      { label: 'Net P&L', val: s.net_pnl || 0, isPositive: (s.net_pnl || 0) >= 0, isCurrency: true },
      { label: 'Total Trades', val: s.total_trades || 0, isPositive: true },
      { label: 'Win Rate', val: s.win_rate_percent || 0, suffix: '%', isPositive: true },
      { label: 'Wins', val: s.winning_trades || 0, isPositive: true },
      { label: 'Profit Factor', val: s.profit_factor || 0, isPositive: true },
      { label: 'Avg Win', val: s.avg_win || 0, isPositive: true, isCurrency: true },
      { label: 'Expectancy', val: s.expectancy || 0, isPositive: (s.expectancy || 0) >= 0, isCurrency: true }
    ]
  })

  const topWinners = createMemo(() => {
    return reportTrades().filter(t => t.pnl > 0).sort((a, b) => b.pnl - a.pnl).slice(0, 5)
  })

  const monthly = createMemo(() => {
    const byMonth = {}
    for (const d of daily()) {
      const month = d.date.slice(0, 7)
      byMonth[month] = (byMonth[month] || 0) + d.pnl
    }
    return Object.entries(byMonth).sort((a, b) => a[0].localeCompare(b[0])).map(([month, pnl]) => ({
      month,
      pnl: Math.round(pnl * 100) / 100
    }))
  })

  return (
    <div class="space-y-6">
      {/* Filters & Actions Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">From</span>
            <input type="date" value={sinceDate()} onInput={(e) => setSinceDate(e.target.value)}
              class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono w-[140px]" />
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">To</span>
            <input type="date" value={untilDate()} onInput={(e) => setUntilDate(e.target.value)}
              class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono w-[140px]" />
          </div>
        </div>

        <div class="flex items-center gap-2.5">
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Schedule Report
          </button>
          <button
            onClick={() => {
              const params = new URLSearchParams()
              if (sinceDate()) params.set('since', sinceDate())
              if (untilDate()) params.set('until', untilDate())
              window.open(`/api/reports/export?${params.toString()}`, '_blank')
            }}
            class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all"
          >
            Export
          </button>
          <button
            onClick={() => fetchAll({ since: sinceDate(), until: untilDate() })}
            disabled={loading()}
            class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all disabled:opacity-40"
          >
            {loading() ? 'Loading...' : 'Generate Report'}
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
        <button
          onClick={() => setActiveTab('analytics')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'analytics' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Trade Analytics
        </button>
        <button
          onClick={() => setActiveTab('strategy')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'strategy' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Strategy Performance
        </button>
        <button
          onClick={() => setActiveTab('daily')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'daily' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Daily Analysis
        </button>
        <button
          onClick={() => setActiveTab('monthly')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'monthly' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Monthly Analysis
        </button>
        <button
          onClick={() => setActiveTab('instrument')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'instrument' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Instrument Analysis
        </button>
        <button
          onClick={() => setActiveTab('risk')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'risk' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Risk Analysis
        </button>
        <button
          onClick={() => setActiveTab('custom')}
          class={`px-4 py-2 rounded-lg transition-all shrink-0 ${activeTab() === 'custom' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Custom Reports
        </button>
      </div>

      <Show when={activeTab() === 'summary'}>
        <Show when={metrics().length > 0} fallback={
          <div class="flex items-center justify-center h-20 bg-white/[0.01] border border-dashed border-white/10 rounded-2xl">
            <span class="text-xs text-gray-600 font-bold uppercase tracking-wider">No report data yet</span>
          </div>
        }>
          <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-7 gap-4">
            <For each={metrics()}>
              {(m) => (
                <div class="glass p-4 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
                  <div>
                    <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">{m.label}</span>
                    <div class={`text-base font-black text-data ${m.isPositive ? 'text-emerald-400' : 'text-rose-400'}`}>
                      <AnimatedNumber value={m.val} currency={m.isCurrency} decimals={m.isCurrency ? 0 : 2} suffix={m.suffix} showSign={m.isCurrency ? true : false} />
                    </div>
                  </div>
                </div>
              )}
            </For>
          </div>
        </Show>

        {/* Charts & Breakdown Workspace */}
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div class="lg:col-span-9 space-y-6">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="glass rounded-2xl overflow-hidden h-[280px]">
                <EquityCurve data={() => curveData()} height={280} />
              </div>
              <div class="glass rounded-2xl overflow-hidden h-[280px]">
                <DrawdownChart data={() => curveData()} height={280} />
              </div>
            </div>
          </div>
          <div class="lg:col-span-3 space-y-6 flex flex-col justify-between h-full">
            <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[280px]">
              <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
                <span class="font-black text-gray-400 uppercase tracking-widest">Performance Breakdown</span>
              </div>
              <Show when={summary()?.total_trades > 0} fallback={
                <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
              }>
                <div class="flex-1 flex items-center justify-between gap-4 py-2">
                  <div class="relative w-20 h-20 shrink-0">
                    <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                      <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.02)" stroke-width="3" />
                      <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5"
                        stroke-dasharray={`${summary()?.win_rate_percent || 0} ${100 - (summary()?.win_rate_percent || 0)}`} stroke-dashoffset="0" />
                      <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5"
                        stroke-dasharray={`${100 - (summary()?.win_rate_percent || 0)} ${summary()?.win_rate_percent || 0}`} stroke-dashoffset={`-${summary()?.win_rate_percent || 0}`} />
                    </svg>
                    <div class="absolute inset-0 flex flex-col items-center justify-center">
                      <span class="text-[9px] font-black text-gray-400">Total</span>
                      <span class="text-[9px] font-black text-emerald-400">{summary()?.total_trades || 0}</span>
                    </div>
                  </div>
                  <div class="flex-1 space-y-1.5 text-[8px] font-black uppercase text-gray-500">
                    <div class="flex justify-between">
                      <span>Win</span>
                      <span class="text-white">{summary()?.win_rate_percent?.toFixed(1) || 0}%</span>
                    </div>
                    <div class="flex justify-between">
                      <span>Loss</span>
                      <span class="text-rose-500">{summary()?.losing_trades > 0 ? ((summary().losing_trades / summary().total_trades) * 100).toFixed(1) : 0}%</span>
                    </div>
                  </div>
                </div>
              </Show>
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
                  <Show when={reportTrades().length > 0} fallback={
                    <tr><td colspan="5" class="text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No recent trades</td></tr>
                  }>
                    <For each={reportTrades()}>
                      {(t) => (
                        <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                          <td class="py-2.5 text-gray-500 font-mono">{t.exited_at ? new Date(t.exited_at).toLocaleString('en-IN') : '—'}</td>
                          <td class="py-2.5 font-bold text-white max-w-[150px] truncate">{t.symbol}</td>
                          <td class="py-2.5 text-center">
                            <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                              t.side === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                            }`}>{t.side}</span>
                          </td>
                          <td class={`py-2.5 text-right font-black text-data ${t.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                            <AnimatedNumber value={t.pnl} currency decimals={0} showSign pnlColor />
                          </td>
                          <td class="py-2.5 text-right text-gray-400 font-bold">{t.entry_strategy || '—'}</td>
                        </tr>
                      )}
                    </For>
                  </Show>
                </tbody>
              </table>
            </div>
          </div>
          <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest">Daily P&L Calendar</span>
              <span class="text-gray-500 font-mono">{daily().length > 0 ? new Date(daily()[0].date).toLocaleDateString('en-IN', { month: 'long', year: 'numeric' }) : '—'}</span>
            </div>
            <div class="grid grid-cols-5 gap-2 mt-3 text-[10px]">
              <div class="text-center font-black text-gray-600 uppercase text-[8px]">Mon</div>
              <div class="text-center font-black text-gray-600 uppercase text-[8px]">Tue</div>
              <div class="text-center font-black text-gray-600 uppercase text-[8px]">Wed</div>
              <div class="text-center font-black text-gray-600 uppercase text-[8px]">Thu</div>
              <div class="text-center font-black text-gray-600 uppercase text-[8px]">Fri</div>
              <Show when={daily().length > 0} fallback={
                <div class="col-span-5 text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No daily data</div>
              }>
                <For each={daily()}>
                  {(day) => (
                    <div class={`p-1.5 rounded-lg border flex flex-col items-center justify-between min-h-[44px] ${
                      day.pnl >= 0 ? 'bg-emerald-500/5 border-emerald-500/20 text-emerald-400' : 'bg-rose-500/5 border-rose-500/20 text-rose-400'
                    }`}>
                      <span class="text-[7px] text-gray-400 font-mono self-start">{new Date(day.date).getDate()}</span>
                      <span class="text-[9px] font-black text-data">{day.pnl >= 0 ? '+' : ''}{day.pnl.toFixed(0)}</span>
                    </div>
                  )}
                </For>
              </Show>
            </div>
          </div>
        </div>

        {/* Bottom strategic data tables */}
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
          <div class="glass p-5 rounded-2xl">
            <div class="border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Strategy</span>
            </div>
            <div class="mt-2 max-h-[180px] overflow-y-auto">
              <Show when={byStrategy().length > 0} fallback={
                <div class="flex items-center justify-center h-16 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
              }>
                <table class="w-full text-left border-collapse text-[9px]">
                  <thead>
                    <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                      <th class="py-1.5">Strategy</th>
                      <th class="py-1.5 text-right">Trades</th>
                      <th class="py-1.5 text-right">WR</th>
                      <th class="py-1.5 text-right">Net P&L</th>
                    </tr>
                  </thead>
                  <tbody>
                    <For each={byStrategy()}>
                      {(s) => (
                        <tr class="border-b border-white/5">
                          <td class="py-1.5 font-bold text-white truncate max-w-[80px]">{s.strategy}</td>
                          <td class="py-1.5 text-right text-gray-400">{s.total_trades}</td>
                          <td class="py-1.5 text-right text-gray-400">{s.win_rate_percent}%</td>
                          <td class={`py-1.5 text-right font-black text-data ${s.net_pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                            <AnimatedNumber value={s.net_pnl} currency decimals={0} showSign />
                          </td>
                        </tr>
                      )}
                    </For>
                  </tbody>
                </table>
              </Show>
            </div>
          </div>
          <div class="glass p-5 rounded-2xl">
            <div class="border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Instrument</span>
            </div>
            <div class="mt-2 max-h-[180px] overflow-y-auto">
              <Show when={byInstrument().length > 0} fallback={
                <div class="flex items-center justify-center h-16 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
              }>
                <table class="w-full text-left border-collapse text-[9px]">
                  <thead>
                    <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                      <th class="py-1.5">Symbol</th>
                      <th class="py-1.5 text-right">Trades</th>
                      <th class="py-1.5 text-right">WR</th>
                      <th class="py-1.5 text-right">Net P&L</th>
                    </tr>
                  </thead>
                  <tbody>
                    <For each={byInstrument()}>
                      {(inst) => (
                        <tr class="border-b border-white/5">
                          <td class="py-1.5 font-bold text-white">{inst.symbol}</td>
                          <td class="py-1.5 text-right text-gray-400">{inst.total_trades}</td>
                          <td class="py-1.5 text-right text-gray-400">{inst.win_rate_percent}%</td>
                          <td class={`py-1.5 text-right font-black text-data ${inst.net_pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                            <AnimatedNumber value={inst.net_pnl} currency decimals={0} showSign />
                          </td>
                        </tr>
                      )}
                    </For>
                  </tbody>
                </table>
              </Show>
            </div>
          </div>
          <div class="glass p-5 rounded-2xl flex flex-col justify-between">
            <div class="border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Outcome Distribution</span>
            </div>
            <Show when={summary()?.total_trades > 0} fallback={
              <div class="flex items-center justify-center h-24 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
            }>
              <div class="flex-1 flex items-center justify-around py-3">
                <div class="relative w-20 h-20">
                  <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.02)" stroke-width="3" />
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="3.5"
                      stroke-dasharray={`${summary().win_rate_percent} ${100 - summary().win_rate_percent}`} stroke-dashoffset="0" />
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="3.5"
                      stroke-dasharray={`${100 - summary().win_rate_percent} ${summary().win_rate_percent}`} stroke-dashoffset={`-${summary().win_rate_percent}`} />
                  </svg>
                  <div class="absolute inset-0 flex flex-col items-center justify-center">
                    <span class="text-xs font-black text-white text-data">{summary()?.total_trades}</span>
                    <span class="text-[6px] text-gray-500 uppercase tracking-wider">Trades</span>
                  </div>
                </div>
                <div class="space-y-1.5 text-[9px] font-bold">
                  <div class="text-emerald-400">Wins: {summary()?.winning_trades || 0} ({summary()?.win_rate_percent?.toFixed(1) || 0}%)</div>
                  <div class="text-rose-400">Losses: {summary()?.losing_trades || 0} ({summary()?.losing_trades > 0 ? ((summary().losing_trades / summary().total_trades) * 100).toFixed(1) : 0}%)</div>
                </div>
              </div>
            </Show>
          </div>
          <div class="glass p-5 rounded-2xl">
            <div class="border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Top Winning Trades</span>
            </div>
            <Show when={topWinners().length > 0} fallback={
              <div class="flex items-center justify-center h-24 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
            }>
              <div class="overflow-x-auto mt-2">
                <table class="w-full text-left border-collapse text-[10px]">
                  <thead>
                    <tr class="text-gray-600 font-black uppercase border-b border-white/5">
                      <th class="py-2.5">Contract</th>
                      <th class="py-2.5 text-right">P&L</th>
                    </tr>
                  </thead>
                  <tbody>
                    <For each={topWinners()}>
                      {(w) => (
                        <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                          <td class="py-2 font-bold text-white max-w-[130px] truncate" title={w.symbol}>{w.symbol}</td>
                          <td class="py-2 text-right font-black text-emerald-400 text-data">
                            +₹{Number(w.pnl).toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                          </td>
                        </tr>
                      )}
                    </For>
                  </tbody>
                </table>
              </div>
            </Show>
          </div>
        </div>
      </Show>

      {/* Trade Analytics */}
      <Show when={activeTab() === 'analytics'}>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div class="lg:col-span-4 glass p-5 rounded-2xl space-y-3">
            <div class="border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Average Trade</span>
            </div>
            <div class="text-[10px] space-y-2">
              <div class="flex justify-between"><span class="text-gray-500">Avg Win</span><span class="font-black text-emerald-400 text-data"><AnimatedNumber value={summary()?.avg_win || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Avg Loss</span><span class="font-black text-rose-400 text-data"><AnimatedNumber value={summary()?.avg_loss || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Max Win</span><span class="font-black text-emerald-400 text-data"><AnimatedNumber value={summary()?.max_win || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Max Loss</span><span class="font-black text-rose-400 text-data"><AnimatedNumber value={summary()?.max_loss || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Profit Factor</span><span class="font-black text-white text-data">{summary()?.profit_factor?.toFixed(2) || '—'}</span></div>
            </div>
          </div>
          <div class="lg:col-span-4 glass p-5 rounded-2xl space-y-3">
            <div class="border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Win/Loss Metrics</span>
            </div>
            <div class="text-[10px] space-y-2">
              <div class="flex justify-between"><span class="text-gray-500">Winning Trades</span><span class="font-black text-emerald-400">{summary()?.winning_trades || 0}</span></div>
              <div class="flex justify-between"><span class="text-gray-500">Losing Trades</span><span class="font-black text-rose-400">{summary()?.losing_trades || 0}</span></div>
              <div class="flex justify-between"><span class="text-gray-500">Gross Profit</span><span class="font-black text-emerald-400 text-data"><AnimatedNumber value={summary()?.gross_profit || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Gross Loss</span><span class="font-black text-rose-400 text-data"><AnimatedNumber value={summary()?.gross_loss || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Expectancy</span><span class={`font-black text-data ${(summary()?.expectancy || 0) >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}><AnimatedNumber value={summary()?.expectancy || 0} currency decimals={0} showSign /></span></div>
            </div>
          </div>
          <div class="lg:col-span-4 glass p-5 rounded-2xl space-y-3">
            <div class="border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Costs</span>
            </div>
            <div class="text-[10px] space-y-2">
              <div class="flex justify-between"><span class="text-gray-500">Total Brokerage</span><span class="font-black text-white text-data"><AnimatedNumber value={summary()?.total_brokerage || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between pt-4"><span class="text-gray-500 uppercase text-[8px] font-bold">Note</span></div>
              <div class="text-gray-600 text-[8px] leading-relaxed">Brokerage, STT, transaction charges and taxes are estimated. Actual costs may vary.</div>
            </div>
          </div>
        </div>
      </Show>

      {/* Strategy Performance */}
      <Show when={activeTab() === 'strategy'}>
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Strategy</span>
          </div>
          <Show when={byStrategy().length > 0} fallback={
            <div class="flex items-center justify-center h-24 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
          }>
            <div class="overflow-x-auto mt-3">
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2.5">Strategy</th>
                    <th class="py-2.5 text-right">Total</th>
                    <th class="py-2.5 text-right">Wins</th>
                    <th class="py-2.5 text-right">Losses</th>
                    <th class="py-2.5 text-right">Win Rate</th>
                    <th class="py-2.5 text-right">Avg P&L</th>
                    <th class="py-2.5 text-right">Net P&L</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={byStrategy()}>
                    {(s) => (
                      <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                        <td class="py-2.5 font-bold text-white">{s.strategy}</td>
                        <td class="py-2.5 text-right text-gray-400">{s.total_trades}</td>
                        <td class="py-2.5 text-right text-emerald-400 font-bold">{s.wins}</td>
                        <td class="py-2.5 text-right text-rose-400 font-bold">{s.losses}</td>
                        <td class="py-2.5 text-right text-gray-300 font-bold">{s.win_rate_percent}%</td>
                        <td class="py-2.5 text-right font-black text-data">
                          <AnimatedNumber value={s.avg_pnl} currency decimals={0} showSign />
                        </td>
                        <td class={`py-2.5 text-right font-black text-data ${s.net_pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                          <AnimatedNumber value={s.net_pnl} currency decimals={0} showSign />
                        </td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>
        </div>
      </Show>

      {/* Daily Analysis */}
      <Show when={activeTab() === 'daily'}>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div class="lg:col-span-7 glass rounded-2xl overflow-hidden h-[360px]">
            <EquityCurve data={() => curveData()} height={360} />
          </div>
          <div class="lg:col-span-5 glass p-5 rounded-2xl flex flex-col justify-between">
            <div class="border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest">Daily P&L Calendar</span>
            </div>
            <Show when={daily().length > 0} fallback={
              <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">No daily data</div>
            }>
              <div class="grid grid-cols-5 gap-2 mt-3 text-[10px] flex-1 content-start">
                <div class="text-center font-black text-gray-600 uppercase text-[8px]">Mon</div>
                <div class="text-center font-black text-gray-600 uppercase text-[8px]">Tue</div>
                <div class="text-center font-black text-gray-600 uppercase text-[8px]">Wed</div>
                <div class="text-center font-black text-gray-600 uppercase text-[8px]">Thu</div>
                <div class="text-center font-black text-gray-600 uppercase text-[8px]">Fri</div>
                <For each={daily()}>
                  {(day) => (
                    <div class={`p-1.5 rounded-lg border flex flex-col items-center justify-between min-h-[44px] ${
                      day.pnl >= 0 ? 'bg-emerald-500/5 border-emerald-500/20 text-emerald-400' : 'bg-rose-500/5 border-rose-500/20 text-rose-400'
                    }`}>
                      <span class="text-[7px] text-gray-400 font-mono self-start">{new Date(day.date).getDate()}</span>
                      <span class="text-[9px] font-black text-data">{day.pnl >= 0 ? '+' : ''}{day.pnl.toFixed(0)}</span>
                    </div>
                  )}
                </For>
              </div>
            </Show>
          </div>
        </div>
      </Show>

      {/* Monthly Analysis */}
      <Show when={activeTab() === 'monthly'}>
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Monthly P&L Breakdown</span>
          </div>
          <Show when={monthly().length > 0} fallback={
            <div class="flex items-center justify-center h-24 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
          }>
            <div class="overflow-x-auto mt-3">
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2.5">Month</th>
                    <th class="py-2.5 text-right">P&L</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={monthly()}>
                    {(m) => {
                      const d = new Date(m.month + '-01')
                      const label = d.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' })
                      return (
                        <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                          <td class="py-2.5 font-bold text-white">{label}</td>
                          <td class={`py-2.5 text-right font-black text-data ${m.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                            <AnimatedNumber value={m.pnl} currency decimals={0} showSign />
                          </td>
                        </tr>
                      )
                    }}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>
        </div>
      </Show>

      {/* Instrument Analysis */}
      <Show when={activeTab() === 'instrument'}>
        <div class="glass p-5 rounded-2xl">
          <div class="border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">P&L by Instrument</span>
          </div>
          <Show when={byInstrument().length > 0} fallback={
            <div class="flex items-center justify-center h-24 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
          }>
            <div class="overflow-x-auto mt-3">
              <table class="w-full text-left border-collapse text-[10px]">
                <thead>
                  <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                    <th class="py-2.5">Symbol</th>
                    <th class="py-2.5 text-right">Total</th>
                    <th class="py-2.5 text-right">Wins</th>
                    <th class="py-2.5 text-right">Losses</th>
                    <th class="py-2.5 text-right">Win Rate</th>
                    <th class="py-2.5 text-right">Avg P&L</th>
                    <th class="py-2.5 text-right">Net P&L</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={byInstrument()}>
                    {(inst) => (
                      <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                        <td class="py-2.5 font-bold text-white">{inst.symbol}</td>
                        <td class="py-2.5 text-right text-gray-400">{inst.total_trades}</td>
                        <td class="py-2.5 text-right text-emerald-400 font-bold">{inst.wins}</td>
                        <td class="py-2.5 text-right text-rose-400 font-bold">{inst.losses}</td>
                        <td class="py-2.5 text-right text-gray-300 font-bold">{inst.win_rate_percent}%</td>
                        <td class="py-2.5 text-right font-black text-data">
                          <AnimatedNumber value={inst.avg_pnl} currency decimals={0} showSign />
                        </td>
                        <td class={`py-2.5 text-right font-black text-data ${inst.net_pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                          <AnimatedNumber value={inst.net_pnl} currency decimals={0} showSign />
                        </td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>
        </div>
      </Show>

      {/* Risk Analysis */}
      <Show when={activeTab() === 'risk'}>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div class="lg:col-span-6 glass p-5 rounded-2xl space-y-3">
            <div class="border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Risk Metrics</span>
            </div>
            <div class="text-[10px] space-y-3">
              <div class="flex justify-between"><span class="text-gray-500">Max Drawdown (₹)</span><span class="font-black text-rose-400 text-data"><AnimatedNumber value={summary()?.max_loss || 0} currency decimals={0} showSign /></span></div>
              <div class="flex justify-between"><span class="text-gray-500">Max Drawdown (%)</span><span class="font-black text-rose-400">{summary()?.max_loss && summary()?.net_pnl ? (Math.abs(summary().max_loss) / Math.abs(summary().net_pnl || 1) * 100).toFixed(1) : 0}%</span></div>
              <div class="flex justify-between"><span class="text-gray-500">Profit Factor</span><span class="font-black text-white text-data">{summary()?.profit_factor?.toFixed(2) || '—'}</span></div>
              <div class="flex justify-between"><span class="text-gray-500">Win Rate</span><span class="font-black text-emerald-400">{summary()?.win_rate_percent?.toFixed(1) || 0}%</span></div>
              <div class="flex justify-between"><span class="text-gray-500">Expectancy</span><span class={`font-black text-data ${(summary()?.expectancy || 0) >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}><AnimatedNumber value={summary()?.expectancy || 0} currency decimals={0} showSign /></span></div>
            </div>
          </div>
          <div class="lg:col-span-6 glass p-5 rounded-2xl flex flex-col justify-between">
            <div class="border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest">Outcome Distribution</span>
            </div>
            <Show when={summary()?.total_trades > 0} fallback={
              <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">No data</div>
            }>
              <div class="flex-1 flex items-center justify-around py-4">
                <div class="relative w-24 h-24">
                  <svg viewBox="0 0 36 36" class="w-full h-full transform -rotate-90">
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgba(255,255,255,0.02)" stroke-width="3" />
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(16, 185, 129)" stroke-width="4"
                      stroke-dasharray={`${summary().win_rate_percent} ${100 - summary().win_rate_percent}`} stroke-dashoffset="0" />
                    <circle cx="18" cy="18" r="15.915" fill="none" stroke="rgb(239, 68, 68)" stroke-width="4"
                      stroke-dasharray={`${100 - summary().win_rate_percent} ${summary().win_rate_percent}`} stroke-dashoffset={`-${summary().win_rate_percent}`} />
                  </svg>
                  <div class="absolute inset-0 flex flex-col items-center justify-center">
                    <span class="text-sm font-black text-white text-data">{summary()?.total_trades}</span>
                    <span class="text-[7px] text-gray-500 uppercase tracking-wider">Trades</span>
                  </div>
                </div>
                <div class="space-y-2 text-[10px] font-bold">
                  <div class="text-emerald-400">Wins: {summary()?.winning_trades || 0} ({summary()?.win_rate_percent?.toFixed(1) || 0}%)</div>
                  <div class="text-rose-400">Losses: {summary()?.losing_trades || 0} ({summary()?.losing_trades > 0 ? ((summary().losing_trades / summary().total_trades) * 100).toFixed(1) : 0}%)</div>
                </div>
              </div>
            </Show>
          </div>
        </div>
      </Show>

      {/* Custom Reports */}
      <Show when={activeTab() === 'custom'}>
        <div class="glass p-8 rounded-2xl flex flex-col items-center justify-center gap-4">
          <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Custom Reports</span>
          <p class="text-xs text-gray-600 text-center max-w-md leading-relaxed">
            Build custom report templates combining metrics, charts, and breakdowns.
            Select a date range, choose what to include, and schedule automated delivery.
          </p>
          <div class="flex items-center gap-3 mt-2">
            <button class="px-5 py-2.5 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">Schedule Report</button>
            <button class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all">Export Data</button>
          </div>
        </div>
      </Show>
    </div>
  )
}
