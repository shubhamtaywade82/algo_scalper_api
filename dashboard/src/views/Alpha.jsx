import { For, Show, createMemo } from 'solid-js'
import { useAlpha } from '../stores/useAlpha'

function formatTime(timestamp) {
  if (!timestamp) return '—'
  const d = new Date(timestamp)
  return d.toLocaleString('en-IN', {
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
  })
}

function inr(val) {
  if (val == null) return '₹0.00'
  return `₹${Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export default function Alpha() {
  const { status, history, performance, scanning, triggerScan, executeSignal } = useAlpha()

  const riskPercent = createMemo(() => {
    const s = status().risk_stats
    const l = status().risk_limits
    if (!s || !l) return 0
    return Math.min((s.trades_count / l.daily_max_trades) * 100, 100)
  })

  return (
    <div class="flex flex-col gap-8">
      {/* Header & Controls */}
      <div class="flex items-center justify-between">
        <div class="flex flex-col gap-1">
          <h1 class="text-2xl font-black text-white uppercase tracking-tighter flex items-center gap-3">
            <span class="w-3 h-3 rounded-full bg-primary-500 shadow-[0_0_15px_rgba(59,130,246,0.5)]"></span>
            Alpha Intelligence
          </h1>
          <p class="text-xs font-bold text-gray-500 uppercase tracking-widest">Autonomous Strategy Orchestrator</p>
        </div>

        <div class="flex items-center gap-4">
          <button
            onClick={triggerScan}
            disabled={scanning()}
            class={`px-6 py-2.5 rounded-xl font-black text-[10px] uppercase tracking-[0.2em] transition-all duration-300 border flex items-center gap-3 ${scanning() ? 'bg-gray-800 border-white/5 text-gray-500' : 'bg-primary-600 hover:bg-primary-500 border-primary-400/50 text-white shadow-lg shadow-primary-900/20'}`}
          >
            <Show when={scanning()}>
              <span class="w-3 h-3 border-2 border-gray-500 border-t-transparent rounded-full animate-spin"></span>
            </Show>
            {scanning() ? 'Scanning Market...' : 'Trigger Live Scan'}
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Risk Limits Card */}
        <div class="glass rounded-3xl p-6 border border-white/5 flex flex-col gap-6">
          <div class="flex items-center justify-between">
            <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em]">Risk Guardrails</h3>
            <span class={`px-2 py-0.5 rounded text-[8px] font-black uppercase tracking-widest ${status().enabled ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'}`}>
              {status().enabled ? 'Active' : 'Halted'}
            </span>
          </div>

          <div class="flex flex-col gap-4">
            <div class="flex flex-col gap-2">
              <div class="flex justify-between items-end">
                <span class="text-[9px] font-bold text-gray-500 uppercase tracking-widest">Daily Trades</span>
                <span class="text-xs font-black text-white">{status().risk_stats?.trades_count || 0} / {status().risk_limits?.daily_max_trades || 0}</span>
              </div>
              <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                <div class="h-full bg-primary-500 transition-all duration-1000" style={`width: ${riskPercent()}%`}></div>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div class="bg-white/[0.02] rounded-2xl p-4 border border-white/5">
                <span class="text-[8px] font-black text-gray-600 uppercase tracking-widest block mb-1">Loss Streak</span>
                <span class={`text-lg font-black ${(status().risk_stats?.consecutive_losses || 0) >= 2 ? 'text-rose-500' : 'text-white'}`}>
                  {status().risk_stats?.consecutive_losses || 0}
                </span>
              </div>
              <div class="bg-white/[0.02] rounded-2xl p-4 border border-white/5">
                <span class="text-[8px] font-black text-gray-600 uppercase tracking-widest block mb-1">Active</span>
                <span class="text-lg font-black text-white">{status().risk_stats?.active_positions || 0}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Strategy Performance */}
        <div class="lg:col-span-2 glass rounded-3xl p-6 border border-white/5 flex flex-col gap-6">
          <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em]">Strategy Performance Attribution</h3>
          
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <For each={Object.entries(performance().by_source)}>
              {([source, stats]) => (
                <div class="bg-white/[0.02] rounded-2xl p-4 border border-white/5 flex flex-col gap-1">
                  <span class="text-[8px] font-black text-gray-600 uppercase tracking-widest">{source.replace(/_/g, ' ')}</span>
                  <span class={`text-sm font-black ${stats.total_pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{inr(stats.total_pnl)}</span>
                  <div class="flex items-center justify-between mt-1">
                    <span class="text-[8px] font-bold text-gray-500 uppercase tracking-tighter">WR: {stats.win_rate}%</span>
                    <span class="text-[8px] font-bold text-gray-500 uppercase tracking-tighter">n={stats.count}</span>
                  </div>
                </div>
              )}
            </For>
            <Show when={Object.keys(performance().by_source).length === 0}>
              <div class="col-span-full py-8 text-center text-[10px] font-bold text-gray-600 uppercase tracking-widest">
                No performance data recorded yet today.
              </div>
            </Show>
          </div>
        </div>
      </div>

      {/* Signal History Table */}
      <div class="glass rounded-3xl overflow-hidden border border-white/5">
        <div class="px-6 py-4 border-b border-white/5 flex items-center justify-between bg-white/[0.01]">
          <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em]">Recent Intelligence Signals</h3>
          <span class="text-[10px] font-bold text-gray-600 uppercase tracking-tighter">{history().length} signals cached</span>
        </div>
        
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="text-[9px] font-black text-gray-500 uppercase tracking-widest bg-white/[0.02]">
                <th class="p-4 pl-6">Time</th>
                <th class="p-4">Strategy</th>
                <th class="p-4">Instrument</th>
                <th class="p-4 text-center">Direction</th>
                <th class="p-4 text-right">Confidence</th>
                <th class="p-4 text-center">Status</th>
                <th class="p-4 text-right">PnL</th>
                <th class="p-4 pr-6 text-right">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <For each={history()}>
                {(sig) => (
                  <tr class="hover:bg-white/[0.02] transition-colors group">
                    <td class="p-4 pl-6">
                      <span class="text-[10px] font-bold text-gray-500 font-mono">{formatTime(sig.created_at)}</span>
                    </td>
                    <td class="p-4">
                      <span class="text-[10px] font-black text-white uppercase tracking-wider">{sig.alpha_source.replace(/_/g, ' ')}</span>
                    </td>
                    <td class="p-4">
                      <div class="flex flex-col">
                        <span class="text-xs font-black text-white">{sig.index_key.toUpperCase()}</span>
                        <span class="text-[9px] font-bold text-gray-500">Strike: {sig.strike_price}</span>
                      </div>
                    </td>
                    <td class="p-4 text-center">
                      <span class={`px-2 py-1 rounded-full text-[9px] font-black uppercase tracking-widest ${sig.direction.toLowerCase() === 'ce' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'}`}>
                        {sig.direction}
                      </span>
                    </td>
                    <td class="p-4 text-right">
                      <span class="text-xs font-black text-white">{(sig.confidence * 100).toFixed(0)}%</span>
                    </td>
                    <td class="p-4 text-center">
                      <span class={`text-[9px] font-black uppercase tracking-widest ${sig.status === 'executed' ? 'text-primary-400' : sig.status === 'failed' ? 'text-rose-500' : 'text-gray-500'}`}>
                        {sig.status}
                      </span>
                    </td>
                    <td class="p-4 text-right">
                      <Show when={sig.pnl != null} fallback={<span class="text-gray-700">—</span>}>
                        <span class={`text-xs font-black ${sig.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                          {inr(sig.pnl)}
                        </span>
                      </Show>
                    </td>
                    <td class="p-4 pr-6 text-right">
                      <Show when={sig.status === 'pending'}>
                        <button
                          onClick={() => executeSignal(sig)}
                          class="px-3 py-1 bg-white/5 hover:bg-primary-500 hover:text-white border border-white/10 rounded-lg text-[9px] font-black uppercase tracking-widest transition-all"
                        >
                          Execute
                        </button>
                      </Show>
                    </td>
                  </tr>
                )}
              </For>
              <Show when={history().length === 0}>
                <tr>
                  <td colspan="8" class="p-20 text-center text-gray-600 text-[10px] font-black uppercase tracking-[0.2em]">
                    Intelligence archive empty
                  </td>
                </tr>
              </Show>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
