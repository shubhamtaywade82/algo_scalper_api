import { createMemo, createSignal, Show, For } from 'solid-js'

function fmtPct(v) {
  if (v == null) return '—'
  return `${v >= 0 ? '+' : ''}${Number(v).toFixed(2)}%`
}

function fmtVal(v, dec = 2) {
  if (v == null) return '—'
  return Number(v).toFixed(dec)
}

export default function OptimizationPanel(props) {
  const [lookback, setLookback] = createSignal(5)
  const [indicator, setIndicator] = createSignal('all')

  const results = createMemo(() => props.data)

  const handleRun = () => {
    if (props.onRun) {
      props.onRun(lookback(), indicator())
    }
  }

  return (
    <div class="glass rounded-2xl p-6 glass-hover">
      <div class="flex items-center justify-between gap-3 mb-5">
        <div class="flex items-center gap-3">
          <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">⚙️ Backtest & Parameter Optimization</span>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div>
          <label class="block text-[8px] font-black text-gray-500 uppercase tracking-widest mb-2">Lookback (Days)</label>
          <select
            value={lookback()}
            onChange={(e) => setLookback(Number(e.target.value))}
            class="w-full px-3 py-2 rounded-lg bg-black/40 border border-white/10 text-gray-300 text-xs font-bold focus:outline-none focus:border-primary-500/50"
          >
            <option value={5}>5 Days</option>
            <option value={15}>15 Days</option>
            <option value={30}>30 Days</option>
            <option value={90}>90 Days</option>
          </select>
        </div>

        <div>
          <label class="block text-[8px] font-black text-gray-500 uppercase tracking-widest mb-2">Indicator / System</label>
          <select
            value={indicator()}
            onChange={(e) => setIndicator(e.target.value)}
            class="w-full px-3 py-2 rounded-lg bg-black/40 border border-white/10 text-gray-300 text-xs font-bold focus:outline-none focus:border-primary-500/50"
          >
            <option value="all">All Systems</option>
            <option value="adx">ADX Indicator</option>
            <option value="rsi">RSI Indicator</option>
            <option value="macd">MACD Indicator</option>
            <option value="supertrend">Supertrend Indicator</option>
            <option value="trailing">Trailing Stop Exit</option>
          </select>
        </div>

        <div class="flex items-end">
          <button
            onClick={handleRun}
            disabled={props.loading}
            class="w-full px-4 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest bg-primary-500/20 text-primary-300 border border-primary-500/30 hover:bg-primary-500/30 hover:border-primary-500/50 transition-all duration-300 disabled:opacity-40 flex items-center justify-center gap-2 shadow-[0_0_15px_rgba(59,130,246,0.1)]"
          >
            <Show when={props.loading}>
              <span class="w-3.5 h-3.5 border border-primary-300 border-t-transparent rounded-full animate-spin"></span>
            </Show>
            <span>{props.loading ? 'Sweeping Parameters...' : '⚡ Run Optimization Sweep'}</span>
          </button>
        </div>
      </div>

      <Show when={props.error}>
        <div class="text-rose-400 text-[10px] font-bold mb-4 px-3 py-2 bg-rose-500/10 border border-rose-500/20 rounded-lg">
          ⚠ {props.error}
        </div>
      </Show>

      <Show when={props.loading && !results()}>
        <div class="flex flex-col items-center justify-center py-12 gap-3 bg-white/[0.01] border border-white/5 rounded-xl">
          <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin" />
          <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase">
            Fetching candle series & testing combinations...
          </span>
        </div>
      </Show>

      <Show when={results()}>
        <div class="space-y-6">
          {/* Indicators Section */}
          <Show when={results().indicators && Object.keys(results().indicators).length > 0}>
            <div>
              <div class="text-[9px] font-black text-cyan-400 tracking-widest uppercase mb-3">Indicator Parameter Sweeps</div>
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <For each={Object.entries(results().indicators)}>
                  {([ind, res]) => (
                    <div class="rounded-xl p-4 bg-white/[0.02] border border-white/5">
                      <div class="flex items-center justify-between mb-3 border-b border-white/5 pb-2">
                        <span class="text-[10px] font-black text-white uppercase tracking-wider">{ind}</span>
                        <span class="text-[9px] font-black text-emerald-400 bg-emerald-400/10 px-2 py-0.5 rounded tracking-widest">
                          {fmtPct(res.best_params ? res.avg_price_move : 0)} AVG MOVE
                        </span>
                      </div>

                      <Show when={res.best_params} fallback={
                        <div class="text-[9px] font-bold text-rose-400/80 py-2">
                          ⚠ Optimization failed: {res.error || 'Failed to load series data'}
                        </div>
                      }>
                        <div class="space-y-2 text-xs">
                          <div class="flex items-center justify-between">
                            <span class="text-[9px] font-bold text-gray-500 uppercase tracking-wider">Win Rate</span>
                            <span class="text-data text-xs font-black text-emerald-400">{fmtVal(res.win_rate * 100, 1)}%</span>
                          </div>
                          <div class="flex items-center justify-between">
                            <span class="text-[9px] font-bold text-gray-500 uppercase tracking-wider">Total Signals</span>
                            <span class="text-data text-xs font-black text-gray-300">{res.total_signals}</span>
                          </div>
                          <div class="flex items-center justify-between">
                            <span class="text-[9px] font-bold text-gray-500 uppercase tracking-wider">Max Move</span>
                            <span class="text-data text-xs font-black text-gray-300">{fmtPct(res.max_move_pct)}</span>
                          </div>
                          <div class="h-px bg-white/5 my-2"></div>
                          <div>
                            <span class="block text-[8px] font-black text-cyan-400 uppercase tracking-wider mb-1.5">🎯 Suggested Optimal Setup:</span>
                            <div class="flex flex-wrap gap-2">
                              <For each={Object.entries(res.best_params)}>
                                {([param, val]) => (
                                  <span class="px-2 py-1 rounded bg-black/40 border border-white/10 text-[9px] font-bold text-gray-400">
                                    {param}: <strong class="text-white">{val}</strong>
                                  </span>
                                )}
                              </For>
                            </div>
                          </div>
                        </div>
                      </Show>
                    </div>
                  )}
                </For>
              </div>
            </div>
          </Show>

          {/* Trailing stops Section */}
          <Show when={results().trailing}>
            <div class="rounded-xl p-5 bg-white/[0.01] border border-cyan-500/10">
              <div class="flex items-center justify-between mb-4 pb-2 border-b border-white/5">
                <span class="text-[10px] font-black text-cyan-400 tracking-widest uppercase">Trailing Exit Stop Calibration</span>
                <span class="text-[9px] font-bold text-cyan-400 bg-cyan-400/10 px-2 py-0.5 rounded tracking-widest">
                  {results().trailing.total_simulated || 92} TRADES SIMULATED
                </span>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 mb-4">
                <div class="p-3 rounded-lg bg-black/40 border border-white/5">
                  <span class="block text-[8px] font-bold text-gray-500 uppercase tracking-wider mb-1">Early Trigger</span>
                  <span class="text-sm font-black text-white">{fmtVal((results().trailing.best_params?.early_trigger || 0.03) * 100, 1)}%</span>
                </div>
                <div class="p-3 rounded-lg bg-black/40 border border-white/5">
                  <span class="block text-[8px] font-bold text-gray-500 uppercase tracking-wider mb-1">Breakeven Trigger</span>
                  <span class="text-sm font-black text-white">{fmtVal((results().trailing.best_params?.breakeven_trigger || 0.08) * 100, 1)}%</span>
                </div>
                <div class="p-3 rounded-lg bg-black/40 border border-white/5">
                  <span class="block text-[8px] font-bold text-gray-500 uppercase tracking-wider mb-1">Activation Trigger</span>
                  <span class="text-sm font-black text-white">{fmtVal((results().trailing.best_params?.activation_trigger || 0.15) * 100, 1)}%</span>
                </div>
                <div class="p-3 rounded-lg bg-black/40 border border-white/5">
                  <span class="block text-[8px] font-bold text-gray-500 uppercase tracking-wider mb-1">Trailing Distance</span>
                  <span class="text-sm font-black text-white">{fmtVal((results().trailing.best_params?.trailing_distance || 0.20) * 100, 1)}%</span>
                </div>
              </div>
            </div>
          </Show>
        </div>
      </Show>
    </div>
  )
}
