import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'
import { useFlash } from '../stores/useFlash'
import AnimatedNumber from './AnimatedNumber'

function pnlClass(val) {
  const n = Number(val)
  if (!n) return 'from-gray-400 to-gray-500'
  return n >= 0 ? 'from-emerald-400 to-emerald-500' : 'from-rose-400 to-rose-500'
}

async function resetDrawdown() {
  if (!confirm('Are you sure you want to reset the drawdown guard? This will allow new entries for the rest of the day.')) return
  try {
    const res = await fetch('/api/drawdown_guard/reset', { method: 'DELETE' })
    const data = await res.json()
    if (data.success) {
      alert('Trading resumed successfully.')
    } else {
      alert('Error resetting guard: ' + data.error)
    }
  } catch {
    alert('Failed to connect to server')
  }
}

export default function StatsBar(props) {
  const stats = () => props.stats || {}
  const balance = () => props.balance || {}
  const tradingMode = () => (props.mode === 'paper' || stats().paper_mode === true ? 'PAPER' : 'LIVE')

  const totalFlash = useFlash(() => stats().total_pnl_rupees)
  const realizedFlash = useFlash(() => stats().realized_pnl_rupees)
  const unrealizedFlash = useFlash(() => stats().unrealized_pnl_rupees)
  const cashFlash = useFlash(() => balance().cash)

  return (
    <div class="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-7 gap-4">
      {/* Available Balance Card */}
      <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-primary-500/50 shadow-[0_4px_20px_rgba(59,130,246,0.05)] hover:shadow-[0_8px_30px_rgba(59,130,246,0.15)]">
        <div class="absolute top-0 right-0 w-32 h-32 bg-primary-500/5 blur-3xl transition-opacity group-hover:opacity-10"></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Available Cash</span>
          <div class={`flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2 ${cashFlash()}`}>
            <span class="text-2xl font-black text-white text-data tracking-tight">
              <AnimatedNumber value={balance().cash} currency decimals={2} />
            </span>
          </div>
          <div class="flex items-center justify-between gap-2 mt-4">
            <Show when={stats().is_blocked} fallback={
              <div class="flex items-center gap-2">
                <Show when={!props.marketStatus || props.marketStatus?.market_open} fallback={
                  <span class="text-[9px] font-black text-amber-400 uppercase tracking-widest flex items-center gap-1">
                    <div class="w-1.5 h-1.5 rounded-full bg-amber-500"></div>
                    {props.marketStatus?.holiday_name ? 'HOLIDAY' : (props.marketStatus?.is_trading_day === false ? 'WEEKEND' : 'MARKET CLOSED')}
                  </span>
                }>
                  <span class="text-[9px] font-black text-emerald-400 uppercase tracking-widest flex items-center gap-1">
                    <div class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></div> MARKET OPEN
                  </span>
                </Show>
                <span class={`text-[9px] font-black uppercase tracking-widest px-1.5 py-0.5 rounded border ${
                  tradingMode() === 'PAPER'
                    ? 'text-cyan-400 border-cyan-500/25 bg-cyan-500/10'
                    : 'text-emerald-400 border-emerald-500/25 bg-emerald-500/10'
                }`}>
                  {tradingMode()}
                </span>
              </div>
            }>
              <div class="flex items-center gap-2">
                <span class="text-[9px] font-black text-rose-500 uppercase tracking-widest flex items-center gap-1">
                  <div class="w-1.5 h-1.5 rounded-full bg-rose-500"></div> BLOCKED
                </span>
                <button
                  onClick={resetDrawdown}
                  class="px-2 py-1 bg-rose-500/25 hover:bg-rose-500/40 text-rose-300 border border-rose-500/40 rounded-lg text-[8px] font-black uppercase tracking-widest shadow-[0_0_8px_rgba(239,68,68,0.15)] hover:shadow-[0_0_12px_rgba(239,68,68,0.35)] transition-all animate-pulse"
                >
                  RESET GUARD
                </button>
              </div>
            </Show>
          </div>
        </div>
      </div>

      {/* Total P&L Card */}
      <div 
        class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group shadow-[0_4px_20px_rgba(0,0,0,0.3)] hover:border-l-4 transition-all duration-300"
        style={{ 'border-left-width': '4px', 'border-left-color': `var(--color-${Number(stats().total_pnl_rupees) >= 0 ? 'emerald' : 'rose'}-500)` }}
      >
        <div class={`absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10 ${pnlClass(stats().total_pnl_rupees)}`}></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Total Net P&amp;L</span>
          <div class={`flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2 ${totalFlash()}`}>
            <span class="text-sm font-bold">
              <AnimatedNumber value={stats().total_pnl_rupees} signOnly pnlColor zeroPositive />
            </span>
            <span class="text-3xl font-black text-data tracking-tighter">
              <AnimatedNumber value={stats().total_pnl_rupees} currency absolute decimals={2} pnlColor zeroPositive />
            </span>
          </div>
          
          <div class="flex flex-col gap-1.5 mt-4">
            <div class="flex justify-between items-center text-[8px] font-black tracking-widest text-gray-500">
              <span>WIN RATE: {(() => {
                const w = Number(stats().winners || 0);
                const l = Number(stats().losers || 0);
                const tot = w + l;
                return tot > 0 ? `${Math.round((w / tot) * 100)}%` : '—';
              })()}</span>
              <span class="text-gray-600">{stats().winners}W - {stats().losers}L</span>
            </div>
            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden flex">
              <div class="h-full bg-emerald-500 transition-all duration-500" style={{ width: `${(() => {
                const w = Number(stats().winners || 0);
                const l = Number(stats().losers || 0);
                const tot = w + l;
                return tot > 0 ? (w / tot) * 100 : 50;
              })()}%` }}></div>
              <div class="h-full bg-rose-500 transition-all duration-500 flex-1"></div>
            </div>
          </div>
        </div>
      </div>

      {/* Realized P&L */}
      <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-emerald-500/50 shadow-[0_4px_20px_rgba(16,185,129,0.03)] hover:shadow-[0_8px_30px_rgba(16,185,129,0.1)]">
        <div class={`absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10 ${pnlClass(stats().realized_pnl_rupees)}`}></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Realized</span>
          <div class={`flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2 ${realizedFlash()}`}>
            <span class="text-xs font-bold">
              <AnimatedNumber value={stats().realized_pnl_rupees} signOnly pnlColor zeroPositive />
            </span>
            <span class="text-2xl font-black text-data tracking-tight">
              <AnimatedNumber value={stats().realized_pnl_rupees} currency absolute decimals={2} pnlColor zeroPositive />
            </span>
          </div>
          <div class="flex items-center gap-2 mt-4">
            <span class="text-[9px] font-black text-emerald-400 uppercase tracking-widest bg-emerald-500/10 border border-emerald-500/20 px-2 py-0.5 rounded-full">BOOKED P&L</span>
          </div>
        </div>
      </div>

      {/* Unrealized P&L */}
      <div
        class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 shadow-[0_4px_20px_rgba(0,0,0,0.3)]"
        style={{ 'border-left-color': `var(--color-${Number(stats().unrealized_pnl_rupees) >= 0 ? 'emerald' : 'rose'}-500)` }}
      >
        <div class={`absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10 ${pnlClass(stats().unrealized_pnl_rupees)}`}></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Active Unrealized</span>
          <div class={`flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2 ${unrealizedFlash()}`}>
            <span class="text-xs font-bold">
              <AnimatedNumber value={stats().unrealized_pnl_rupees} signOnly pnlColor zeroPositive />
            </span>
            <span class="text-2xl font-black text-data tracking-tight">
              <AnimatedNumber value={stats().unrealized_pnl_rupees} currency absolute decimals={2} pnlColor zeroPositive />
            </span>
          </div>
          <div class="flex items-center gap-2 mt-4">
            <span class="text-[9px] font-black text-primary-400 uppercase tracking-widest">LIVE TRACKING</span>
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-primary-500"></span>
            </span>
          </div>
        </div>
      </div>

      {/* Daily Peak (HWM) */}
      <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-amber-500/50 shadow-[0_4px_20px_rgba(245,158,11,0.03)] hover:shadow-[0_8px_30px_rgba(245,158,11,0.1)]">
        <div class="absolute top-0 right-0 w-32 h-32 bg-amber-500/5 blur-3xl transition-opacity group-hover:opacity-10"></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Daily Peak (HWM)</span>
          <div class="flex items-baseline gap-1 mt-1">
            <span class="text-2xl font-black text-amber-400 text-data tracking-tight">
              <AnimatedNumber value={stats().peak_pnl} currency decimals={2} />
            </span>
          </div>
          <div class="flex items-center gap-2 mt-4">
            <span class="text-[9px] font-black text-amber-500 uppercase tracking-widest bg-amber-500/10 border border-amber-500/20 px-2 py-0.5 rounded-full">HIGH WATERMARK</span>
          </div>
        </div>
      </div>

      {/* Active Positions */}
      <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-indigo-500/50 shadow-[0_4px_20px_rgba(99,102,241,0.03)] hover:shadow-[0_8px_30px_rgba(99,102,241,0.1)]">
        <div class="absolute top-0 right-0 w-24 h-24 bg-indigo-400/10 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Live Exposure</span>
          <div class="flex items-baseline gap-2 mt-2">
            <span class="text-3xl font-black text-indigo-400 text-data">
              <AnimatedNumber value={stats().active_positions ?? 0} integer decimals={0} />
            </span>
            <span class="text-[10px] font-bold text-gray-500 uppercase tracking-widest">Active</span>
          </div>
          <div class="flex items-center gap-1 mt-4">
            <div class="w-1.5 h-3 bg-indigo-500/40 rounded-full"></div>
            <div class="w-1.5 h-3 bg-indigo-500/20 rounded-full"></div>
            <div class="w-1.5 h-3 bg-indigo-500/10 rounded-full"></div>
          </div>
        </div>
      </div>

      {/* Day Volume */}
      <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-cyan-500/50 shadow-[0_4px_20px_rgba(6,182,212,0.03)] hover:shadow-[0_8px_30px_rgba(6,182,212,0.1)]">
        <div class="absolute top-0 right-0 w-24 h-24 bg-cyan-400/10 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
        <div class="flex flex-col relative z-10">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Day Volume</span>
          <div class="flex items-baseline gap-2 mt-2">
            <span class="text-3xl font-black text-cyan-400 text-data">
              <AnimatedNumber value={stats().total_trades ?? 0} integer decimals={0} />
            </span>
            <span class="text-[10px] font-bold text-gray-500 uppercase tracking-widest">Trades</span>
          </div>
          <div class="mt-4 flex items-center gap-1">
            <For each={[1, 2, 3, 4, 5]}>
              {(i) => <div class={`h-1.5 flex-1 rounded-full ${i <= (stats().total_trades > 5 ? 5 : stats().total_trades) ? 'bg-cyan-500/40 shadow-[0_0_8px_rgba(6,182,212,0.3)]' : 'bg-white/5'}`}></div>}
            </For>
          </div>
        </div>
      </div>
    </div>
  )
}
