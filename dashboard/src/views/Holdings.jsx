// DEPENDENCY: backend — requires /api/holdings endpoint (not yet implemented)
// This component provides a skeleton that will render when the endpoint is built.
import { createSignal, onMount } from 'solid-js'
import { Show, For } from 'solid-js'

export default function Holdings() {
  const [holdings, setHoldings] = createSignal([])
  const [loading, setLoading] = createSignal(true)
  const [error, setError] = createSignal(null)

  async function fetchHoldings() {
    setLoading(true)
    setError(null)
    try {
      // TODO: backend — implement GET /api/holdings returning holdings list
      // Expected response: { holdings: [{ symbol, quantity, avg_price, ltp, pnl, segment }] }
      const res = await fetch('/api/holdings')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setHoldings(data.holdings || [])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  onMount(fetchHoldings)

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-black text-white uppercase tracking-widest">Holdings</h1>
        <button
          onClick={fetchHoldings}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
        >
          {loading() ? '↻ Loading...' : '↻ Refresh'}
        </button>
      </div>

      {/* DEPENDENCY: backend — this page requires /api/holdings to be implemented */}
      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: GET /api/holdings not yet implemented
        </p>
      </div>

      <Show when={error()}>
        <div class="glass rounded-2xl p-6 border border-rose-500/20">
          <p class="text-xs text-rose-400">Failed to load holdings: {error()}</p>
        </div>
      </Show>

      <Show when={!loading() && !error() && holdings().length === 0}>
        <div class="glass rounded-2xl p-12 text-center">
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No holdings data available</p>
        </div>
      </Show>

      <Show when={holdings().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full border-collapse text-sm">
              <thead>
                <tr class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 bg-white/[0.02]">
                  <th class="text-left px-6 py-4 font-black">Symbol</th>
                  <th class="text-right px-4 py-4 font-black">Quantity</th>
                  <th class="text-right px-4 py-4 font-black">Avg Price</th>
                  <th class="text-right px-4 py-4 font-black">LTP</th>
                  <th class="text-right px-4 py-4 font-black">P&L</th>
                  <th class="text-left px-4 py-4 font-black">Segment</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/5">
                <For each={holdings()}>
                  {(h) => (
                    <tr class="hover:bg-white/[0.02] transition-colors">
                      <td class="px-6 py-4 font-bold text-white">{h.symbol}</td>
                      <td class="px-4 py-4 text-right text-data">{h.quantity}</td>
                      <td class="px-4 py-4 text-right text-data text-gray-400">{h.avg_price}</td>
                      <td class="px-4 py-4 text-right text-data text-white">{h.ltp}</td>
                      <td class={`px-4 py-4 text-right text-data font-bold ${Number(h.pnl) >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        {h.pnl}
                      </td>
                      <td class="px-4 py-4 text-gray-500">{h.segment}</td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>
      </Show>
    </div>
  )
}
