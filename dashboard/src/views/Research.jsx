import { createSignal } from 'solid-js'
import { Tabs } from '../components/ui/Tabs'
import SignalPipelinePanel from '../components/research/SignalPipelinePanel'
import LifecycleBoardPanel from '../components/research/LifecycleBoardPanel'

const TABS = [
  { value: 'signals', label: 'Signal Pipeline' },
  { value: 'lifecycle', label: 'Premium Lifecycle Board' }
]

export default function Research() {
  const [tab, setTab] = createSignal('signals')

  return (
    <div class="flex flex-col gap-6">
      <div class="flex items-center justify-between px-2">
        <h2 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-cyan-500" />
          Research Kernel
        </h2>
        <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter">
          Real DhanHQ rolling-option data — every run below is a live fetch, not a simulation
        </span>
      </div>

      <Tabs
        tabs={TABS}
        value={tab()}
        onChange={setTab}
        tabBarClass="px-2"
      >
        {tab() === 'signals' ? <SignalPipelinePanel /> : <LifecycleBoardPanel />}
      </Tabs>
    </div>
  )
}
