// dashboard/src/views/StrategiesHub.jsx
import { createSignal, Show } from 'solid-js'
import { useSearchParams } from '@solidjs/router'
import Strategies from './Strategies'
import Alpha from './Alpha'
import Signals from './Signals'
import Backtester from './Backtester'
import Replay from './Replay'

const TABS = [
  { id: 'strategies', label: 'Strategies' },
  { id: 'alpha', label: 'Alpha & Risk' },
  { id: 'signals', label: 'Signals Audit' },
  { id: 'backtester', label: 'Backtester' },
  { id: 'replay', label: 'Replay' },
]

export default function StrategiesHub(props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const currentTab = () => props.defaultTab || searchParams.tab || 'strategies'
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

      <Show when={activeTab() === 'strategies'}>
        <Strategies />
      </Show>
      <Show when={activeTab() === 'alpha'}>
        <Alpha />
      </Show>
      <Show when={activeTab() === 'signals'}>
        <Signals />
      </Show>
      <Show when={activeTab() === 'backtester'}>
        <Backtester />
      </Show>
      <Show when={activeTab() === 'replay'}>
        <Replay />
      </Show>
    </div>
  )
}
