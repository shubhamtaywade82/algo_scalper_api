import { Show, For, Index } from 'solid-js'
import PositionRow from './PositionRow'
import { Table, TableHeader, TableBody, TableRow, TableHead } from './ui/Table'

export default function OpenPositions(props) {
  return (
    <div class="overflow-hidden">
      <Show when={(props.positions || []).length === 0}>
        <div class="flex flex-col items-center justify-center py-8 text-gray-600">
          <div class="w-8 h-8 rounded-full bg-white/5 flex items-center justify-center mb-2">
            <span class="text-sm">⚡</span>
          </div>
          <p class="text-[10px] uppercase tracking-wide font-medium">Scanning for entries...</p>
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

