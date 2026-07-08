import { Show, createEffect, For } from 'solid-js'
import { usePositionDetail } from '../../stores/usePositionDetail'
import AnimatedNumber from '../AnimatedNumber'

function Field(props) {
  return (
    <div class="flex flex-col">
      <span class="text-[9px] text-gray-500 font-black uppercase tracking-wider mb-1">{props.label}</span>
      <span class="text-sm text-gray-200 font-bold">{props.value ?? '—'}</span>
    </div>
  )
}

export default function PositionDetailDrawer(props) {
  const { detail, loading, error, fetchDetail, clear } = usePositionDetail()

  createEffect(() => {
    const id = props.positionId
    if (id != null) fetchDetail(id)
    else clear()
  })

  function handleKeydown(e) {
    if (e.key === 'Escape') props.onClose()
  }

  return (
    <Show when={props.positionId != null}>
      <div class="fixed inset-0 z-50 flex justify-end" onKeyDown={handleKeydown}>
        <div class="fixed inset-0 bg-black/60" onClick={() => props.onClose()} />
        <div class="relative w-full max-w-md h-full bg-gray-900 border-l border-white/10 overflow-y-auto p-6 space-y-6">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-black text-white uppercase tracking-tight">Position Detail</h2>
            <button type="button" class="text-gray-400 hover:text-white text-xl leading-none" onClick={() => props.onClose()}>&times;</button>
          </div>

          <Show when={loading()}>
            <div class="text-center text-gray-500 text-sm py-10">Loading…</div>
          </Show>

          <Show when={error()}>
            <div class="text-center text-rose-400 text-sm py-10">Failed to load: {error()}</div>
          </Show>

          <Show when={!loading() && detail()}>
            {(d) => (
              <div class="space-y-6">
                <div class="flex items-center justify-between">
                  <div>
                    <div class="text-xl font-black text-white uppercase">{d().symbol}</div>
                    <div class="text-[10px] text-gray-500 uppercase tracking-wider">
                      {d().side} · Qty {d().quantity} · {d().paper ? 'Paper' : 'Live'}
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                  <Field label="Entry Price" value={<AnimatedNumber value={d().entry_price} decimals={2} />} />
                  <Field label={d().exit_price != null ? 'Exit Price' : 'LTP'} value={<AnimatedNumber value={d().exit_price ?? d().ltp} decimals={2} />} />
                  <Field label="PnL" value={<AnimatedNumber value={d().pnl} showSign currency absolute decimals={2} pnlColor />} />
                  <Field label="PnL %" value={<AnimatedNumber value={d().pnl_pct} showSign suffix="%" decimals={2} pnlColor />} />
                  <Field label="High Water Mark" value={<AnimatedNumber value={d().hwm_pnl} currency decimals={2} />} />
                </div>

                <div class="space-y-2">
                  <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Trailing State</h3>
                  <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                    <Field label="HWM PnL %" value={d().trailing_state?.hwm_pnl_pct} />
                    <Field label="Secured SL" value={d().trailing_state?.secured_sl_price} />
                    <Field label="Breakeven Locked" value={d().trailing_state?.breakeven_locked ? 'Yes' : 'No'} />
                    <Field label="Profit Zone" value={d().trailing_state?.profit_zone_state} />
                  </div>
                </div>

                <div class="space-y-2">
                  <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Entry Context</h3>
                  <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                    <Field label="IV at Entry" value={d().entry_context?.iv_at_entry} />
                    <Field label="VIX at Entry" value={d().entry_context?.vix_at_entry} />
                    <Field label="DTE at Entry" value={d().entry_context?.dte_at_entry} />
                    <Field label="ATM Strike" value={d().entry_context?.atm_strike} />
                    <Field label="Expiry" value={d().entry_context?.expiry_date} />
                    <Field label="Entry Timeframe" value={d().entry_context?.entry_tf} />
                    <Field label="Alpha Source" value={d().entry_context?.alpha_source} />
                    <Field label="Entry Path" value={d().entry_context?.entry_path} />
                  </div>
                </div>

                <Show when={d().exit_block}>
                  <div class="space-y-2">
                    <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Exit</h3>
                    <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                      <Field label="Reason" value={d().exit_block.exit_reason} />
                      <Field label="Path" value={d().exit_block.exit_path} />
                      <Field label="Classification" value={d().exit_block.exit_classification} />
                      <Field label="Exited At" value={d().exit_block.exited_at && new Date(d().exit_block.exited_at).toLocaleString('en-IN')} />
                    </div>
                  </div>
                </Show>

                <Show when={d().strategy_signal}>
                  <div class="space-y-2">
                    <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Strategy & Guard Trail</h3>
                    <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                      <Field label="Strategy" value={d().strategy_signal.strategy_slug} />
                      <Field label="Action" value={d().strategy_signal.action} />
                      <Field label="Outcome" value={d().strategy_signal.outcome} />
                      <Field label="Reason" value={d().strategy_signal.reason} />
                    </div>
                    <Show when={d().strategy_signal.guard_results?.length}>
                      <ul class="space-y-1">
                        <For each={d().strategy_signal.guard_results}>
                          {(g) => (
                            <li class="flex items-center justify-between text-xs bg-white/[0.02] border border-white/5 rounded-lg px-3 py-2">
                              <span class="text-gray-300">{g.guard?.split('::').pop()}</span>
                              <span class={`font-black uppercase text-[9px] px-2 py-0.5 rounded-full ${g.result === 'pass' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
                                {g.result}
                              </span>
                            </li>
                          )}
                        </For>
                      </ul>
                    </Show>
                  </div>
                </Show>

                <details class="bg-white/[0.02] border border-white/5 rounded-xl p-4">
                  <summary class="text-[10px] text-gray-500 font-black uppercase tracking-widest cursor-pointer">Raw Data</summary>
                  <pre class="text-[10px] text-gray-400 mt-3 overflow-x-auto">{JSON.stringify({ config_snapshot: d().config_snapshot, meta: d().meta }, null, 2)}</pre>
                </details>
              </div>
            )}
          </Show>
        </div>
      </div>
    </Show>
  )
}
