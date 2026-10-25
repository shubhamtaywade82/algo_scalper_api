// dashboard/src/views/Portfolio.jsx
import { createSignal, Show } from 'solid-js'
import { useSearchParams } from '@solidjs/router'
import Positions from './Positions'
import Ledger from './Ledger'
import Holdings from './Holdings'
import Funds from './Funds'

const TABS = [
  { id: 'positions', label: 'Positions' },
  { id: 'orders', label: 'Orders & Ledger' },
  { id: 'holdings', label: 'Holdings' },
  { id: 'funds', label: 'Funds & Margin' },
]

export default function Portfolio(props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const currentTab = () => props.defaultTab || searchParams.tab || 'positions'
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

      <Show when={activeTab() === 'positions'}>
        <Positions />
      </Show>
      <Show when={activeTab() === 'orders'}>
        <Ledger />
      </Show>
      <Show when={activeTab() === 'holdings'}>
        <Holdings />
      </Show>
      <Show when={activeTab() === 'funds'}>
        <Funds />
      </Show>
    </div>
  )
}
