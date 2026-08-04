import { For, Show, createMemo } from 'solid-js'
import { useAlpha } from '../stores/useAlpha'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import Badge from '../components/ui/Badge'

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
  const { status, history, performance } = useAlpha()

  const riskPercent = createMemo(() => {
    const s = status().risk_stats
    const l = status().risk_limits
    if (!s || !l) return 0
    return Math.min((s.trades_count / l.daily_max_trades) * 100, 100)
  })

  return (
    <div class="flex flex-col gap-8">
      {/* Header */}
      <div class="flex flex-col gap-1">
        <h1 class="text-2xl font-black text-white uppercase tracking-tighter flex items-center gap-3">
          <span class="w-3 h-3 rounded-full bg-primary-500 shadow-[0_0_15px_rgba(59,130,246,0.5)]" />
          Alpha Intelligence
        </h1>
        <p class="text-xs font-bold text-gray-500 uppercase tracking-widest">Strategies::Manager Platform View</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Risk Limits Card */}
        <div class="glass rounded-3xl p-6 border border-white/5 flex flex-col gap-6">
          <div class="flex items-center justify-between">
            <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em]">Risk Guardrails</h3>
            <Badge variant={status().enabled ? 'success' : 'danger'} class="text-[8px] font-black uppercase tracking-widest">
              {status().enabled ? 'Active' : 'Halted'}
            </Badge>
          </div>

          <div class="flex flex-col gap-4">
            <div class="flex flex-col gap-2">
              <div class="flex justify-between items-end">
                <span class="text-[9px] font-bold text-gray-500 uppercase tracking-widest">Daily Trades</span>
                <span class="text-xs font-black text-white">{status().risk_stats?.trades_count || 0} / {status().risk_limits?.daily_max_trades || 0}</span>
              </div>
              <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                <div class="h-full bg-primary-500 transition-all duration-1000" style={`width: ${riskPercent()}%`} />
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
          <Table>
            <TableHeader>
              <TableRow class="text-[9px] font-black text-gray-500 uppercase tracking-widest bg-white/[0.02]">
                <TableHead class="p-4 pl-6">Time</TableHead>
                <TableHead class="p-4">Strategy</TableHead>
                <TableHead class="p-4">Instrument</TableHead>
                <TableHead class="p-4 text-center">Direction</TableHead>
                <TableHead class="p-4 text-right">Confidence</TableHead>
                <TableHead class="p-4 text-center">Status</TableHead>
                <TableHead class="p-4 text-right">PnL</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody class="divide-y divide-white/5">
              <For each={history()}>
                {(sig) => (
                  <TableRow class="hover:bg-white/[0.02] transition-colors group">
                    <TableCell class="p-4 pl-6">
                      <span class="text-[10px] font-bold text-gray-500 font-mono">{formatTime(sig.created_at)}</span>
                    </TableCell>
                    <TableCell class="p-4">
                      <span class="text-[10px] font-black text-white uppercase tracking-wider">{(sig.alpha_source || 'unknown').replace(/_/g, ' ')}</span>
                    </TableCell>
                    <TableCell class="p-4">
                      <div class="flex flex-col">
                        <span class="text-xs font-black text-white">{sig.index_key?.toUpperCase()}</span>
                        <Show when={sig.strike_price != null}>
                          <span class="text-[9px] font-bold text-gray-500">Strike: {sig.strike_price}</span>
                        </Show>
                      </div>
                    </TableCell>
                    <TableCell class="p-4 text-center">
                      <Show when={sig.direction} fallback={<span class="text-gray-700">—</span>}>
                        <Badge
                          variant={sig.direction === 'bullish' ? 'success' : 'danger'}
                          class="text-[9px] font-black uppercase tracking-widest"
                        >
                          {sig.direction}
                        </Badge>
                      </Show>
                    </TableCell>
                    <TableCell class="p-4 text-right">
                      <Show when={sig.confidence != null} fallback={<span class="text-gray-700">—</span>}>
                        <span class="text-xs font-black text-white">{(sig.confidence * 100).toFixed(0)}%</span>
                      </Show>
                    </TableCell>
                    <TableCell class="p-4 text-center">
                      <Badge
                        variant={sig.status === 'entered' ? 'info' : sig.status === 'blocked' ? 'danger' : 'outline'}
                        class="text-[9px] font-black uppercase tracking-widest"
                      >
                        {sig.status}
                      </Badge>
                    </TableCell>
                    <TableCell class="p-4 text-right">
                      <Show when={sig.pnl != null} fallback={<span class="text-gray-700">—</span>}>
                        <span class={`text-xs font-black ${sig.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                          {inr(sig.pnl)}
                        </span>
                      </Show>
                    </TableCell>
                  </TableRow>
                )}
              </For>
              <Show when={history().length === 0}>
                <TableRow>
                  <TableCell colspan="7" class="p-20 text-center text-gray-600 text-[10px] font-black uppercase tracking-[0.2em]">
                    Intelligence archive empty
                  </TableCell>
                </TableRow>
              </Show>
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  )
}
