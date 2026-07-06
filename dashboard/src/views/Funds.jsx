import { Show } from 'solid-js'
import { useFunds } from '../stores/useFunds'
import Button from '../components/ui/Button'

export default function Funds() {
  const { funds, loading, error, fetchFunds } = useFunds()

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={fetchFunds}
          loading={loading()}
          leftIcon={<span>↻</span>}
        >
          {loading() ? 'Loading...' : 'Refresh'}
        </Button>
      </div>

      <Show when={error()}>
        <div class="glass rounded-2xl p-6 border border-rose-500/20">
          <p class="text-xs text-rose-400">{error()}</p>
        </div>
      </Show>

      <Show when={funds()}>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div class="glass p-5 rounded-2xl">
            <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Cash</span>
            <div class="text-2xl font-black text-white text-data mt-1">{funds().cash}</div>
          </div>
          <div class="glass p-5 rounded-2xl">
            <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Equity</span>
            <div class="text-2xl font-black text-white text-data mt-1">{funds().equity}</div>
          </div>
          <div class="glass p-5 rounded-2xl">
            <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">MTM</span>
            <div class="text-2xl font-black text-white text-data mt-1">{funds().mtm}</div>
          </div>
          <div class="glass p-5 rounded-2xl">
            <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Exposure</span>
            <div class="text-2xl font-black text-white text-data mt-1">{funds().exposure}</div>
          </div>
        </div>
      </Show>
    </div>
  )
}
