import { Show, createMemo } from 'solid-js'
import AnimatedNumber from '../AnimatedNumber'

export default function BacktestPreview(props) {
  const results = () => props.results() || {
    net_profit: 0,
    total_trades: 0,
    win_rate: 0,
    profit_factor: 0,
    max_drawdown: 0
  }

  const isProfit = () => results().net_profit >= 0

  return (
    <div class="glass border border-white/5 rounded-2xl overflow-hidden flex flex-col h-full bg-[#0d1117]/30">
      {/* Header */}
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5 bg-white/[0.01]">
        <h4 class="text-[9px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400" />
          Backtest Performance
        </h4>
        <span class="text-[9px] font-bold text-gray-500 font-mono">
          {props.dateRange || '01 May 2024 - 31 May 2024'}
        </span>
      </div>

      {/* Metrics Row */}
      <div class="grid grid-cols-5 divide-x divide-white/5 border-b border-white/5 bg-white/[0.005]">
        <div class="p-3 text-center">
          <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Net Profit</span>
          <span class={`text-[11px] font-black text-data ${isProfit() ? 'text-emerald-400' : 'text-rose-400'}`}>
            ₹<AnimatedNumber value={results().net_profit} decimals={0} />
          </span>
          <span class="text-[6px] text-emerald-500 block font-bold mt-0.5">+12.43%</span>
        </div>
        <div class="p-3 text-center">
          <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Total Trades</span>
          <span class="text-[11px] font-black text-white text-data">
            <AnimatedNumber value={results().total_trades} decimals={0} />
          </span>
        </div>
        <div class="p-3 text-center">
          <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Win Rate</span>
          <span class="text-[11px] font-black text-white text-data">
            <AnimatedNumber value={results().win_rate} decimals={1} />%
          </span>
        </div>
        <div class="p-3 text-center">
          <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Profit Factor</span>
          <span class="text-[11px] font-black text-white text-data">
            <AnimatedNumber value={results().profit_factor} decimals={2} />
          </span>
        </div>
        <div class="p-3 text-center">
          <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Max Drawdown</span>
          <span class="text-[11px] font-black text-rose-500 text-data">
            ₹<AnimatedNumber value={results().max_drawdown} decimals={0} />
          </span>
          <span class="text-[6px] text-rose-500 block font-bold mt-0.5">2.31%</span>
        </div>
      </div>

      {/* SVG Equity Chart */}
      <div class="flex-1 p-4 flex flex-col justify-between min-h-0">
        <div class="flex items-center gap-4 text-[7px] font-black uppercase text-gray-500 mb-2">
          <div class="flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500" />
            <span>Equity Curve</span>
          </div>
          <div class="flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-gray-600" />
            <span>Buy & Hold</span>
          </div>
        </div>

        <div class="flex-1 w-full relative min-h-0">
          <svg viewBox="0 0 300 100" class="w-full h-full overflow-visible" preserveAspectRatio="none">
            <defs>
              <linearGradient id="chartGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#10b981" stop-opacity="0.15" />
                <stop offset="100%" stop-color="#10b981" stop-opacity="0.0" />
              </linearGradient>
            </defs>

            {/* Grid Lines */}
            <line x1="0" y1="20" x2="300" y2="20" stroke="rgba(255,255,255,0.02)" stroke-width="1" />
            <line x1="0" y1="50" x2="300" y2="50" stroke="rgba(255,255,255,0.02)" stroke-width="1" />
            <line x1="0" y1="80" x2="300" y2="80" stroke="rgba(255,255,255,0.02)" stroke-width="1" />

            {/* Buy and Hold Line */}
            <path d="M 0,80 L 50,75 L 100,78 L 150,70 L 200,65 L 250,68 L 300,55" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1" />

            {/* Equity Curve Gradient Fill */}
            <path d="M 0,80 L 50,70 L 100,60 L 150,45 L 200,50 L 250,30 L 300,20 L 300,100 L 0,100 Z" fill="url(#chartGradient)" />

            {/* Equity Curve Line */}
            <path d="M 0,80 L 50,70 L 100,60 L 150,45 L 200,50 L 250,30 L 300,20" fill="none" stroke="#10b981" stroke-width="1.5" />
          </svg>
        </div>

        {/* X Axis Labels */}
        <div class="flex justify-between text-[7px] text-gray-600 font-mono mt-2 font-bold uppercase">
          <span>May 1</span>
          <span>May 8</span>
          <span>May 15</span>
          <span>May 22</span>
          <span>May 29</span>
        </div>
      </div>
    </div>
  )
}
