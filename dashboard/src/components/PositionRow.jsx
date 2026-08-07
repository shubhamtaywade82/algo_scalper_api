import { createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { useFlash } from '../stores/useFlash'
import AnimatedNumber from './AnimatedNumber'
import { TableRow, TableCell } from './ui/Table'
import { getLotInfo } from '../lib/lots'

function inr(val, dec = 2) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: dec, maximumFractionDigits: dec })
}

function formatDuration(secs) {
  if (!secs) return '—'
  const m = Math.floor(secs / 60)
  const s = Math.floor(secs % 60)
  return m > 0 ? `${m}m ${s}s` : `${s}s`
}

export default function PositionRow(props) {
  const pos = () => props.pos
  const isStale = createMemo(() => pos()?.stale === true || pos()?.ltp_stale === true)

  const ltpFlash = useFlash(() => pos()?.ltp)
  const pnlFlash = useFlash(() => pos()?.pnl)
  const isClosing = createMemo(() => props.closingId != null && props.closingId === pos()?.id)

  const lotDetails = createMemo(() => getLotInfo(pos()?.symbol, pos()?.quantity))

  return (
    <TableRow
      clickable={typeof props.onSelect === 'function'}
      onClick={() => props.onSelect?.(pos()?.id)}
      class={`border-l-2 transition-all duration-300 ${
        Number(pos()?.pnl) >= 0
          ? 'bg-emerald-500/[0.01] hover:bg-emerald-500/[0.03] border-l-emerald-500/40'
          : 'bg-rose-500/[0.01] hover:bg-rose-500/[0.03] border-l-rose-500/40'
      }`}
    >
      <TableCell class="px-6 py-4">
        <div class="flex flex-col">
          <div class="flex items-center gap-2">
            <span class="text-sm font-black text-gray-100 uppercase tracking-tight">{pos()?.symbol}</span>
            <Show when={pos()?.paper}>
              <span class="text-[8px] font-black uppercase px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-400 border border-amber-500/20">
                PAPER
              </span>
            </Show>
          </div>
          <div class="flex items-center gap-1.5 text-[9px] text-gray-500 font-bold uppercase tracking-wider mt-1">
            <Show when={pos()?.index_key}>
              <span class="text-primary-400 font-black">{pos()?.index_key}</span>
              <span>•</span>
            </Show>
            <Show when={pos()?.direction}>
              <span class={pos()?.direction?.toUpperCase() === 'BULLISH' ? 'text-emerald-400' : 'text-rose-400'}>
                {pos()?.direction}
              </span>
              <span>•</span>
            </Show>
            <span>{pos()?.segment || 'F&O'}</span>
          </div>
        </div>
      </TableCell>
      <TableCell class="px-4 py-4 text-center">
        <span class={`text-[9px] font-black px-3 py-1 rounded-full tracking-wider uppercase inline-block min-w-[55px] ${pos()?.side === 'BUY' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 shadow-[0_0_8px_rgba(16,185,129,0.05)]' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20 shadow-[0_0_8px_rgba(239,68,68,0.05)]'}`}>
          {pos()?.side}
        </span>
      </TableCell>
      <TableCell class="px-4 py-4 text-right">
        <div class="flex flex-col items-end">
          <span class="text-gray-200 text-data font-black text-sm">
            <AnimatedNumber value={pos()?.quantity} integer decimals={0} />
          </span>
          <Show when={lotDetails().hasLots}>
            <span class="text-[9px] font-bold text-primary-400 text-data">
              {lotDetails().lots} {lotDetails().lots === 1 ? 'Lot' : 'Lots'}
            </span>
          </Show>
        </div>
      </TableCell>
      <TableCell class="px-4 py-4 text-right text-gray-400 text-data text-xs font-semibold">
        <AnimatedNumber value={pos()?.entry_price} decimals={2} />
      </TableCell>
      <TableCell class={`px-4 py-4 text-right text-white font-black text-data transition-all duration-300 rounded-lg ${isStale() ? 'bg-amber-500/10 text-amber-300 border border-amber-500/20' : ltpFlash()}`}>
        <div class="flex items-center justify-end gap-2">
          <span>{inr(pos()?.ltp)}</span>
          <Show when={isStale()}>
            <span class="text-[8px] font-black text-amber-300 bg-amber-500/10 border border-amber-500/20 px-1.5 py-0.5 rounded">STALE</span>
          </Show>
        </div>
      </TableCell>
      <TableCell class="px-4 py-4 text-right text-rose-400/80 text-data text-xs font-bold">
        <AnimatedNumber value={pos()?.sl_price} decimals={2} />
      </TableCell>
      <TableCell class="px-4 py-4 text-right text-emerald-400/80 text-data text-xs font-bold">
        <AnimatedNumber value={pos()?.tp_price} decimals={2} />
      </TableCell>
      <TableCell class={`px-4 py-4 text-right font-black text-data text-sm transition-all duration-300 rounded-lg ${pnlFlash()}`}>
        <AnimatedNumber value={pos()?.pnl} showSign currency absolute decimals={2} pnlColor />
      </TableCell>
      <TableCell class="px-4 py-4 text-right text-data font-bold">
        <div class="flex items-center justify-end gap-1">
          <span>
            <AnimatedNumber value={pos()?.pnl_pct} showSign suffix="%" decimals={2} pnlColor />
          </span>
          <div class={`w-1 h-3 rounded-full ${Number(pos()?.pnl_pct) >= 0 ? 'bg-emerald-500' : 'bg-rose-500'}`} />
        </div>
      </TableCell>
      <TableCell class="px-4 py-4 text-right font-black text-amber-400 text-data text-xs">
        <AnimatedNumber value={pos()?.hwm_pnl} currency decimals={2} />
      </TableCell>
      <TableCell class="px-6 py-4 text-right">
        <div class="flex flex-col items-end">
          <span class="text-data text-[11px] text-gray-400 font-bold">{formatDuration(pos()?.time_in_position_sec)}</span>
          <div class="w-12 h-1 bg-white/5 rounded-full mt-1.5 overflow-hidden">
            <div class="h-full duration-bar-progress" style={{ width: '100%' }} />
          </div>
        </div>
      </TableCell>
      <TableCell class="px-4 py-4 text-center align-middle">
        <Show when={typeof props.onClose === 'function'}>
          <button
            type="button"
            class="text-[10px] font-black uppercase tracking-widest px-3 py-2 rounded-xl border border-rose-500/30 text-rose-300 bg-rose-500/10 hover:bg-rose-500/25 hover:border-rose-500/50 shadow-[0_0_10px_rgba(239,68,68,0.05)] hover:shadow-[0_0_15px_rgba(239,68,68,0.2)] transition-all cursor-pointer disabled:opacity-40 disabled:pointer-events-none"
            disabled={isClosing()}
            onClick={(e) => {
              e.stopPropagation()
              props.onClose(pos()?.id)
            }}
            aria-label={`Close position ${pos()?.symbol}`}
          >
            {isClosing() ? '…' : 'Close'}
          </button>
        </Show>
      </TableCell>
    </TableRow>
  )
}
