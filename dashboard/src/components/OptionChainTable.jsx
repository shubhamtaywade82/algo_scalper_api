// dashboard/src/components/OptionChainTable.jsx
import { Index, Show } from 'solid-js'

function fmt(n, digits = 2) {
  return n == null ? '—' : Number(n).toFixed(digits)
}

export default function OptionChainTable(props) {
  const legs = () => props.chain?.legs || []
  const atmStrike = () => props.chain?.atm_strike

  const strikeRows = () => {
    const byStrike = {}
    legs().forEach(leg => {
      byStrike[leg.strike] ||= { strike: leg.strike, ce: null, pe: null }
      byStrike[leg.strike][leg.type.toLowerCase()] = leg
    })
    return Object.values(byStrike).sort((a, b) => a.strike - b.strike)
  }

  return (
    <div class="glass rounded-2xl overflow-hidden mt-6">
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.02]">
        <h2 class="text-sm font-bold text-white uppercase tracking-[0.2em]">
          {props.indexKey} Option Chain
          <Show when={props.chain?.spot}>
            <span class="text-primary-400 ml-2 font-black text-data">Spot {fmt(props.chain.spot)}</span>
          </Show>
        </h2>
        <div class={`text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full border ${props.isStale ? 'text-amber-300 bg-amber-500/10 border-amber-500/30' : 'text-cyan-300 bg-cyan-500/10 border-cyan-500/30'}`}>
          {props.isStale ? 'STALE' : 'LIVE'}
        </div>
      </div>

      <Show when={strikeRows().length > 0} fallback={<div class="p-10 text-center text-gray-600 text-xs uppercase tracking-widest">Waiting for chain data...</div>}>
        <div class="overflow-x-auto">
          <table class="w-full border-collapse text-xs">
            <thead>
              <tr class="text-[10px] text-gray-400 uppercase tracking-[0.15em] border-b border-white/5 bg-white/[0.02]">
                <th class="text-right px-3 py-2">CE Delta</th>
                <th class="text-right px-3 py-2">CE IV</th>
                <th class="text-right px-3 py-2">CE OI</th>
                <th class="text-right px-3 py-2">CE LTP</th>
                <th class="text-center px-3 py-2">Strike</th>
                <th class="text-left px-3 py-2">PE LTP</th>
                <th class="text-left px-3 py-2">PE OI</th>
                <th class="text-left px-3 py-2">PE IV</th>
                <th class="text-left px-3 py-2">PE Delta</th>
              </tr>
            </thead>
            <tbody>
              <Index each={strikeRows()}>
                {row => (
                  <tr class={`border-b border-white/5 ${row().strike === atmStrike() ? 'bg-primary-500/10' : ''}`}>
                    <td class="text-right px-3 py-2">{fmt(row().ce?.delta, 3)}</td>
                    <td class="text-right px-3 py-2">{fmt(row().ce?.iv)}</td>
                    <td class="text-right px-3 py-2">{row().ce?.oi ?? '—'}</td>
                    <td class="text-right px-3 py-2 font-bold">{fmt(row().ce?.ltp)}</td>
                    <td class="text-center px-3 py-2 font-black">{row().strike}</td>
                    <td class="text-left px-3 py-2 font-bold">{fmt(row().pe?.ltp)}</td>
                    <td class="text-left px-3 py-2">{row().pe?.oi ?? '—'}</td>
                    <td class="text-left px-3 py-2">{fmt(row().pe?.iv)}</td>
                    <td class="text-left px-3 py-2">{fmt(row().pe?.delta, 3)}</td>
                  </tr>
                )}
              </Index>
            </tbody>
          </table>
        </div>
      </Show>
    </div>
  )
}
