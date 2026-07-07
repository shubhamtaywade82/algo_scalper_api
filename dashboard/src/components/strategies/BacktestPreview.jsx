import { Show, For, createMemo } from 'solid-js'
import AnimatedNumber from '../AnimatedNumber'

export default function BacktestPreview(props) {
  const results = () => props.results() || {}

  const hasResults = () => {
    const r = results()
    // Checks if we have metrics or equity curve or signals
    return (
      r &&
      (r.netProfit !== undefined ||
        r.net_profit !== undefined ||
        (r.totalTrades && r.totalTrades > 0) ||
        (r.total_trades && r.total_trades > 0) ||
        (r.equity_curve && r.equity_curve.length > 0))
    )
  }

  const netProfit = () => {
    const r = results()
    return r.netProfit !== undefined ? r.netProfit : (r.net_profit !== undefined ? r.net_profit : 0)
  }

  const isProfit = () => netProfit() >= 0

  const totalTrades = () => {
    const r = results()
    return r.totalTrades !== undefined ? r.totalTrades : (r.total_trades !== undefined ? r.total_trades : 0)
  }

  const winRate = () => {
    const r = results()
    return r.winRate !== undefined ? r.winRate : (r.win_rate !== undefined ? r.win_rate : 0)
  }

  const profitFactor = () => {
    const r = results()
    return r.profitFactor !== undefined ? r.profitFactor : (r.profit_factor !== undefined ? r.profit_factor : 0)
  }

  const maxDrawdown = () => {
    const r = results()
    return r.maxDrawdown !== undefined ? r.maxDrawdown : (r.max_drawdown !== undefined ? r.max_drawdown : 0)
  }

  const netProfitPct = () => {
    const r = results()
    const pct = r.netProfitPct !== undefined ? r.netProfitPct : (r.net_profit_pct !== undefined ? r.net_profit_pct : null)
    if (pct == null) return '—'
    return `${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%`
  }

  const maxDrawdownPct = () => {
    const r = results()
    const pct = r.maxDrawdownPct !== undefined ? r.maxDrawdownPct : (r.max_drawdown_pct !== undefined ? r.max_drawdown_pct : null)
    if (pct == null) return '—'
    return `${pct.toFixed(2)}%`
  }

  const dateRange = () => {
    if (props.dateRange) return props.dateRange
    const r = results()
    if (r.config && r.config.days_back) {
      return `Last ${r.config.days_back} Days`
    }
    if (r.ran_at) {
      return `Validated: ${new Date(r.ran_at).toLocaleDateString()}`
    }
    return '—'
  }

  const equityCurvePaths = createMemo(() => {
    const curve = results().equity_curve || []
    if (curve.length < 2) return { line: '', fill: '' }

    const equities = curve.map(d => d.equity)
    const maxEq = Math.max(...equities)
    const minEq = Math.min(...equities)
    const range = maxEq - minEq || 1

    const points = curve.map((d, i) => {
      const x = (i / (curve.length - 1)) * 300
      const y = 80 - ((d.equity - minEq) / range) * 60
      return { x, y }
    })

    const linePath = `M ${points.map(p => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' L ')}`
    const fillPath = `${linePath} L 300,100 L 0,100 Z`

    return { line: linePath, fill: fillPath }
  })

  const baselineY = createMemo(() => {
    const curve = results().equity_curve || []
    if (curve.length === 0) return 80
    const equities = curve.map(d => d.equity)
    const maxEq = Math.max(...equities)
    const minEq = Math.min(...equities)
    const range = maxEq - minEq || 1
    const firstEq = equities[0]
    return 80 - ((firstEq - minEq) / range) * 60
  })

  const xAxisLabels = createMemo(() => {
    const curve = results().equity_curve || []
    if (curve.length < 2) return ['Start', 'Mid', 'End']
    const formatTime = (t) => {
      const d = new Date(t * 1000)
      return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
    }
    const start = formatTime(curve[0].time)
    const mid = formatTime(curve[Math.floor(curve.length / 2)].time)
    const end = formatTime(curve[curve.length - 1].time)
    return [start, mid, end]
  })

  return (
    <div class="glass border border-white/5 rounded-2xl overflow-hidden flex flex-col h-full bg-[#0d1117]/30">
      {/* Header */}
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5 bg-white/[0.01]">
        <h4 class="text-[9px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-1.5">
          <span class={`w-1.5 h-1.5 rounded-full ${hasResults() ? 'bg-emerald-400' : 'bg-gray-500'}`} />
          Backtest Performance
        </h4>
        <span class="text-[9px] font-bold text-gray-500 font-mono">
          {dateRange()}
        </span>
      </div>

      <Show when={hasResults()} fallback={
        <div class="flex-1 flex flex-col items-center justify-center py-16 px-4 text-center">
          <span class="text-xl mb-2">📊</span>
          <h4 class="text-[9px] font-black text-gray-400 uppercase tracking-widest mb-1">No Backtest Data</h4>
          <p class="text-[8px] text-gray-500 max-w-[200px] leading-relaxed">
            Run a backtest or strategy validation to see performance preview.
          </p>
        </div>
      }>
        {/* Metrics Row */}
        <div class="grid grid-cols-5 divide-x divide-white/5 border-b border-white/5 bg-white/[0.005]">
          <div class="p-3 text-center">
            <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Net Profit</span>
            <span class={`text-[11px] font-black text-data ${isProfit() ? 'text-emerald-400' : 'text-rose-400'}`}>
              ₹<AnimatedNumber value={netProfit()} decimals={0} />
            </span>
            <span class={`text-[6px] block font-bold mt-0.5 ${netProfitPct().startsWith('+') ? 'text-emerald-500' : 'text-rose-500'}`}>
              {netProfitPct()}
            </span>
          </div>
          <div class="p-3 text-center">
            <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Total Trades</span>
            <span class="text-[11px] font-black text-white text-data">
              <AnimatedNumber value={totalTrades()} decimals={0} />
            </span>
          </div>
          <div class="p-3 text-center">
            <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Win Rate</span>
            <span class="text-[11px] font-black text-white text-data">
              <AnimatedNumber value={winRate()} decimals={1} />%
            </span>
          </div>
          <div class="p-3 text-center">
            <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Profit Factor</span>
            <span class="text-[11px] font-black text-white text-data">
              <AnimatedNumber value={profitFactor()} decimals={2} />
            </span>
          </div>
          <div class="p-3 text-center">
            <span class="text-[7px] font-black text-gray-500 uppercase tracking-wider block mb-1">Max Drawdown</span>
            <span class="text-[11px] font-black text-rose-500 text-data">
              ₹<AnimatedNumber value={maxDrawdown()} decimals={0} />
            </span>
            <span class="text-[6px] text-rose-500 block font-bold mt-0.5">{maxDrawdownPct()}</span>
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
              <span>Baseline</span>
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

              {/* Baseline (Buy & Hold / Starting Equity) */}
              <path d={`M 0,${baselineY()} L 300,${baselineY()}`} fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1" stroke-dasharray="2 2" />

              {/* Equity Curve Gradient Fill */}
              <Show when={equityCurvePaths().fill}>
                <path d={equityCurvePaths().fill} fill="url(#chartGradient)" />
              </Show>

              {/* Equity Curve Line */}
              <Show when={equityCurvePaths().line}>
                <path d={equityCurvePaths().line} fill="none" stroke="#10b981" stroke-width="1.5" />
              </Show>
            </svg>
          </div>

          {/* X Axis Labels */}
          <div class="flex justify-between text-[7px] text-gray-600 font-mono mt-2 font-bold uppercase">
            <span>{xAxisLabels()[0]}</span>
            <span>{xAxisLabels()[1]}</span>
            <span>{xAxisLabels()[2]}</span>
          </div>
        </div>
      </Show>
    </div>
  )
}
