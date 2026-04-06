import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'

const ALIGNMENT_ROWS = [
  { key: 'long_signal', label: 'Long signal' },
  { key: 'short_signal', label: 'Short signal' },
  { key: 'structure_bias', label: 'Structure' },
  { key: 'long_score', label: 'Long score' },
  { key: 'short_score', label: 'Short score' },
  { key: 'choch_bull', label: 'CHoCH bull' },
  { key: 'choch_bear', label: 'CHoCH bear' },
  { key: 'liq_sweep_bull', label: 'Liq sweep bull' },
  { key: 'liq_sweep_bear', label: 'Liq sweep bear' },
  { key: 'pdh_sweep', label: 'PDH sweep' },
  { key: 'pdl_sweep', label: 'PDL sweep' }
]

function structureBiasLabel(v) {
  const n = Number(v)
  if (n === 1) return 'BULL'
  if (n === -1) return 'BEAR'
  return 'NEUTRAL'
}

function formatAlignmentCell(rowKey, val) {
  if (rowKey === 'structure_bias') return structureBiasLabel(val)
  if (typeof val === 'boolean') return val ? 'Y' : '—'
  if (val == null) return '—'
  return String(val)
}

function resolutionOrder(mtf) {
  const tf = mtf?.timeframes
  if (!tf || typeof tf !== 'object') return []
  return Object.keys(tf).sort((a, b) => {
    const na = Number(a)
    const nb = Number(b)
    if (!Number.isNaN(na) && !Number.isNaN(nb)) return na - nb
    return a.localeCompare(b)
  })
}

export default function SmcConfluencePanel(props) {
  const mtf = () => props.smcConfluenceMtf
  const summary = () => props.smcConfluenceLtfSummary
  const err = () => props.smcConfluenceMtfError
  const resolutions = createMemo(() => resolutionOrder(mtf()))
  const alignment = () => mtf()?.alignment || {}

  return (
    <div class="mt-4 pt-4 border-t border-white/10 space-y-4">
      <div class="flex items-center justify-between gap-2 flex-wrap">
        <span class="text-[10px] font-black text-amber-500/90 tracking-[0.2em] uppercase">
          SMC Confluence (Pine)
        </span>
        <Show when={mtf()?.generated_at_utc}>
          <span class="text-[8px] font-bold text-gray-600 tracking-wider">
            MTF {mtf().generated_at_utc} UTC
          </span>
        </Show>
      </div>

      <Show when={err()}>
        <div class="text-[9px] font-bold text-amber-400/90 bg-amber-500/10 border border-amber-500/20 rounded-lg px-3 py-2">
          Confluence digest error: {err()}
        </div>
      </Show>

      <Show when={summary() && !mtf()}>
        <div class="flex flex-wrap items-center gap-2 text-[9px] font-bold text-gray-400">
          <span class="text-gray-500 uppercase tracking-wider">LTF only</span>
          <span class="px-2 py-1 rounded bg-white/5 border border-white/10">
            L {summary().long_score ?? '—'} / S {summary().short_score ?? '—'}
          </span>
          <Show when={summary().structure_bias != null}>
            <span class="px-2 py-1 rounded bg-white/5 border border-white/10">
              {structureBiasLabel(summary().structure_bias)}
            </span>
          </Show>
          <Show when={summary().long_signal}>
            <span class="px-2 py-1 rounded bg-emerald-500/15 text-emerald-400 border border-emerald-500/25">LONG sig</span>
          </Show>
          <Show when={summary().short_signal}>
            <span class="px-2 py-1 rounded bg-rose-500/15 text-rose-400 border border-rose-500/25">SHORT sig</span>
          </Show>
        </div>
      </Show>

      <Show when={mtf() && resolutions().length > 0}>
        <div class="overflow-x-auto rounded-xl border border-white/10 bg-white/[0.02]">
          <table class="w-full text-left text-[9px]">
            <thead>
              <tr class="border-b border-white/10 text-gray-500 font-black uppercase tracking-wider">
                <th class="px-3 py-2 whitespace-nowrap">Metric</th>
                <For each={resolutions()}>
                  {(res) => (
                    <th class="px-3 py-2 whitespace-nowrap text-center">{res}m</th>
                  )}
                </For>
              </tr>
            </thead>
            <tbody>
              <For each={ALIGNMENT_ROWS}>
                {(row) => (
                  <tr class="border-b border-white/5 hover:bg-white/[0.02]">
                    <td class="px-3 py-1.5 font-bold text-gray-500 whitespace-nowrap">{row.label}</td>
                    <For each={resolutions()}>
                      {(res) => (
                        <td class="px-3 py-1.5 text-center font-mono text-gray-300">
                          {formatAlignmentCell(row.key, alignment()[row.key]?.[res])}
                        </td>
                      )}
                    </For>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </div>

        <div class="space-y-2">
          <span class="text-[9px] font-black text-gray-500 uppercase tracking-widest">Last bar per TF</span>
          <For each={resolutions()}>
            {(res) => {
              const block = () => mtf().timeframes?.[res]
              const c = () => block()?.confluence
              return (
                <Show when={c()}>
                  <div class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-lg bg-white/[0.02] border border-white/5">
                    <span class="text-[9px] font-black text-cyan-400 min-w-[28px]">{res}m</span>
                    <span class="text-[9px] text-gray-500">
                      L {c().long_score ?? '—'} / S {c().short_score ?? '—'}
                    </span>
                    <span class="text-[9px] text-gray-500">{structureBiasLabel(c().structure_bias)}</span>
                    <Show when={c().long_signal}>
                      <span class="px-1.5 py-0.5 rounded text-[8px] font-black bg-emerald-500/20 text-emerald-400">L</span>
                    </Show>
                    <Show when={c().short_signal}>
                      <span class="px-1.5 py-0.5 rounded text-[8px] font-black bg-rose-500/20 text-rose-400">S</span>
                    </Show>
                  </div>
                </Show>
              )
            }}
          </For>
        </div>
      </Show>

      <Show when={!summary() && !mtf() && !err()}>
        <p class="text-[9px] text-gray-600 leading-relaxed">
          Enable <code class="text-gray-400">signals.enable_smc_confluence_digest</code> in algo.yml and refresh analysis
          cache to populate Pine confluence (MTF digest + LTF summary).
        </p>
      </Show>
    </div>
  )
}
