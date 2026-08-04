import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'
import PositionRow from './PositionRow'

export default function OpenPositions(props) {
  const isSafe = createMemo(() => !props.circuitBreaker?.tripped)
  const isWsLive = createMemo(() => props.wsConnected && !props.wsStale)

  return (
    <div class="glass rounded-2xl overflow-hidden mt-6">
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.02]">
        <div class="flex items-center gap-3">
          <div class="w-2 h-8 bg-primary-500 rounded-full"></div>
          <h2 class="text-sm font-bold text-white uppercase tracking-[0.2em]">
            Open Positions
            <span class="text-primary-400 ml-2 font-black text-data">[{(props.positions || []).length}]</span>
          </h2>
        </div>
        <div class="flex items-center gap-2">
          <div class={`flex items-center gap-2 text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full transition-all duration-500 border ${isWsLive() ? 'text-cyan-300 bg-cyan-500/10 border-cyan-500/30' : 'text-amber-300 bg-amber-500/10 border-amber-500/30'}`}>
            <span class={`w-2 h-2 rounded-full ${isWsLive() ? 'bg-cyan-300 shadow-[0_0_10px_rgba(34,211,238,0.55)]' : 'bg-amber-300 animate-pulse shadow-[0_0_10px_rgba(251,191,36,0.45)]'}`}></span>
            {isWsLive() ? 'WS LIVE' : 'WS STALE'}
          </div>
          <div class={`flex items-center gap-2 text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full transition-all duration-500 border ${isSafe() ? 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20' : 'text-rose-400 bg-rose-500/10 border-rose-500/20'}`}>
            <span class={`w-2 h-2 rounded-full ${isSafe() ? 'bg-emerald-400 shadow-[0_0_8px_oklch(0.64_0.17_145_/_0.5)]' : 'bg-rose-400 animate-pulse shadow-[0_0_12px_oklch(0.62_0.18_20_/_0.5)]'}`}></span>
            CIRCUIT: {isSafe() ? 'OPTIMAL' : 'TRIPPED'}
          </div>
        </div>
      </div>

      <Show when={(props.positions || []).length === 0}>
        <div class="flex flex-col items-center justify-center py-20 text-gray-600">
          <div class="w-16 h-16 rounded-full bg-white/5 flex items-center justify-center mb-4">
            <span class="text-2xl">⚡</span>
          </div>
          <p class="text-xs uppercase tracking-widest font-bold">Scanning for entries...</p>
        </div>
      </Show>

      <Show when={(props.positions || []).length > 0}>
        <div class="overflow-x-auto">
          <table class="w-full border-collapse">
            <thead>
              <tr class="text-[10px] text-gray-500 uppercase tracking-widest border-b border-white/5 bg-white/[0.01]">
                <th class="text-left px-6 py-4 font-bold">Asset</th>
                <th class="text-center px-4 py-4 font-bold">Position</th>
                <th class="text-right px-4 py-4 font-bold">Size</th>
                <th class="text-right px-4 py-4 font-bold">Entry</th>
                <th class="text-right px-4 py-4 font-bold">Current</th>
                <th class="text-right px-4 py-4 font-bold">Net P&amp;L</th>
                <th class="text-right px-4 py-4 font-bold">% Change</th>
                <th class="text-right px-4 py-4 font-bold">Peak (HWM)</th>
                <th class="text-right px-6 py-4 font-bold">Duration</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <For each={props.positions || []}>
                {(pos) => <PositionRow pos={pos} />}
              </For>
            </tbody>
          </table>
        </div>
      </Show>
    </div>
  )
}
