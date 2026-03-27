import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'

const METRIC_KEYS = ['max_gain_pct', 'max_loss_pct', 'open_to_close_pct', 'post_peak_retrace', 'oi_change_pct', 'spot_change_pct']

function fmtPct(v) {
  if (v == null) return '—'
  return `${v >= 0 ? '+' : ''}${Number(v).toFixed(2)}%`
}

function pctClass(v) {
  if (v == null) return 'text-gray-500'
  return v >= 0 ? 'text-emerald-400' : 'text-rose-400'
}

function sessionBarColor(pct) {
  if (pct == null) return 'bg-gray-700'
  if (pct >= 1) return 'bg-emerald-500'
  if (pct <= -1) return 'bg-rose-500'
  return 'bg-amber-500'
}

function sessionOpacity(pct) {
  if (pct == null) return 0.3
  return Math.min(Math.abs(pct) / 5 + 0.4, 1)
}

export default function HistoricalBehavior(props) {
  const data = () => props.data
  const ce = createMemo(() => data()?.ce_aggregate)
  const pe = createMemo(() => data()?.pe_aggregate)
  const cycles = createMemo(() => (data()?.cycles || []).slice(-6))
  const hasData = createMemo(() => data() && !data().error)

  const latestSessions = createMemo(() => {
    if (!data()?.cycles?.length) return null
    const last = data().cycles[data().cycles.length - 1]
    return { ce: last.ce_sessions, pe: last.pe_sessions }
  })

  return (
    <div class="glass rounded-2xl p-6 glass-hover">
      <div class="flex items-center justify-between mb-5">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">📈 Historical Options Behavior</span>
        <Show when={hasData()}>
          <span class="text-[9px] font-bold text-gray-600 tracking-wider">
            {data().weeks} weeks · {ce()?.n || 0} cycles
          </span>
        </Show>
      </div>

      <Show when={!data() && !props.loading}>
        <div class="text-center py-12">
          <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase mb-3">No historical data loaded</div>
          <button
            onClick={() => props.onLoad?.()}
            class="px-5 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest bg-primary-500/10 text-primary-400 border border-primary-500/20 hover:bg-primary-500/20 transition-all"
          >
            📊 Load from DhanHQ
          </button>
          <div class="text-gray-700 text-[8px] mt-3 tracking-wider">First load may take 10–30 seconds</div>
        </div>
      </Show>

      <Show when={props.loading}>
        <div class="flex flex-col items-center py-12 gap-3">
          <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin"></div>
          <span class="text-[9px] font-bold text-gray-600 tracking-widest uppercase">Fetching DhanHQ data...</span>
        </div>
      </Show>

      <Show when={data()?.error}>
        <div class="text-center py-8 text-rose-400 text-xs font-bold">{data().error}</div>
      </Show>

      <Show when={hasData()}>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
          <Show when={ce()}>
            <div>
              <div class="text-[9px] font-black text-cyan-400 tracking-widest uppercase mb-3">CE (Call) Aggregate</div>
              <table class="w-full text-[10px]">
                <thead>
                  <tr class="border-b border-white/5">
                    <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Metric</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Avg</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Best</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Worst</th>
                  </tr>
                </thead>
                <tbody class="text-data">
                  <For each={METRIC_KEYS}>
                    {(key) => (
                      <tr class="border-b border-white/[0.03]">
                        <td class="py-2 text-gray-500 text-[9px] font-bold tracking-wider">{key.replace(/_pct$/, '').replace(/_/g, ' ')}</td>
                        <td class={`py-2 text-right font-bold ${pctClass(ce().avg[key])}`}>{fmtPct(ce().avg[key])}</td>
                        <td class="py-2 text-right text-gray-400">{fmtPct(ce().max[key])}</td>
                        <td class="py-2 text-right text-gray-500">{fmtPct(ce().min[key])}</td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>

          <Show when={pe()}>
            <div>
              <div class="text-[9px] font-black text-cyan-400 tracking-widest uppercase mb-3">PE (Put) Aggregate</div>
              <table class="w-full text-[10px]">
                <thead>
                  <tr class="border-b border-white/5">
                    <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Metric</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Avg</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Best</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Worst</th>
                  </tr>
                </thead>
                <tbody class="text-data">
                  <For each={METRIC_KEYS}>
                    {(key) => (
                      <tr class="border-b border-white/[0.03]">
                        <td class="py-2 text-gray-500 text-[9px] font-bold tracking-wider">{key.replace(/_pct$/, '').replace(/_/g, ' ')}</td>
                        <td class={`py-2 text-right font-bold ${pctClass(pe().avg[key])}`}>{fmtPct(pe().avg[key])}</td>
                        <td class="py-2 text-right text-gray-400">{fmtPct(pe().max[key])}</td>
                        <td class="py-2 text-right text-gray-500">{fmtPct(pe().min[key])}</td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>
        </div>

        <Show when={latestSessions()}>
          <div class="mt-6 space-y-3">
            <For each={[{side: 'ce', label: 'CE Sessions (Latest)'}, {side: 'pe', label: 'PE Sessions (Latest)'}]}>
              {({side, label}) => (
                <Show when={latestSessions()[side]}>
                  <div>
                    <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-1.5">{label}</div>
                    <div class="flex gap-1 h-8 rounded-lg overflow-hidden">
                      <For each={Object.entries(latestSessions()[side])}>
                        {([name, sess]) => (
                          <Show when={sess}>
                            <div
                              class={`flex-1 flex items-center justify-center text-[8px] font-black text-white rounded transition-transform hover:scale-y-110 ${sessionBarColor(sess.oc_pct)}`}
                              style={{ opacity: sessionOpacity(sess.oc_pct) }}
                              title={`${name}: ${fmtPct(sess.oc_pct)}`}
                            >
                              {name.substring(0, 4)} {fmtPct(sess.oc_pct)}
                            </div>
                          </Show>
                        )}
                      </For>
                    </div>
                  </div>
                </Show>
              )}
            </For>
          </div>
        </Show>

        <Show when={cycles().length > 0}>
          <div class="mt-6">
            <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">Recent Expiry Cycles</div>
            <div class="overflow-x-auto">
              <table class="w-full text-[10px]">
                <thead>
                  <tr class="border-b border-white/5">
                    <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">Expiry</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">CE Gain</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">CE Retr</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">PE Gain</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">PE Retr</th>
                    <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">Spot Δ</th>
                  </tr>
                </thead>
                <tbody class="text-data">
                  <For each={cycles()}>
                    {(c) => (
                      <tr class="border-b border-white/[0.03] hover:bg-white/[0.02] transition-colors">
                        <td class="py-2 text-gray-400">{c.expiry}</td>
                        <td class={`py-2 text-right ${pctClass(c.ce?.max_gain_pct)}`}>{fmtPct(c.ce?.max_gain_pct)}</td>
                        <td class="py-2 text-right text-amber-400">{fmtPct(c.ce?.post_peak_retrace)}</td>
                        <td class={`py-2 text-right ${pctClass(c.pe?.max_gain_pct)}`}>{fmtPct(c.pe?.max_gain_pct)}</td>
                        <td class="py-2 text-right text-amber-400">{fmtPct(c.pe?.post_peak_retrace)}</td>
                        <td class={`py-2 text-right ${pctClass(c.ce?.spot_change_pct)}`}>{fmtPct(c.ce?.spot_change_pct)}</td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </div>
        </Show>
      </Show>
    </div>
  )
}
