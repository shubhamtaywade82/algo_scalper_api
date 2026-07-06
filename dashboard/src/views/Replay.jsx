import { createSignal, createMemo, For, Show } from 'solid-js'
import AnimatedNumber from '../components/AnimatedNumber'

export default function Replay() {
  const [isPlaying, setIsPlaying] = createSignal(false)
  const [playbackSpeed, setPlaybackSpeed] = createSignal('1x')
  const [activeTab, setActiveTab] = createSignal('trades')

  // Replay Metrics
  const metrics = {
    netPnl: 24350,
    netPnlPct: 2.48,
    totalTrades: 76,
    winRate: 63.21,
    winTrades: 48,
    profitFactor: 2.18,
    maxDrawdown: 18750,
    maxDrawdownPct: 1.87,
    avgTrade: 320.39,
    expectancy: 1639.47,
    sharpeRatio: 1.42,
    sortinoRatio: 2.31
  }

  // Events timeline mock
  const events = [
    { time: '09:00:00', text: 'Market Open', type: 'system' },
    { time: '09:05:00', text: 'Opening Range Building', type: 'strategy' },
    { time: '09:15:00', text: 'Buy Signal Generated', type: 'signal' },
    { time: '09:15:02', text: 'Order Placed', type: 'order' },
    { time: '09:15:04', text: 'Order Filled @ 134.50', type: 'order' },
    { time: '09:37:45', text: 'Exit Signal Generated', type: 'signal' },
    { time: '09:37:45', text: 'Order Placed', type: 'order' },
    { time: '09:37:47', text: 'Order Filled @ 142.80', type: 'order' }
  ]

  // Replay trades mock
  const replayTrades = [
    { id: 1, time: '03 Jun 09:15:00', type: 'BUY', inst: 'NIFTY 06 JUN 22100 CE', qty: 75, entry: 134.50, exit: 142.80, pnl: 830, pnlPct: 6.17, status: 'WIN' },
    { id: 2, time: '03 Jun 09:37:45', type: 'SELL', inst: 'NIFTY 06 JUN 22100 CE', qty: 75, entry: 134.50, exit: 142.80, pnl: 830, pnlPct: 6.17, status: 'WIN' },
    { id: 3, time: '03 Jun 10:12:00', type: 'BUY', inst: 'NIFTY 06 JUN 22150 CE', qty: 75, entry: 128.40, exit: 123.20, pnl: -390, pnlPct: -4.05, status: 'LOSS' },
    { id: 4, time: '03 Jun 10:32:30', type: 'SELL', inst: 'NIFTY 06 JUN 22150 CE', qty: 75, entry: 128.40, exit: 123.20, pnl: -390, pnlPct: -4.05, status: 'LOSS' },
    { id: 5, time: '03 Jun 11:05:00', type: 'BUY', inst: 'NIFTY 06 JUN 22200 CE', qty: 75, entry: 110.25, exit: 118.70, pnl: 635, pnlPct: 7.66, status: 'WIN' }
  ]

  // Strategy State Indicators
  const strategyState = [
    { name: 'EMA 20', val: '21,982.45' },
    { name: 'EMA 50', val: '21,945.10' },
    { name: 'RSI (14)', val: '64.25' },
    { name: 'ATR (14)', val: '32.45' },
    { name: 'Opening Range High', val: '22,010.20' },
    { name: 'Opening Range Low', val: '21,950.15' },
    { name: 'Breakout', val: 'Yes', class: 'text-emerald-400 font-bold' },
    { name: 'Position', val: 'Flat', class: 'text-gray-400 font-bold' }
  ]

  return (
    <div class="space-y-6">
      {/* Page Title Row */}
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-black text-white uppercase tracking-widest">Replay</h1>
          <p class="text-[10px] font-bold text-gray-500 uppercase tracking-widest mt-1">Replay historical market data and see how your strategies performed</p>
        </div>
        <div class="flex items-center gap-3">
          <div class="flex items-center gap-2 bg-white/[0.02] border border-white/5 rounded-2xl px-3 py-1.5 text-[9px] font-black uppercase text-gray-400">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400" />
            <span>Market: NSE</span>
            <span class="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse ml-2" />
            <span class="text-rose-400">Live: Off (Replay)</span>
          </div>
        </div>
      </div>

      {/* Control & Configuration Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Strategy</span>
            <select class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg">
              <option>ORB Breakout v1.0.0</option>
            </select>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Instrument</span>
            <select class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg font-mono">
              <option>NIFTY</option>
            </select>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Timeframe</span>
            <select class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg">
              <option>1 Minute</option>
            </select>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Date</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono">
              01 Apr 2024 - 03 Jun 2024
            </div>
          </div>
        </div>

        <div class="flex items-center gap-2.5 mt-2 md:mt-0">
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Load Data
          </button>
          <button
            onClick={() => setIsPlaying(!isPlaying())}
            class={`px-5 py-2.5 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all flex items-center gap-1.5 ${
              isPlaying() ? 'bg-amber-600 hover:bg-amber-500' : 'bg-emerald-600 hover:bg-emerald-500'
            }`}
          >
            <span>{isPlaying() ? '⏸' : '▶'}</span> {isPlaying() ? 'Pause Replay' : 'Start Replay'}
          </button>
        </div>
      </div>

      {/* Replay Metrics Row */}
      <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-4">
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Net P&L</span>
          <div class="text-base font-black text-emerald-400 text-data">+₹{metrics.netPnl.toLocaleString('en-IN')}</div>
          <span class="text-[8px] font-bold text-emerald-500 mt-1 block">+{metrics.netPnlPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Trades</span>
          <div class="text-base font-black text-white text-data">{metrics.totalTrades}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Buy/Sell logs</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Win Rate</span>
          <div class="text-base font-black text-white text-data">{metrics.winRate}%</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">({metrics.winTrades} / {metrics.totalTrades})</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Profit Factor</span>
          <div class="text-base font-black text-white text-data">{metrics.profitFactor}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Gross PnL Ratio</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Max Drawdown</span>
          <div class="text-base font-black text-rose-500 text-data">₹{metrics.maxDrawdown.toLocaleString('en-IN')}</div>
          <span class="text-[8px] font-bold text-rose-500 mt-1 block">{metrics.maxDrawdownPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Avg Trade</span>
          <div class="text-base font-black text-emerald-400 text-data">+₹{metrics.avgTrade}</div>
          <span class="text-[8px] font-bold text-emerald-500 mt-1 block">Wins & Losses</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Expectancy</span>
          <div class="text-base font-black text-white text-data">₹{metrics.expectancy.toFixed(0)}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Per Position</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Sharpe Ratio</span>
          <div class="text-base font-black text-white text-data">{metrics.sharpeRatio}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Sortino: {metrics.sortinoRatio}</span>
        </div>
      </div>

      {/* WorkSpace Content Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column (8 units): Replay Candlestick Chart */}
        <div class="lg:col-span-8 space-y-6">
          <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[360px]">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <div>
                <span class="font-black text-white">NIFTY - 1 - NSE</span>
                <span class="text-gray-500 font-mono ml-2">O 22,032.40 H 22,033.15 L 22,025.80 C 22,029.05 -2.85 (-0.01%)</span>
              </div>
              <div class="text-emerald-400 font-bold uppercase tracking-wider">Volume SMA 9</div>
            </div>
            {/* Mock Candlestick Chart View */}
            <div class="flex-1 py-4 relative flex items-center justify-center">
              <svg viewBox="0 0 600 200" class="w-full h-full">
                {/* Grid Lines */}
                <line x1="0" y1="50" x2="600" y2="50" stroke="rgba(255,255,255,0.02)" />
                <line x1="0" y1="100" x2="600" y2="100" stroke="rgba(255,255,255,0.02)" />
                <line x1="0" y1="150" x2="600" y2="150" stroke="rgba(255,255,255,0.02)" />

                {/* Candles */}
                <g fill="rgb(16, 185, 129)" stroke="rgb(16, 185, 129)">
                  <line x1="50" y1="130" x2="50" y2="70" stroke-width="1" />
                  <rect x="46" y="80" width="8" height="40" />
                </g>
                <g fill="rgb(239, 68, 68)" stroke="rgb(239, 68, 68)">
                  <line x1="100" y1="140" x2="100" y2="90" stroke-width="1" />
                  <rect x="96" y="100" width="8" height="30" />
                </g>
                {/* Armed Buy Call Tag */}
                <g transform="translate(140, 60)">
                  <rect x="0" y="0" width="60" height="18" rx="4" fill="rgb(16, 185, 129)" />
                  <text x="30" y="12" fill="white" font-size="8" font-weight="bold" text-anchor="middle">BUY CALL</text>
                </g>
                <g fill="rgb(16, 185, 129)" stroke="rgb(16, 185, 129)">
                  <line x1="170" y1="110" x2="170" y2="50" stroke-width="1" />
                  <rect x="166" y="60" width="8" height="40" />
                </g>
                {/* Exit Tag */}
                <g transform="translate(290, 40)">
                  <rect x="0" y="0" width="36" height="18" rx="4" fill="rgb(139, 92, 246)" />
                  <text x="18" y="12" fill="white" font-size="8" font-weight="bold" text-anchor="middle">EXIT</text>
                </g>
                <g fill="rgb(239, 68, 68)" stroke="rgb(239, 68, 68)">
                  <line x1="310" y1="150" x2="310" y2="70" stroke-width="1" />
                  <rect x="306" y="80" width="8" height="50" />
                </g>
              </svg>
            </div>
            {/* Playback controller toolbar */}
            <div class="flex items-center justify-between border-t border-white/5 pt-3">
              <div class="flex items-center gap-3">
                <button class="p-2 bg-white/5 rounded-lg text-gray-300 hover:text-white transition-all text-xs font-bold">⏮</button>
                <button
                  onClick={() => setIsPlaying(!isPlaying())}
                  class="w-8 h-8 rounded-full bg-primary-600 hover:bg-primary-500 text-white flex items-center justify-center transition-all text-xs"
                >
                  {isPlaying() ? '⏸' : '▶'}
                </button>
                <button class="p-2 bg-white/5 rounded-lg text-gray-300 hover:text-white transition-all text-xs font-bold">⏭</button>
                <select
                  value={playbackSpeed()}
                  onChange={(e) => setPlaybackSpeed(e.target.value)}
                  class="glass-select text-[9px] px-2.5 py-1.5 rounded-lg"
                >
                  <option>0.5x</option>
                  <option>1x</option>
                  <option>2x</option>
                  <option>5x</option>
                </select>
              </div>
              <div class="flex-1 mx-6 flex items-center gap-2">
                <input type="range" class="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer accent-primary-500" value="40" />
                <span class="text-[8px] font-mono text-gray-500">09:15:00</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right Column (4 units): Inspector & Config */}
        <div class="lg:col-span-4 space-y-6">
          {/* Trade Information */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trade Information</span>
              <span class="text-[8px] font-black uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded">WIN</span>
            </div>
            <div class="text-[10px] space-y-2.5">
              <div class="flex justify-between border-b border-white/5 pb-2">
                <span class="text-gray-500 uppercase font-bold">Signal</span>
                <span class="font-black text-emerald-400">BUY CALL</span>
              </div>
              <div class="flex justify-between border-b border-white/5 pb-2">
                <span class="text-gray-500 uppercase font-bold">Instrument</span>
                <span class="font-black text-white font-mono">NIFTY 05 JUN 22100 CE</span>
              </div>
              <div class="flex justify-between border-b border-white/5 pb-2">
                <span class="text-gray-500 uppercase font-bold">P&L (Realized)</span>
                <span class="font-black text-emerald-400 text-data">+₹830.00 (+6.17%)</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500 uppercase font-bold">Holding Time</span>
                <span class="font-black text-white text-data">22m 45s</span>
              </div>
            </div>
          </div>

          {/* Strategy State */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Strategy State (At 09:15:00)</span>
            </div>
            <div class="grid grid-cols-2 gap-4 text-[10px]">
              <For each={strategyState}>
                {(st) => (
                  <div>
                    <span class="text-gray-500 block text-[8px] uppercase font-bold">{st.name}</span>
                    <span class={`font-black text-white text-data mt-1 block ${st.class || ''}`}>{st.val}</span>
                  </div>
                )}
              </For>
            </div>
          </div>
        </div>
      </div>

      {/* Bottom Events Timeline & Tab Details */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Events Timeline (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Events Timeline</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">Jump to Event</button>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[160px] mt-2 divide-y divide-white/5">
            <For each={events}>
              {(e) => (
                <div class="py-2.5 flex items-start gap-3 text-[10px]">
                  <span class="text-gray-500 font-mono mt-0.5">{e.time}</span>
                  <div class="flex-1">
                    <p class="text-white font-bold leading-snug">{e.text}</p>
                    <span class={`text-[7px] font-black uppercase mt-1 inline-block ${
                      e.type === 'signal' ? 'text-emerald-400' : e.type === 'order' ? 'text-sky-400' : 'text-gray-500'
                    }`}>{e.type}</span>
                  </div>
                </div>
              )}
            </For>
          </div>
        </div>

        {/* Tab logs & trades review (8 cols) */}
        <div class="lg:col-span-8 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <div class="flex items-center gap-1 text-[10px] font-black uppercase">
              <button
                onClick={() => setActiveTab('trades')}
                class={`px-3 py-1.5 rounded-lg ${activeTab() === 'trades' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500'}`}
              >
                Trades
              </button>
              <button
                onClick={() => setActiveTab('positions')}
                class={`px-3 py-1.5 rounded-lg ${activeTab() === 'positions' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500'}`}
              >
                Positions
              </button>
            </div>
            <span class="text-[8px] font-mono text-gray-500">Showing 1 to 5 of 76 trades</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                  <th class="py-2.5">Time</th>
                  <th class="py-2.5">Instrument</th>
                  <th class="py-2.5 text-center">Type</th>
                  <th class="py-2.5 text-right font-black text-data">P&L</th>
                  <th class="py-2.5 text-right font-black">Status</th>
                </tr>
              </thead>
              <tbody>
                <For each={replayTrades}>
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
                        {t.pnl >= 0 ? '+' : ''}₹{t.pnl} ({t.pnlPct}%)
                      </td>
                      <td class="py-2.5 text-right font-black">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          t.status === 'WIN' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                        }`}>{t.status}</span>
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
