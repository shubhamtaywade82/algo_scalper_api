// DEPENDENCY: backend — requires /api/alerts CRUD endpoints (not yet implemented)
import { createSignal, onMount } from 'solid-js'
import { Show } from 'solid-js'

const ALERT_TYPES = [
  { value: 'price', label: 'Price Alert' },
  { value: 'pnl', label: 'P&L Alert' },
  { value: 'technical', label: 'Technical Alert' },
  { value: 'system', label: 'System Alert' },
]

export default function Alerts() {
  const [alerts, setAlerts] = createSignal([])
  const [loading, setLoading] = createSignal(true)

  async function fetchAlerts() {
    setLoading(true)
    try {
      // TODO: backend — implement GET /api/alerts, POST /api/alerts, PATCH /api/alerts/:id, DELETE /api/alerts/:id
      const res = await fetch('/api/alerts')
      if (res.ok) setAlerts(await res.json())
    } catch {
      /* expected */
    } finally {
      setLoading(false)
    }
  }

  onMount(fetchAlerts)

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-black text-white uppercase tracking-widest">Alerts</h1>
        <button
          onClick={fetchAlerts}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
        >
          {loading() ? '↻' : '↻'} Refresh
        </button>
      </div>

      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: /api/alerts CRUD endpoints not yet implemented
        </p>
        <div class="mt-4 space-y-2 text-[10px] text-gray-500 font-mono">
          <p>Planned endpoints:</p>
          <p class="ml-4">· GET /api/alerts — List alerts</p>
          <p class="ml-4">· POST /api/alerts — Create alert</p>
          <p class="ml-4">· PATCH /api/alerts/:id — Update alert</p>
          <p class="ml-4">· DELETE /api/alerts/:id — Delete alert</p>
        </div>
      </div>

      <Show when={alerts().length === 0 && !loading()}>
        <div class="glass rounded-2xl p-12 text-center">
          <div class="text-3xl mb-3">🔔</div>
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No alerts configured</p>
          <p class="text-[10px] text-gray-600 mt-2">Set up price, P&L, or technical alerts</p>
        </div>
      </Show>
    </div>
  )
}
