// dashboard/src/views/OptionScalper.jsx
import { createSignal } from 'solid-js'
import { useOptionChain } from '../stores/useOptionChain'
import { useDashboardContext } from '../context/DashboardContext'
import OptionChainTable from '../components/OptionChainTable'
import OpenPositions from '../components/OpenPositions'

const INDICES = ['NIFTY', 'BANKNIFTY', 'SENSEX']

export default function OptionScalper() {
  const [selectedIndex, setSelectedIndex] = createSignal('NIFTY')
  const { chain, isStale } = useOptionChain(selectedIndex)
  const { open, circuitBreaker, positionsConnected, positionsStale } = useDashboardContext()

  return (
    <div>
      <div class="flex gap-2 mb-4">
        {INDICES.map(idx => (
          <button
            class={`px-4 py-2 rounded-lg text-xs font-black uppercase tracking-widest border ${selectedIndex() === idx ? 'bg-primary-500/20 border-primary-500/40 text-primary-300' : 'bg-white/5 border-white/10 text-gray-400'}`}
            onClick={() => setSelectedIndex(idx)}
          >
            {idx}
          </button>
        ))}
      </div>

      <OptionChainTable indexKey={selectedIndex()} chain={chain()} isStale={isStale()} />

      <OpenPositions
        positions={open()}
        circuitBreaker={circuitBreaker()}
        wsConnected={positionsConnected()}
        wsStale={positionsStale()}
      />
    </div>
  )
}
