// DEPENDENCY: backend — requires /api/funds endpoint (not yet implemented)
import { createSignal, onMount } from 'solid-js'
import { Show } from 'solid-js'

export default function Funds() {
  const [funds, setFunds] = createSignal(null)
  const [loading, setLoading] = createSignal(true)
  const [error, setError] = createSignal(null)

  async function fetchFunds() {
    setLoading(true)
    setError(null)
    try {
      // TODO: backend — implement GET /api/funds returning fund details
      // Expected response: { cash, equity, mtm, exposure, margin_used }
      const res = await fetch('/api/funds')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setFunds(await res.json())
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  onMount(fetchFunds)

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-black text-white uppercase tracking-widest">Funds</h1>
        <button
          onClick={fetchFunds}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
        >
          {loading() ? '↻' : '↻'} Refresh
        </button>
      </div>

      {/* DEPENDENCY: backend */}
      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: GET /api/funds not yet implemented
        </p>
        <p class="text-[9px] text-gray-500 mt-2">
          Planned endpoints: GET /api/funds/balance, POST /api/funds/add, POST /api/funds/withdraw
        </p>
      </div>

      <Show when={error()}>
        <div class="text-rose-400 text-xs">{error()}</div>
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
