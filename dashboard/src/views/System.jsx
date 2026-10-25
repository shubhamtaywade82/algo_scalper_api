// dashboard/src/views/System.jsx
import { createSignal, Show } from 'solid-js'
import { useSearchParams } from '@solidjs/router'
import Settings from './Settings'
import Scheduler from './Scheduler'
import Logs from './Logs'
import Alerts from './Alerts'

const TABS = [
  { id: 'settings', label: 'Settings & Config' },
  { id: 'scheduler', label: 'Scheduler' },
  { id: 'logs', label: 'System Logs' },
  { id: 'alerts', label: 'Alerts' },
]

export default function System(props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const currentTab = () => props.defaultTab || searchParams.tab || 'settings'
  const [activeTab, setActiveTab] = createSignal(currentTab())

  const handleSelect = (id) => {
    setActiveTab(id)
    setSearchParams({ tab: id })
  }

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between border-b border-white/5 pb-3">
        <div class="flex items-center gap-2">
          {TABS.map((t) => (
            <button
              type="button"
              class={`px-4 py-2 rounded-xl text-xs font-black uppercase tracking-wider transition-all cursor-pointer ${
                activeTab() === t.id
                  ? 'bg-primary-600 text-white shadow-lg'
                  : 'text-gray-400 hover:text-white bg-white/5 hover:bg-white/10'
              }`}
              onClick={() => handleSelect(t.id)}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <Show when={activeTab() === 'settings'}>
        <Settings />
      </Show>
      <Show when={activeTab() === 'scheduler'}>
        <Scheduler />
      </Show>
      <Show when={activeTab() === 'logs'}>
        <Logs />
      </Show>
      <Show when={activeTab() === 'alerts'}>
        <Alerts />
      </Show>
    </div>
  )
}
