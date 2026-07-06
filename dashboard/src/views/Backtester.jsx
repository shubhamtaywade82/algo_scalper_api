import { createSignal, createMemo, For, Show } from 'solid-js'
import AnimatedNumber from '../components/AnimatedNumber'

export default function Backtester() {
  const [selectedStrategy, setSelectedStrategy] = createSignal('ORB Breakout')
  const [activeTab, setActiveTab] = createSignal('overview')
  const [selectedTradeIndex, setSelectedTradeIndex] = createSignal(0)

  // Saved configs list
  const savedConfigs = [
    { id: '1', label: 'ORB Breakout - NIFTY 1m (v1)' },
    { id: '2', label: 'Supertrend Scalper - BANKNIFTY 5m' },
    { id: '3', label: 'EMA Cross - SENSEX 15m' }
  ]

  // KPI Metrics
  const metrics = {
    netProfit: 124560,
    netProfitPct: 12.46,
    totalReturn: 12.46,
    annualizedReturn: 28.73,
    winRate: 63.21,
    winTrades: 48,
    totalTrades: 76,
    profitFactor: 2.18,
    maxDrawdown: 18750,
    maxDrawdownPct: 1.87,
    expectancy: 1639.47
  }

  // Trades List Mock
  const trades = [
    { id: 1, datetime: '02 Apr 09:25', instrument: 'NIFTY 04 APR 22100 CE', type: 'BUY', entry: 134.50, exit: 142.80, pnl: 830, pnlPct: 6.17, status: 'WIN' },
    { id: 2, datetime: '02 Apr 10:03', instrument: 'NIFTY 04 APR 22100 CE', type: 'BUY', entry: 142.10, exit: 137.60, pnl: -450, pnlPct: -3.17, status: 'LOSS' },
    { id: 3, datetime: '02 Apr 10:48', instrument: 'NIFTY 04 APR 22100 CE', type: 'BUY', entry: 103.20, exit: 111.90, pnl: 870, pnlPct: 8.43, status: 'WIN' },
    { id: 4, datetime: '02 Apr 11:32', instrument: 'NIFTY 04 APR 22200 PE', type: 'SELL', entry: 95.75, exit: 91.20, pnl: 455, pnlPct: 4.75, status: 'WIN' },
    { id: 5, datetime: '02 Apr 13:05', instrument: 'NIFTY 04 APR 22100 CE', type: 'BUY', entry: 128.60, exit: 123.40, pnl: -520, pnlPct: -4.04, status: 'LOSS' },
    { id: 6, datetime: '03 Apr 09:24', instrument: 'NIFTY 05 APR 22150 CE', type: 'BUY', entry: 115.35, exit: 128.10, pnl: 1275, pnlPct: 11.07, status: 'WIN' },
    { id: 7, datetime: '03 Apr 10:12', instrument: 'NIFTY 05 APR 22150 CE', type: 'BUY', entry: 128.40, exit: 133.90, pnl: 550, pnlPct: 4.28, status: 'WIN' }
  ]

  const selectedTrade = () => trades[selectedTradeIndex()] || trades[0]

  return (
    <div class="space-y-6">

      {/* Action Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex items-center gap-3">
          <select class="glass-select text-xs px-3 py-2 rounded-xl">
            <For each={savedConfigs}>
              {(cfg) => <option value={cfg.id}>{cfg.label}</option>}
            </For>
          </select>
          <button class="p-2 border border-white/5 rounded-xl text-gray-500 hover:text-white transition-colors">
            ★
          </button>
        </div>
        <div class="flex items-center gap-2.5">
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Save Report
          </button>
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Share
          </button>
          <button class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-[0_0_15px_rgba(59,130,246,0.25)] hover:shadow-[0_0_20px_rgba(59,130,246,0.45)] transition-all flex items-center gap-1.5">
            <span>▶</span> Run Backtest
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
          <div class="text-lg font-black text-emerald-400 text-data">₹{metrics.netProfit.toLocaleString('en-IN')}</div>
          <span class="text-[9px] font-bold text-emerald-500 mt-1 block">+{metrics.netProfitPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Return</span>
          <div class="text-lg font-black text-white text-data">{metrics.totalReturn}%</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">Annualized: {metrics.annualizedReturn}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Win Rate</span>
          <div class="text-lg font-black text-white text-data">{metrics.winRate}%</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">({metrics.winTrades} / {metrics.totalTrades})</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Profit Factor</span>
          <div class="text-lg font-black text-white text-data">{metrics.profitFactor}</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">Gross Profit/Loss</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Max Drawdown</span>
          <div class="text-lg font-black text-rose-500 text-data">₹{metrics.maxDrawdown.toLocaleString('en-IN')}</div>
          <span class="text-[9px] font-bold text-rose-500 mt-1 block">{metrics.maxDrawdownPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Trades</span>
          <div class="text-lg font-black text-white text-data">{metrics.totalTrades}</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">Buy: 40 / Sell: 36</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest block mb-1">Expectancy</span>
          <div class="text-lg font-black text-white text-data">₹{metrics.expectancy}</div>
          <span class="text-[9px] font-bold text-gray-500 mt-1 block">Per Trade</span>
        </div>
      </div>

      {/* Main Workspace Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left 9 columns: Chart & Table */}
        <div class="lg:col-span-9 space-y-6">
          {/* Main Backtest Chart */}
          <div class="glass p-5 rounded-2xl h-[340px] flex flex-col justify-between">
            <div class="flex items-center justify-between border-b border-white/5 pb-3">
              <div>
                <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest block">Equity Curve</span>
                <span class="text-[8px] font-bold text-gray-600 mt-0.5 block">Initial Capital: ₹10,00,000</span>
              </div>
              <div class="flex items-center gap-3 text-[9px] font-bold">
                <span class="text-emerald-400 flex items-center gap-1.5"><span class="w-2 h-2 rounded bg-emerald-500" /> Equity</span>
                <span class="text-gray-500 flex items-center gap-1.5"><span class="w-2 h-2 rounded bg-gray-500" /> Buy & Hold (Nifty)</span>
              </div>
            </div>
            <div class="flex-1 py-4 relative">
              <svg viewBox="0 0 500 150" class="w-full h-full">
                <defs>
                  <linearGradient id="backtestGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="rgb(16, 185, 129)" stop-opacity="0.15"/>
                    <stop offset="100%" stop-color="rgb(16, 185, 129)" stop-opacity="0.0"/>
                  </linearGradient>
                </defs>
                {/* Buy & Hold line */}
                <path d="M 10 110 L 100 115 L 200 95 L 300 100 L 400 90 L 490 85" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1.5" stroke-dasharray="3,3" />
                {/* Backtest Equity curve */}
                <path d="M 10 110 Q 50 100 100 80 T 200 85 T 300 60 T 400 55 T 490 35" fill="none" stroke="rgb(16, 185, 129)" stroke-width="2.5" />
                <path d="M 10 110 Q 50 100 100 80 T 200 85 T 300 60 T 400 55 T 490 35 L 490 145 L 10 145 Z" fill="url(#backtestGrad)" />
              </svg>
              <div class="flex justify-between text-[8px] text-gray-600 font-black uppercase px-2 mt-1">
                <span>01 Apr</span>
                <span>01 May</span>
                <span>01 Jun</span>
                <span>01 Jul</span>
                <span>31 Aug</span>
              </div>
            </div>
          </div>

          {/* Bottom layout: Left (Trades List) + Right (Trade Inspector Card) */}
          <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* Trades List (7 Cols) */}
            <div class="lg:col-span-7 glass p-5 rounded-2xl flex flex-col justify-between">
              <div class="flex items-center justify-between border-b border-white/5 pb-3">
                <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trades ({metrics.totalTrades})</span>
                <div class="flex items-center gap-2">
                  <select class="glass-select text-[8px] font-bold px-2.5 py-1.5 rounded-lg">
                    <option>All Trades</option>
                  </select>
                  <button class="px-2.5 py-1.5 bg-white/[0.02] border border-white/5 hover:bg-white/[0.04] text-[8px] font-black uppercase tracking-wider rounded-lg text-gray-400">Export</button>
                </div>
              </div>
              <div class="overflow-x-auto mt-2">
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
                    <For each={trades}>
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
              </div>
            </div>

            {/* Trade Detail Inspector (5 Cols) */}
            <div class="lg:col-span-5 glass p-5 rounded-2xl flex flex-col justify-between">
              <div class="flex items-center justify-between border-b border-white/5 pb-3">
                <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trade Detail</span>
                <span class="text-[8px] font-black uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded">WIN</span>
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
                    <span class="font-semibold text-white mt-1 block">02 Apr 09:37</span>
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

                {/* Price Chart Preview (Mock Candle Stick Chart) */}
                <div class="h-[120px] bg-black/20 rounded-xl p-3 border border-white/5 flex flex-col justify-between">
                  <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest">Price Chart (1m)</span>
                  <div class="flex-1 flex items-end justify-between gap-1 py-2">
                    {/* Simulated Candlesticks */}
                    <div class="w-2 bg-rose-500 h-10 relative flex items-center justify-center"><div class="absolute w-0.5 h-14 bg-rose-500" /></div>
                    <div class="w-2 bg-emerald-500 h-12 relative flex items-center justify-center"><div class="absolute w-0.5 h-16 bg-emerald-500" /></div>
                    <div class="w-2 bg-emerald-500 h-16 relative flex items-center justify-center"><div class="absolute w-0.5 h-20 bg-emerald-500" /></div>
                    <div class="w-2 bg-emerald-500 h-8 relative flex items-center justify-center"><div class="absolute w-0.5 h-12 bg-emerald-500" /></div>
                    <div class="w-2 bg-rose-500 h-14 relative flex items-center justify-center"><div class="absolute w-0.5 h-18 bg-rose-500" /></div>
                    <div class="w-2 bg-emerald-500 h-10 relative flex items-center justify-center"><div class="absolute w-0.5 h-14 bg-emerald-500" /></div>
                  </div>
                </div>
              </div>
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
                <span class="font-black text-white uppercase tracking-wider">{selectedStrategy()}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Timeframe</span>
                <span class="font-black text-white text-data">1 Minute</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Instruments</span>
                <span class="font-black text-white text-data">NIFTY</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Date Range</span>
                <span class="font-black text-white text-data">01 Apr - 31 Aug 2024</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Initial Capital</span>
                <span class="font-black text-white text-data">₹10,00,000</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Slippage</span>
                <span class="font-black text-white text-data">₹1.00</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Brokerage</span>
                <span class="font-black text-white text-data">₹20 per order</span>
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
                <span class="font-black text-white text-data">76</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Winning Trades</span>
                <span class="font-black text-emerald-400 text-data">48 (63.21%)</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Losing Trades</span>
                <span class="font-black text-rose-500 text-data">28 (36.79%)</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Largest Win</span>
                <span class="font-black text-emerald-400 text-data">+₹8,450</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Largest Loss</span>
                <span class="font-black text-rose-500 text-data">-₹4,250</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Sharpe Ratio</span>
                <span class="font-black text-white text-data">1.42</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Sortino Ratio</span>
                <span class="font-black text-white text-data">2.31</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-gray-500 font-bold uppercase">Calmar Ratio</span>
                <span class="font-black text-white text-data">1.53</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
