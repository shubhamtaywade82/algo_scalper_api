import { For } from 'solid-js'

const FIELD_DEFS = [
  { key: 'stop_loss_pct', label: 'Stop Loss (decimal, e.g. 0.05)', type: 'text', placeholder: '0.05' },
  { key: 'take_profit_pct', label: 'Take Profit (decimal)', type: 'text', placeholder: '0.10' },
  { key: 'trailing_activation_pct', label: 'Trailing Activation (decimal)', type: 'text', placeholder: '0.03' },
  { key: 'time_stop_minutes', label: 'Time Stop (minutes)', type: 'number', placeholder: '45' }
]

export default function ExitRulesPanel(props) {
  const rules = () => props.value() || {}

  const update = (key, raw) => {
    props.onChange({ ...rules(), [key]: raw === '' ? undefined : raw })
  }

  return (
    <div class="glass p-5 rounded-2xl space-y-4">
      <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest block">Exit Rules</span>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <For each={FIELD_DEFS}>
          {(f) => (
            <label class="block space-y-1">
              <span class="text-[9px] font-bold text-gray-500 uppercase tracking-wider">{f.label}</span>
              <input
                type={f.type}
                value={rules()[f.key] ?? ''}
                placeholder={f.placeholder}
                onInput={(e) => update(f.key, e.target.value)}
                class="w-full bg-white/5 border border-white/5 rounded-lg px-3 py-1.5 text-xs text-white outline-none font-mono"
              />
            </label>
          )}
        </For>
      </div>
    </div>
  )
}
