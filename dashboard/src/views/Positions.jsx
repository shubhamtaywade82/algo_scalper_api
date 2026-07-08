import { For, Show, createSignal, onMount } from 'solid-js'
import { usePositions } from '../stores/usePositions'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import AnimatedNumber from '../components/AnimatedNumber'
import PositionDetailDrawer from '../components/positions/PositionDetailDrawer'

function PositionsBox(props) {
  return (
    <div class="space-y-3">
      <h2 class="text-xs font-black uppercase tracking-widest text-gray-400">
        {props.title} ({props.rows.length})
      </h2>
      <div class="bg-white/[0.01] border border-white/5 rounded-2xl overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Symbol</TableHead>
              <TableHead class="text-center">Side</TableHead>
              <TableHead class="text-right">Qty</TableHead>
              <TableHead class="text-right">Entry</TableHead>
              <TableHead class="text-right">{props.isOpen ? 'LTP' : 'Exit'}</TableHead>
              <TableHead class="text-right">PnL</TableHead>
              <TableHead class="text-right">PnL %</TableHead>
              <Show when={props.isOpen}><TableHead class="text-center">Action</TableHead></Show>
            </TableRow>
          </TableHeader>
          <TableBody>
            <For each={props.rows}>
              {(pos) => (
                <TableRow clickable onClick={() => props.onSelect(pos.id)}>
                  <TableCell class="px-6 py-4 font-bold text-gray-100 uppercase text-sm">{pos.symbol}</TableCell>
                  <TableCell class="px-4 py-4 text-center">
                    <span class={`text-[9px] font-black px-3 py-1 rounded-full uppercase ${pos.side === 'BUY' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
                      {pos.side}
                    </span>
                  </TableCell>
                  <TableCell class="px-4 py-4 text-right text-gray-400"><AnimatedNumber value={pos.quantity} integer decimals={0} /></TableCell>
                  <TableCell class="px-4 py-4 text-right text-gray-500 text-xs"><AnimatedNumber value={pos.entry_price} decimals={2} /></TableCell>
                  <TableCell class="px-4 py-4 text-right text-white font-black">
                    <AnimatedNumber value={props.isOpen ? pos.ltp : pos.exit_price} decimals={2} />
                  </TableCell>
                  <TableCell class="px-4 py-4 text-right font-black"><AnimatedNumber value={pos.pnl} showSign currency absolute decimals={2} pnlColor /></TableCell>
                  <TableCell class="px-4 py-4 text-right font-bold"><AnimatedNumber value={pos.pnl_pct} showSign suffix="%" decimals={2} pnlColor /></TableCell>
                  <Show when={props.isOpen}>
                    <TableCell class="px-4 py-4 text-center">
                      <button
                        type="button"
                        class="text-[10px] font-black uppercase px-3 py-2 rounded-xl border border-rose-500/30 text-rose-300 bg-rose-500/10 hover:bg-rose-500/25 disabled:opacity-40"
                        disabled={props.closingId === pos.id}
                        onClick={(e) => { e.stopPropagation(); props.onClosePosition(pos.id) }}
                      >
                        {props.closingId === pos.id ? '…' : 'Close'}
                      </button>
                    </TableCell>
                  </Show>
                </TableRow>
              )}
            </For>
          </TableBody>
        </Table>
        <Show when={props.rows.length === 0}>
          <div class="py-16 text-center text-gray-500 text-sm">No {props.isOpen ? 'open' : 'closed'} positions.</div>
        </Show>
      </div>
    </div>
  )
}

export default function Positions() {
  const { open, closed, fetchPositions, closeOpenPosition, closingPositionId } = usePositions()
  const [selectedId, setSelectedId] = createSignal(null)

  onMount(() => fetchPositions())

  return (
    <div class="space-y-8">
      <PositionsBox
        title="Open"
        rows={open()}
        isOpen
        onSelect={setSelectedId}
        onClosePosition={closeOpenPosition}
        closingId={closingPositionId()}
      />
      <PositionsBox
        title="Closed"
        rows={closed()}
        isOpen={false}
        onSelect={setSelectedId}
      />

      <PositionDetailDrawer positionId={selectedId()} onClose={() => setSelectedId(null)} />
    </div>
  )
}
