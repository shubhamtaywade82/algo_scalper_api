import { createSignal, onMount } from 'solid-js'
import { usePositions } from '../stores/usePositions'
import OpenPositions from '../components/OpenPositions'
import ClosedTrades from '../components/ClosedTrades'
import PositionDetailDrawer from '../components/positions/PositionDetailDrawer'
import { useDashboardContext } from '../context/DashboardContext'

export default function Positions() {
  const { open, fetchPositions, closeOpenPosition, closingPositionId, connected, isStale } = usePositions()
  const ctx = useDashboardContext()
  const [selectedId, setSelectedId] = createSignal(null)

  onMount(() => fetchPositions())

  return (
    <div class="space-y-8">
      <OpenPositions
        positions={open()}
        onClosePosition={closeOpenPosition}
        closingPositionId={closingPositionId()}
        onSelectPosition={setSelectedId}
        wsConnected={connected()}
        wsStale={isStale()}
        circuitBreaker={ctx?.circuitBreaker?.()}
      />

      <ClosedTrades onSelect={setSelectedId} />

      <PositionDetailDrawer positionId={selectedId()} onClose={() => setSelectedId(null)} />
    </div>
  )
}
