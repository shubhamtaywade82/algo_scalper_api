import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'

function fmtPct(v, digits = 1) {
  if (v == null) return '—'
  return `${(Number(v) * 100).toFixed(digits)}%`
}

function fmtNum(v, digits = 2) {
  if (v == null) return '—'
  return Number(v).toFixed(digits)
}

function evClass(v) {
  if (v == null) return 'text-gray-500'
  return v >= 0 ? 'text-emerald-400' : 'text-rose-400'
}

export default function ExpectedValueRiskPanel(props) {
  const data = () => props.data
  const hasData = createMemo(() => data() && !data().error)
  const risk = createMemo(() => data()?.risk_config)
  const scenario = createMemo(() => data()?.scenario)
  const grid = createMemo(() => data()?.grid)
  const readiness = createMemo(() => data()?.deploy_readiness)
  const historical = createMemo(() => data()?.historical)
  const configR = createMemo(() => risk()?.reward_multiple)

  const highlightWinRates = createMemo(() => {
    const rates = grid()?.win_rates || []
    const be = risk()?.break_even_win_rate
    if (be == null) return new Set()
    return new Set(
      rates.filter((p) => Math.abs(p - be) < 0.03 || Math.abs(p - (scenario()?.win_probability ?? 0)) < 0.03)
    )
  })

  return (
    <div class="glass rounded-2xl p-6 glass-hover">
      <div class="flex items-center justify-between mb-5 flex-wrap gap-2">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">
          Expected Value & Risk Explorer
        </span>
        <Show when={hasData()}>
          <span class="text-[9px] font-bold text-gray-600 tracking-wider">
            R={fmtNum(configR())} · break-even {fmtPct(risk()?.break_even_win_rate)}
          </span>
        </Show>
      </div>

      <Show when={!data() && !props.loading}>
        <div class="text-center py-8">
          <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase mb-3">
            EV model not loaded
          </div>
          <button
            onClick={() => props.onLoad?.()}
            class="px-5 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest bg-primary-500/10 text-primary-400 border border-primary-500/20 hover:bg-primary-500/20 transition-all"
          >
            Compute EV & Risk
          </button>
        </div>
      </Show>

      <Show when={props.loading}>
        <div class="flex flex-col items-center py-10 gap-3">
          <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin" />
          <span class="text-[9px] font-bold text-gray-600 tracking-widest uppercase">Building risk report...</span>
        </div>
      </Show>

      <Show when={data()?.error}>
        <div class="text-center py-6 text-rose-400 text-xs font-bold">{data().error}</div>
      </Show>

      <Show when={hasData()}>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div class="rounded-xl border border-white/5 bg-white/[0.02] p-4">
            <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">Scenario EV</div>
            <div class={`text-2xl font-black ${evClass(scenario()?.expected_value)}`}>
              {fmtNum(scenario()?.expected_value, 3)}
            </div>
            <div class="text-[9px] text-gray-500 mt-1">
              P(win) {fmtPct(scenario()?.win_probability)} × R {fmtNum(configR())}
            </div>
          </div>
          <div class="rounded-xl border border-white/5 bg-white/[0.02] p-4">
            <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">Config stops</div>
            <div class="text-sm font-bold text-gray-300">
              SL {fmtPct(risk()?.sl_pct, 0)} · TP {fmtPct(risk()?.tp_pct, 0)}
            </div>
            <div class="text-[9px] text-gray-500 mt-1">
              Per-trade risk {fmtPct(risk()?.per_trade_risk_pct, 2)}
            </div>
          </div>
          <div class="rounded-xl border border-white/5 bg-white/[0.02] p-4">
            <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">Deploy readiness</div>
            <div class={`text-sm font-black ${readiness()?.positive_edge ? 'text-emerald-400' : 'text-rose-400'}`}>
              {readiness()?.positive_edge ? 'Positive edge' : 'No edge at scenario P'}
            </div>
            <div class="text-[9px] text-gray-500 mt-1">
              Conservative EV {fmtNum(readiness()?.conservative_expected_value, 3)}
            </div>
          </div>
        </div>

        <Show when={grid()?.cells?.length}>
          <div class="mb-6 overflow-x-auto">
            <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase mb-2">
              EV grid (risk units) — highlighted near break-even / scenario
            </div>
            <table class="w-full text-[9px] min-w-[480px]">
              <thead>
                <tr class="border-b border-white/5">
                  <th class="text-left py-2 font-black text-gray-600 tracking-widest uppercase">R</th>
                  <th class="text-right py-2 font-black text-gray-600 tracking-widest uppercase">BE P</th>
                  <For each={grid().win_rates}>
                    {(p) => (
                      <th
                        class={`text-right py-2 font-black tracking-widest uppercase ${
                          highlightWinRates().has(p) ? 'text-primary-400' : 'text-gray-600'
                        }`}
                      >
                        {fmtPct(p, 0)}
                      </th>
                    )}
                  </For>
                </tr>
              </thead>
              <tbody>
                <For each={grid().cells}>
                  {(row) => (
                    <tr
                      class={`border-b border-white/[0.03] ${
                        row.reward_multiple === configR() ? 'bg-primary-500/5' : ''
                      }`}
                    >
                      <td class="py-2 text-gray-400 font-bold">{fmtNum(row.reward_multiple, 1)}</td>
                      <td class="py-2 text-right text-amber-400">{fmtPct(row.break_even_win_rate)}</td>
                      <For each={grid().win_rates}>
                        {(p) => (
                          <td class={`py-2 text-right font-bold ${evClass(row.by_win_rate[p])}`}>
                            {fmtNum(row.by_win_rate[p], 2)}
                          </td>
                        )}
                      </For>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </Show>

        <Show when={historical()?.available}>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 text-[10px]">
            <For each={[{ key: 'ce', label: 'CE historical' }, { key: 'pe', label: 'PE historical' }]}>
              {({ key, label }) => (
                <Show when={historical()[key]}>
                  <div class="rounded-xl border border-white/5 p-4">
                    <div class="text-[8px] font-black text-cyan-400 tracking-widest uppercase mb-2">{label}</div>
                    <div class="grid grid-cols-2 gap-2 text-gray-400">
                      <span>Target hit rate</span>
                      <span class="text-right text-gray-200">{fmtPct(historical()[key].target_hit_rate)}</span>
                      <span>Stop touch rate</span>
                      <span class="text-right text-gray-200">{fmtPct(historical()[key].stop_touch_rate)}</span>
                      <span>Positive close</span>
                      <span class="text-right text-gray-200">{fmtPct(historical()[key].positive_close_rate)}</span>
                      <span>EV @ config R</span>
                      <span class={`text-right font-bold ${evClass(historical()[key].expected_value_at_config_rr)}`}>
                        {fmtNum(historical()[key].expected_value_at_config_rr, 3)}
                      </span>
                    </div>
                  </div>
                </Show>
              )}
            </For>
          </div>
        </Show>

        <Show when={data()?.theta_churn}>
          <div class="mt-4 text-[9px] text-gray-500 border-t border-white/5 pt-4">
            Theta/chop: <span class="text-gray-400">{data().theta_churn.message}</span>
          </div>
        </Show>
      </Show>
    </div>
  )
}
