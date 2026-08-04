import { For } from 'solid-js'

const FIELD_DEFS = [
  { key: 'max_risk_per_trade_pct', label: 'Max Risk Per Trade (decimal)', type: 'text', placeholder: '0.01' },
  { key: 'max_concurrent_positions', label: 'Max Concurrent Positions', type: 'number', placeholder: '3' },
  { key: 'daily_loss_limit_pct', label: 'Daily Loss Limit (decimal)', type: 'text', placeholder: '0.05' },
  { key: 'max_positions_per_instrument', label: 'Max Positions Per Instrument', type: 'number', placeholder: '1' }
]

export default function RiskManagementPanel(props) {
  const rules = () => props.value() || {}

  const update = (key, raw) => {
    props.onChange({ ...rules(), [key]: raw === '' ? undefined : raw })
  }

  return (
    <div class="glass p-5 rounded-2xl space-y-4">
      <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest block">Risk Management</span>
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
