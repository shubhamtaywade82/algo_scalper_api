import { ref, onMounted, onUnmounted } from 'vue'
import cable from '../cable'

const POLL_INTERVAL_MS = 5000

export function useDashboard(onPositionChange) {
  const mode = ref('paper')
  const connected = ref(false)
  const stats = ref({
    total_trades: 0,
    active_positions: 0,
    total_pnl_rupees: 0,
    realized_pnl_rupees: 0,
    unrealized_pnl_rupees: 0,
    win_rate: 0,
    winners: 0,
    losers: 0
  })
  const balance = ref({ cash: 0, equity: 0, mtm: 0, exposure: 0 })
  const indices = ref({ nifty: null, banknifty: null, sensex: null })
  const system = ref({ ws_market_feed: false, ws_order_update: false, scheduler: 'unknown' })
  const circuitBreaker = ref({})
  const lastUpdated = ref(null)
  const recentSignals = ref([])
  const config = ref({ risk: {}, signals: {}, time_restrictions: {} })

  let subscription = null
  let pollTimer = null

  function applyData(data) {
    if (data.mode != null) mode.value = data.mode
    if (data.balance) balance.value = data.balance
    if (data.today) stats.value = data.today
    if (data.indices) indices.value = data.indices
    if (data.system) system.value = data.system
    if (data.circuit_breaker) circuitBreaker.value = data.circuit_breaker
    if (data.recent_signals) recentSignals.value = data.recent_signals
    if (data.config) config.value = data.config
    if (data.timestamp) lastUpdated.value = data.timestamp
  }

  async function fetchInitial() {
    try {
      const res = await fetch('/api/dashboard')
      const data = await res.json()
      applyData(data)
    } catch (e) {
      console.error('[Dashboard] fetch failed:', e)
    }
  }

  onMounted(() => {
    fetchInitial()

    // Polling — reliable baseline; ActionCable pushes faster when connected
    pollTimer = setInterval(fetchInitial, POLL_INTERVAL_MS)

    subscription = cable.subscriptions.create('DashboardChannel', {
      connected() {
        connected.value = true
      },
      disconnected() {
        connected.value = false
      },
      received(data) {
        if (data.type === 'stats') {
          applyData(data)
        } else if (data.type === 'position_activated' || data.type === 'position_exited') {
          onPositionChange?.()
          fetchInitial()
        }
      }
    })
  })

  onUnmounted(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { mode, connected, stats, balance, indices, system, circuitBreaker, lastUpdated, recentSignals, config }
}
