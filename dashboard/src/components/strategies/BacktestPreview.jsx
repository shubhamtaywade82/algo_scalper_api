import { Show, createMemo } from 'solid-js'

export default function BacktestPreview(props) {
  const hasResults = createMemo(() => {
    const r = props.results()
    return r && typeof r.net_profit === 'number'
  })

  const profitColor = createMemo(() => {
    const r = props.results()
    if (!r) return 'text-gray-400'
    return r.net_profit >= 0 ? 'text-emerald-500' : 'text-rose-500'
  })

  const winRateColor = createMemo(() => {
    const r = props.results()
    if (!r) return 'text-gray-400'
    return r.win_rate >= 50 ? 'text-emerald-500' : 'text-amber-500'
  })

  const pfColor = createMemo(() => {
    const r = props.results()
    if (!r) return 'text-gray-400'
    return r.profit_factor >= 1.5 ? 'text-emerald-500' : 'text-amber-500'
  })

  // Generate sample equity curve points
  const equityPoints = createMemo(() => {
    const points = [
      0, 8, 5, 18, 25, 20, 35, 42, 38, 50,
      55, 48, 60, 68, 72, 65, 78, 85, 82, 92,
    ]
    const maxVal = Math.max(...points)
    const width = 560
    const height = 140
    const stepX = width / (points.length - 1)
    return points.map((v, i) => ({
      x: 20 + i * stepX,
      y: 20 + height - (v / maxVal) * height,
    }))
  })

  const holdPoints = createMemo(() => {
    const points = [
      0, 5, 10, 12, 18, 22, 20, 28, 32, 35,
      38, 40, 42, 45, 48, 50, 52, 55, 58, 60,
    ]
    const maxVal = 92
    const width = 560
    const height = 140
    const stepX = width / (points.length - 1)
    return points.map((v, i) => ({
      x: 20 + i * stepX,
      y: 20 + height - (v / maxVal) * height,
    }))
  })

  const polylineStr = createMemo(() => equityPoints().map(p => `${p.x},${p.y}`).join(' '))
  const holdLineStr = createMemo(() => holdPoints().map(p => `${p.x},${p.y}`).join(' '))

  const polygonStr = createMemo(() => {
    const pts = equityPoints()
    if (pts.length === 0) return ''
    const first = pts[0]
    const last = pts[pts.length - 1]
    return `${pts.map(p => `${p.x},${p.y}`).join(' ')} ${last.x},170 ${first.x},170`
  })

  function formatCurrency(val) {
    if (val == null) return '—'
    const sign = val >= 0 ? '+' : ''
    return `${sign}₹${Math.abs(val).toLocaleString('en-IN')}`
  }

  return (
    <div class="flex flex-col gap-4 h-full">
      <Show
        when={hasResults()}
        fallback={
          <div class="flex items-center justify-center h-full text-gray-600 text-xs">
            <div class="text-center">
              <svg class="w-10 h-10 mx-auto mb-2 text-gray-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M3 3v18h18" stroke-linecap="round" stroke-linejoin="round" />
                <path d="M7 16l4-4 4 2 5-6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <p class="font-bold">No backtest data</p>
              <p class="text-[10px] mt-1 text-gray-700">Run a backtest to see results</p>
            </div>
          </div>
        }
      >
        {/* Metric Cards Row */}
        <div class="grid grid-cols-5 gap-2">
          {/* Net Profit */}
          <div class="bg-white/5 rounded-xl px-3 py-2.5 border border-white/5">
            <div class="text-[9px] font-black text-gray-600 uppercase tracking-widest mb-1">Net Profit</div>
            <div class={`text-sm font-black text-data ${profitColor()}`}>
              {formatCurrency(props.results()?.net_profit)}
            </div>
          </div>

          {/* Total Trades */}
          <div class="bg-white/5 rounded-xl px-3 py-2.5 border border-white/5">
            <div class="text-[9px] font-black text-gray-600 uppercase tracking-widest mb-1">Total Trades</div>
            <div class="text-sm font-black text-data text-white">
              {props.results()?.total_trades ?? '—'}
            </div>
          </div>

          {/* Win Rate */}
          <div class="bg-white/5 rounded-xl px-3 py-2.5 border border-white/5">
            <div class="text-[9px] font-black text-gray-600 uppercase tracking-widest mb-1">Win Rate</div>
            <div class={`text-sm font-black text-data ${winRateColor()}`}>
              {props.results()?.win_rate != null ? `${props.results().win_rate}%` : '—'}
            </div>
          </div>

          {/* Profit Factor */}
          <div class="bg-white/5 rounded-xl px-3 py-2.5 border border-white/5">
            <div class="text-[9px] font-black text-gray-600 uppercase tracking-widest mb-1">Profit Factor</div>
            <div class={`text-sm font-black text-data ${pfColor()}`}>
              {props.results()?.profit_factor ?? '—'}
            </div>
          </div>

          {/* Max Drawdown */}
          <div class="bg-white/5 rounded-xl px-3 py-2.5 border border-white/5">
            <div class="text-[9px] font-black text-gray-600 uppercase tracking-widest mb-1">Max Drawdown</div>
            <div class="text-sm font-black text-data text-rose-500">
              {props.results()?.max_drawdown != null ? `${props.results().max_drawdown}%` : '—'}
            </div>
          </div>
        </div>

        {/* Equity Curve Chart */}
        <div class="flex-1 bg-white/[0.02] rounded-xl border border-white/5 p-3 min-h-0">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-4">
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-0.5 bg-primary-500 rounded-full inline-block" />
                <span class="text-[10px] font-bold text-gray-500">Equity Curve</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-0.5 bg-gray-600 rounded-full inline-block" style="border-top: 1px dashed" />
                <span class="text-[10px] font-bold text-gray-600">Buy & Hold</span>
              </div>
            </div>
            <Show when={props.dateRange}>
              <span class="text-[10px] text-gray-600 font-bold">{props.dateRange}</span>
            </Show>
          </div>

          <svg viewBox="0 0 600 180" class="w-full" style="max-height: 140px">
            <defs>
              <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="rgba(59,130,246,0.3)" />
                <stop offset="100%" stop-color="rgba(59,130,246,0)" />
              </linearGradient>
            </defs>

            {/* Grid lines */}
            <line x1="20" y1="40" x2="580" y2="40" stroke="rgba(255,255,255,0.03)" stroke-width="0.5" />
            <line x1="20" y1="80" x2="580" y2="80" stroke="rgba(255,255,255,0.03)" stroke-width="0.5" />
            <line x1="20" y1="120" x2="580" y2="120" stroke="rgba(255,255,255,0.03)" stroke-width="0.5" />

            {/* Gradient fill */}
            <polygon points={polygonStr()} fill="url(#equityGrad)" />

            {/* Buy & Hold line */}
            <polyline
              points={holdLineStr()}
              fill="none"
              stroke="rgba(255,255,255,0.1)"
              stroke-width="1"
              stroke-dasharray="4 3"
            />

            {/* Equity curve line */}
            <polyline
              points={polylineStr()}
              fill="none"
              stroke="rgba(59,130,246,0.8)"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </div>
      </Show>
    </div>
  )
}
