import { createMemo } from 'solid-js'
import { Show, For } from 'solid-js'
import SmcConfluencePanel from './SmcConfluencePanel'

function decisionStyle(d) {
  const map = {
    call: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25 shadow-[0_0_20px_rgba(16,185,129,0.15)]',
    put: 'bg-rose-500/15 text-rose-400 border-rose-500/25 shadow-[0_0_20px_rgba(239,68,68,0.15)]',
    no_trade: 'bg-amber-500/10 text-amber-400 border-amber-500/20'
  }
  return map[d] || 'bg-white/5 text-gray-400 border-white/10'
}

const TF_LABELS = { htf: 'HTF', mtf: 'MTF', ltf: 'LTF' }
const TF_COLORS = { htf: 'border-l-cyan-400', mtf: 'border-l-blue-400', ltf: 'border-l-purple-400' }
const TF_KEYS = ['htf', 'mtf', 'ltf']

export default function SmcAnalysis(props) {
  const smc = () => props.smc
  const decision = createMemo(() => smc()?.decision)
  const timeframes = createMemo(() => smc()?.timeframes || {})

  return (
    <div class="glass rounded-2xl p-6 glass-hover">
      <div class="flex items-center justify-between mb-5">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🏗️ SMC Analysis</span>
        <Show when={decision()}>
          <span class={`px-5 py-2 rounded-lg text-xs font-black tracking-[0.15em] uppercase border ${decisionStyle(decision())}`}>
            {decision()}
          </span>
        </Show>
      </div>

      <Show when={!smc()}>
        <div class="text-center py-8 text-gray-600 text-xs">No SMC data available</div>
      </Show>

      <Show when={smc()}>
        <div class="space-y-2">
          <For each={TF_KEYS}>
            {(key) => (
              <Show when={timeframes()[key]}>
                <div class={`flex items-center gap-4 px-4 py-3 rounded-xl bg-white/[0.02] border-l-[3px] transition-all hover:bg-white/[0.04] ${TF_COLORS[key]}`}>
                  <span class="text-[10px] font-black tracking-widest text-cyan-400 min-w-[36px]">{TF_LABELS[key]}</span>
                  <span class="text-[9px] font-bold text-gray-500 min-w-[32px]">{timeframes()[key].interval}m</span>

                  <Show when={timeframes()[key].context}>
                    <div class="flex flex-wrap gap-1.5 flex-1">
                      <Show when={timeframes()[key].context.structure?.trend}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-blue-500/10 text-blue-400 border border-blue-500/15">
                          {timeframes()[key].context.structure.trend}
                        </span>
                      </Show>
                      <Show when={timeframes()[key].context.structure?.choch}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-purple-500/10 text-purple-300 border border-purple-500/15">CHoCH</span>
                      </Show>
                      <Show when={timeframes()[key].context.structure?.bos}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-emerald-500/10 text-emerald-400 border border-emerald-500/15">BOS</span>
                      </Show>
                      <Show when={timeframes()[key].context.premium_discount?.discount}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-emerald-500/10 text-emerald-400 border border-emerald-500/15">DISCOUNT</span>
                      </Show>
                      <Show when={timeframes()[key].context.premium_discount?.premium}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-rose-500/10 text-rose-400 border border-rose-500/15">PREMIUM</span>
                      </Show>
                      <Show when={timeframes()[key].context.liquidity?.sell_side_taken}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-amber-500/10 text-amber-400 border border-amber-500/15">SSL Taken</span>
                      </Show>
                      <Show when={timeframes()[key].context.liquidity?.buy_side_taken}>
                        <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-amber-500/10 text-amber-400 border border-amber-500/15">BSL Taken</span>
                      </Show>
                    </div>
                  </Show>
                </div>
              </Show>
            )}
          </For>

          <Show when={timeframes().ltf?.avrz}>
            <div class="flex items-center gap-4 px-4 py-3 rounded-xl bg-white/[0.02] border-l-[3px] border-l-violet-400 hover:bg-white/[0.04] transition-all">
              <span class="text-[10px] font-black tracking-widest text-violet-400 min-w-[36px]">AVRZ</span>
              <div class="flex gap-1.5">
                <span class={`px-2.5 py-1 rounded text-[9px] font-bold tracking-wider border ${timeframes().ltf.avrz.rejection ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/15' : 'bg-amber-500/10 text-amber-400 border-amber-500/15'}`}>
                  {timeframes().ltf.avrz.rejection ? 'Rejection ✓' : 'No Rejection'}
                </span>
                <Show when={timeframes().ltf.avrz.zone}>
                  <span class="px-2.5 py-1 rounded text-[9px] font-bold tracking-wider bg-blue-500/10 text-blue-400 border border-blue-500/15">
                    {timeframes().ltf.avrz.zone}
                  </span>
                </Show>
              </div>
            </div>
          </Show>

          <SmcConfluencePanel
            smcConfluenceMtf={smc()?.smc_confluence_mtf}
            smcConfluenceLtfSummary={smc()?.smc_confluence_ltf_summary}
            smcConfluenceMtfError={smc()?.smc_confluence_mtf_error}
          />
        </div>
      </Show>
    </div>
  )
}
