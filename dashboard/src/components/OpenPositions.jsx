import { createMemo } from 'solid-js'
import { Show, For, Index } from 'solid-js'
import PositionRow from './PositionRow'
import AnimatedNumber from './AnimatedNumber'
import { Table, TableHeader, TableBody, TableRow, TableHead } from './ui/Table'

export default function OpenPositions(props) {
  const isSafe = createMemo(() => !props.circuitBreaker?.tripped)
  const isWsLive = createMemo(() => props.wsConnected && !props.wsStale)

  const totalOpenPnl = createMemo(() => {
    return (props.positions || []).reduce((sum, p) => sum + Number(p.pnl || 0), 0)
  })

  return (
    <div class="glass rounded-2xl overflow-hidden mt-6">
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.02] flex-wrap gap-4">
        <div class="flex items-center gap-4">
          <div class="w-2 h-8 bg-primary-500 rounded-full" />
          <div>
            <h2 class="text-sm font-bold text-white uppercase tracking-[0.2em] flex items-center gap-2">
              Open Positions
              <span class="text-primary-400 font-black text-data">[{(props.positions || []).length}]</span>
            </h2>
            <Show when={(props.positions || []).length > 0}>
              <div class="text-[10px] text-gray-400 font-bold uppercase tracking-wider flex items-center gap-2 mt-0.5">
                <span>Total Open PnL:</span>
                <span class="font-black">
                  <AnimatedNumber value={totalOpenPnl()} currency decimals={2} showSign pnlColor />
                </span>
              </div>
            </Show>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <div class={`flex items-center gap-2 text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full transition-all duration-500 border ${isWsLive() ? 'text-cyan-300 bg-cyan-500/10 border-cyan-500/30' : 'text-amber-300 bg-amber-500/10 border-amber-500/30'}`}>
            <span class={`w-2 h-2 rounded-full ${isWsLive() ? 'bg-cyan-300 shadow-[0_0_10px_rgba(34,211,238,0.55)]' : 'bg-amber-300 animate-pulse shadow-[0_0_10px_rgba(251,191,36,0.45)]'}`} />
            {isWsLive() ? 'WS LIVE' : 'WS STALE'}
          </div>
          <div class={`flex items-center gap-2 text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full transition-all duration-500 border ${isSafe() ? 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20' : 'text-rose-400 bg-rose-500/10 border-rose-500/20'}`}>
            <span class={`w-2 h-2 rounded-full ${isSafe() ? 'bg-emerald-400 shadow-[0_0_8px_oklch(0.64_0.17_145_/_0.5)]' : 'bg-rose-400 animate-pulse shadow-[0_0_12px_oklch(0.62_0.18_20_/_0.5)]'}`} />
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
          <Table>
            <TableHeader>
              <TableRow class="text-[10px] text-gray-400 uppercase tracking-[0.15em] border-b border-white/5 bg-white/[0.02]">
                <TableHead class="text-left px-6 py-4 font-black">Asset</TableHead>
                <TableHead class="text-center px-4 py-4 font-black">Position</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">Qty (Lots)</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">Entry</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">LTP</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">SL</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">TP</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">Net P&amp;L</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">P&amp;L %</TableHead>
                <TableHead class="text-right px-4 py-4 font-black">Peak (HWM)</TableHead>
                <TableHead class="text-right px-6 py-4 font-black">Duration</TableHead>
                <TableHead class="text-center px-4 py-4 font-black w-28">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody class="divide-y divide-white/5">
              <Index each={props.positions || []}>
                {(pos) => (
                  <PositionRow
                    pos={pos}
                    onClose={props.onClosePosition}
                    closingId={props.closingPositionId}
                    onSelect={props.onSelectPosition}
                  />
                )}
              </Index>
            </TableBody>
          </Table>
        </div>
      </Show>
    </div>
  )
}

