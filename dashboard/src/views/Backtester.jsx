import { createSignal, createMemo, For, Show } from 'solid-js'
import { useBacktest } from '../stores/useBacktest'
import AnimatedNumber from '../components/AnimatedNumber'
import EquityCurve from '../components/charts/EquityCurve'

export default function Backtester() {
  const [selectedStrategy, setSelectedStrategy] = createSignal('ORB Breakout')
  const [activeTab, setActiveTab] = createSignal('overview')
  const [selectedTradeIndex, setSelectedTradeIndex] = createSignal(0)
  const [symbol, setSymbol] = createSignal('NIFTY')
  const [daysBack, setDaysBack] = createSignal(30)

  const { result, loading, error, runBacktest } = useBacktest()

  const btResult = createMemo(() => result() || {})

  const metrics = createMemo(() => btResult().metrics || {})
  const trades = createMemo(() => btResult().trades || [])
  const equityCurve = createMemo(() => btResult().equity_curve || [])
  const config = createMemo(() => btResult().config || {})

  const selectedTrade = createMemo(() => {
    const t = trades()
    const idx = selectedTradeIndex()
    return t[idx] || {}
  })

  function handleRunBacktest() {
    runBacktest({ symbol: symbol(), days_back: daysBack() })
  }

  return (
    <div class="space-y-6">

      {/* Action Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex items-center gap-3">
          <select class="glass-select text-xs px-3 py-2 rounded-xl">
            <option>Supertrend Backtest</option>
          </select>
          <select class="glass-select text-xs px-3 py-2 rounded-xl" value={symbol()} onChange={e => setSymbol(e.target.value)}>
            <option value="NIFTY">NIFTY</option>
            <option value="BANKNIFTY">BANKNIFTY</option>
            <option value="SENSEX">SENSEX</option>
          </select>
          <select class="glass-select text-xs px-3 py-2 rounded-xl" value={daysBack()} onChange={e => setDaysBack(Number(e.target.value))}>
            <option value={7}>7 days</option>
            <option value={30}>30 days</option>
            <option value={60}>60 days</option>
            <option value={90}>90 days</option>
          </select>
        </div>
        <div class="flex items-center gap-2.5">
          <Show when={error()}>
            <span class="text-[9px] text-rose-400">{error()}</span>
          </Show>
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Save Report
          </button>
          <button
            onClick={handleRunBacktest}
            disabled={loading()}
            class={`px-5 py-2.5 rounded-xl text-xs font-black uppercase tracking-wider transition-all flex items-center gap-1.5 ${
              loading()
                ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                : 'bg-primary-600 hover:bg-primary-500 text-white shadow-[0_0_15px_rgba(59,130,246,0.25)] hover:shadow-[0_0_20px_rgba(59,130,246,0.45)]'
            }`}
          >
            <span>{loading() ? '⟳' : '▶'}</span> {loading() ? 'Running...' : 'Run Backtest'}
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div class="flex items-center gap-1.5 border-b border-white/5 pb-2 text-[10px] font-black uppercase tracking-wider">
        <button
          onClick={() => setActiveTab('overview')}
          class={`px-4 py-2 rounded-lg transition-all ${activeTab() === 'overview' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Overview
        </button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300">Equity Curve</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300">Trades</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300">Monthly Returns</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300">Statistics</button>
        <button class="px-4 py-2 text-gray-500 hover:text-gray-300">Logs</button>
      </div>

      {/* KPI Cards Row */}
      <div class="grid grid-cols-1 md:grid-cols-4 xl:grid-cols-7 gap-4">
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Net Profit</span>
          <div class="text-lg font-black text-emerald-400 text-data">₹{(metrics().netProfit || 0).toLocaleString('en-IN')}</div>
          <span class="text-[9px] font-bold text-emerald-500 mt-1 block">{metrics().netProfitPct >= 0 ? '+' : ''}{metrics().netProfitPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Return</span>
          <div class="text-lg font-black text-white text-data">{metrics().totalReturn}%</div>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Win Rate</span>
          <div class="text-lg font-black text-white text-data">{metrics().winRate}%</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">({metrics().winningTrades} / {metrics().totalTrades})</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Profit Factor</span>
          <div class="text-lg font-black text-white text-data">{metrics().profitFactor}</div>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Max Drawdown</span>
          <div class="text-lg font-black text-rose-500 text-data">₹{(metrics().maxDrawdown || 0).toLocaleString('en-IN')}</div>
          <span class="text-[9px] font-bold text-rose-500 mt-1 block">{metrics().maxDrawdownPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Trades</span>
          <div class="text-lg font-black text-white text-data">{metrics().totalTrades}</div>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Expectancy</span>
          <div class="text-lg font-black text-white text-data">₹{metrics().expectancy}</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">Per Trade</span>
        </div>
      </div>

      {/* Main Workspace Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left 9 columns: Chart & Table */}
        <div class="lg:col-span-9 space-y-6">
          <div class="glass p-5 rounded-2xl h-[340px] flex flex-col justify-between">
            <div class="flex items-center justify-between border-b border-white/5 pb-3">
              <div>
                <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest block">Equity Curve</span>
                <span class="text-[8px] font-bold text-gray-600 mt-0.5 block">Initial Capital: ₹250,000</span>
              </div>
            </div>
            <div class="flex-1 py-2">
              <Show when={result()} fallback={
                <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">
                  Run a backtest to see equity curve
                </div>
              }>
                <EquityCurve data={equityCurve} height={260} />
              </Show>
            </div>
          </div>

          {/* Bottom layout: Left (Trades List) + Right (Trade Inspector Card) */}
          <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* Trades List (7 Cols) */}
            <div class="lg:col-span-7 glass p-5 rounded-2xl flex flex-col justify-between">
              <div class="flex items-center justify-between border-b border-white/5 pb-3">
                <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trades ({metrics().totalTrades})</span>
                <div class="flex items-center gap-2">
                  <select class="glass-select text-[8px] font-bold px-2.5 py-1.5 rounded-lg">
                    <option>All Trades</option>
                  </select>
                  <button class="px-2.5 py-1.5 bg-white/[0.02] border border-white/5 hover:bg-white/[0.04] text-[8px] font-black uppercase tracking-wider rounded-lg text-gray-400">Export</button>
                </div>
              </div>
              <div class="overflow-x-auto mt-2">
                <Show when={trades().length > 0} fallback={
                  <div class="text-center py-8 text-[10px] text-gray-600 font-bold uppercase tracking-wider">No trades — run a backtest</div>
                }>
                  <table class="w-full text-left border-collapse text-[10px]">
                    <thead>
                      <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                        <th class="py-2.5">Date & Time</th>
                        <th class="py-2.5">Instrument</th>
                        <th class="py-2.5 text-center">Type</th>
                        <th class="py-2.5 text-right font-black text-data">P&L</th>
                      </tr>
                    </thead>
                    <tbody>
                      <For each={trades()}>
                        {(t, idx) => (
                          <tr
                            onClick={() => setSelectedTradeIndex(idx())}
                            class={`border-b border-white/5 hover:bg-white/[0.01] cursor-pointer transition-colors ${
                              selectedTradeIndex() === idx() ? 'bg-primary-500/5 border-l-2 border-l-primary-500' : ''
                            }`}
                          >
                            <td class="py-2.5 text-gray-500 font-mono">{t.datetime}</td>
                            <td class="py-2.5 font-bold text-white max-w-[120px] truncate">{t.instrument}</td>
                            <td class="py-2.5 text-center">
                              <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                                t.type === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                              }`}>{t.type}</span>
                            </td>
                            <td class={`py-2.5 text-right font-black text-data ${t.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                              {t.pnl >= 0 ? '+' : ''}₹{t.pnl}
                            </td>
                          </tr>
                        )}
                      </For>
                    </tbody>
                  </table>
                </Show>
              </div>
            </div>

            {/* Trade Detail Inspector (5 Cols) */}
            <div class="lg:col-span-5 glass p-5 rounded-2xl flex flex-col justify-between">
              <Show when={trades().length > 0} fallback={
                <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">Select a trade</div>
              }>
                <div class="flex items-center justify-between border-b border-white/5 pb-3">
                  <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trade Detail</span>
                  <span class={`text-[8px] font-black uppercase tracking-wider px-2 py-0.5 rounded ${
                    selectedTrade().status === 'WIN' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                  }`}>{selectedTrade().status || '—'}</span>
                </div>
                <div class="mt-3 text-[10px] space-y-2.5">
                  <h4 class="font-black text-white text-xs">{selectedTrade().instrument}</h4>
                  <div class="grid grid-cols-2 gap-3 border-y border-white/5 py-3">
                    <div>
                      <span class="text-gray-500 block text-[8px] uppercase font-bold">Entry Time</span>
                      <span class="font-semibold text-white mt-1 block">{selectedTrade().datetime}</span>
                    </div>
                    <div>
                      <span class="text-gray-500 block text-[8px] uppercase font-bold">Exit Time</span>
                      <span class="font-semibold text-white mt-1 block">{selectedTrade().datetime}</span>
                    </div>
                    <div>
                      <span class="text-gray-500 block text-[8px] uppercase font-bold">Entry Price</span>
                      <span class="font-semibold text-white mt-1 block text-data">₹{selectedTrade().entry}</span>
                    </div>
                    <div>
                      <span class="text-gray-500 block text-[8px] uppercase font-bold">Exit Price</span>
                      <span class="font-semibold text-white mt-1 block text-data">₹{selectedTrade().exit}</span>
                    </div>
                  </div>

                  <div class="flex justify-between items-center bg-white/[0.01] p-2.5 rounded-xl border border-white/5">
                    <span class="text-gray-400 font-bold uppercase text-[8px]">Realized P&L</span>
                    <span class={`text-sm font-black text-data ${selectedTrade().pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                      {selectedTrade().pnl >= 0 ? '+' : ''}₹{selectedTrade().pnl} ({selectedTrade().pnlPct}%)
                    </span>
                  </div>
                </div>
              </Show>
            </div>
          </div>
        </div>

        {/* Right 3 columns: Config & Stats summary */}
        <div class="lg:col-span-3 space-y-6">
          {/* Backtest Configuration */}
          <div class="glass p-5 rounded-2xl space-y-4">
            <div class="flex items-center justify-between border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Backtest Configuration</span>
              <button class="text-[8px] font-black uppercase text-primary-400 hover:text-primary-300 transition-colors">Edit</button>
            </div>
            <div class="text-[10px] space-y-3.5">
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Strategy</span>
                <span class="font-black text-white uppercase tracking-wider">{config().strategy || selectedStrategy()}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Timeframe</span>
                <span class="font-black text-white text-data">{config().interval || '1 Minute'}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Instruments</span>
                <span class="font-black text-white text-data">{config().symbol || 'NIFTY'}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Period</span>
                <span class="font-black text-white text-data">{config().days_back || '90'} days</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Initial Capital</span>
                <span class="font-black text-white text-data">₹{(config().initial_capital || 250000).toLocaleString('en-IN')}</span>
              </div>
            </div>
          </div>

          {/* Performance Summary */}
          <div class="glass p-5 rounded-2xl space-y-4">
            <div class="flex items-center justify-between border-b border-white/5 pb-3">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Performance Summary</span>
            </div>
            <div class="text-[10px] space-y-3.5">
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Total Trades</span>
                <span class="font-black text-white text-data">{metrics().totalTrades}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Winning Trades</span>
                <span class="font-black text-emerald-400 text-data">{metrics().winningTrades} ({metrics().winRate}%)</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Losing Trades</span>
                <span class="font-black text-rose-500 text-data">{metrics().losingTrades} {metrics().winRate ? `(${(100 - metrics().winRate).toFixed(2)}%)` : ''}</span>
              </div>
              <Show when={btResult().trades && btResult().trades.length > 0}>
                <div class="flex justify-between items-center">
                  <span class="text-gray-500 font-bold uppercase">Avg Win</span>
                  <span class="font-black text-emerald-400 text-data">+{metrics().avgWinPct}%</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-gray-500 font-bold uppercase">Avg Loss</span>
                  <span class="font-black text-rose-500 text-data">{metrics().avgLossPct}%</span>
                </div>
              </Show>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
