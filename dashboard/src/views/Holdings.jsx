import { Show, For } from 'solid-js'
import { useHoldings } from '../stores/useHoldings'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import Button from '../components/ui/Button'

export default function Holdings() {
  const { holdings, loading, error, fetchHoldings } = useHoldings()

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={fetchHoldings}
          loading={loading()}
          leftIcon={<span>↻</span>}
        >
          {loading() ? 'Loading...' : 'Refresh'}
        </Button>
      </div>

      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: GET /api/holdings not yet implemented
        </p>
      </div>

      <Show when={error()}>
        <div class="glass rounded-2xl p-6 border border-rose-500/20">
          <p class="text-xs text-rose-400">Failed to load holdings: {error()}</p>
        </div>
      </Show>

      <Show when={!loading() && !error() && holdings().length === 0}>
        <div class="glass rounded-2xl p-12 text-center">
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No holdings data available</p>
        </div>
      </Show>

      <Show when={holdings().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 bg-white/[0.02]">
                  <TableHead class="text-left px-6 py-4 font-black">Symbol</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">Quantity</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">Avg Price</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">LTP</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">P&L</TableHead>
                  <TableHead class="text-left px-4 py-4 font-black">Segment</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={holdings()}>
                  {(h) => (
                    <TableRow class="hover:bg-white/[0.02] transition-colors">
                      <TableCell class="px-6 py-4 font-bold text-white">{h.symbol}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-data">{h.quantity}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-data text-gray-400">{h.avg_price}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-data text-white">{h.ltp}</TableCell>
                      <TableCell class={`px-4 py-4 text-right text-data font-bold ${Number(h.pnl) >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        {h.pnl}
                      </TableCell>
                      <TableCell class="px-4 py-4 text-gray-500">{h.segment}</TableCell>
                    </TableRow>
                  )}
                </For>
              </TableBody>
            </Table>
          </div>
        </div>
      </Show>
    </div>
  )
}
