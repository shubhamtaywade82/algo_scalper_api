import { For } from 'solid-js'

const FIELD_DEFS = [
  { key: 'start', label: 'Start Time (HH:MM)', type: 'text', placeholder: '09:20' },
  { key: 'end', label: 'End Time (HH:MM)', type: 'text', placeholder: '15:10' },
  { key: 'days', label: 'Days (comma-separated)', type: 'text', placeholder: 'mon,tue,wed,thu,fri' }
]

export default function SchedulePanel(props) {
  const rules = () => props.value() || {}

  const update = (key, raw) => {
    props.onChange({ ...rules(), [key]: raw === '' ? undefined : raw })
  }

  return (
    <div class="glass p-5 rounded-2xl space-y-4">
      <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest block">Schedule</span>
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
