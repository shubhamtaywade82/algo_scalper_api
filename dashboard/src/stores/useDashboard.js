import { createSignal, onMount, onCleanup } from 'solid-js'
import cable from '../cable'

const POLL_INTERVAL_MS = 30000

export function useDashboard(onPositionChange) {
  const [mode, setMode] = createSignal('paper')
  const [connected, setConnected] = createSignal(false)
  const [stats, setStats] = createSignal({
    total_trades: 0,
    active_positions: 0,
    total_pnl_rupees: 0,
    realized_pnl_rupees: 0,
    unrealized_pnl_rupees: 0,
    win_rate: 0,
    winners: 0,
    losers: 0
  })
  const [balance, setBalance] = createSignal({ cash: 0, equity: 0, mtm: 0, exposure: 0 })
  const [indices, setIndices] = createSignal({ nifty: null, banknifty: null, sensex: null })
  const [system, setSystem] = createSignal({ ws_market_feed: false, ws_order_update: false, scheduler: 'unknown' })
  const [publicIpv4, setPublicIpv4] = createSignal('Unknown')
  const [publicIpv6, setPublicIpv6] = createSignal('Unknown')
  const [registeredIps, setRegisteredIps] = createSignal(null)
  const [circuitBreaker, setCircuitBreaker] = createSignal({})
  const [lastUpdated, setLastUpdated] = createSignal(null)
  const [recentSignals, setRecentSignals] = createSignal([])
  const [config, setConfig] = createSignal({ risk: {}, signals: {}, time_restrictions: {} })

  let subscription = null
  let pollTimer = null

  function applyData(data) {
    if (data.mode != null) setMode(data.mode)
    if (data.balance) setBalance(data.balance)
    if (data.today) setStats(data.today)
    if (data.indices) setIndices(data.indices)
    if (data.system) setSystem(data.system)
    if (data.public_ipv4) setPublicIpv4(data.public_ipv4)
    if (data.public_ipv6) setPublicIpv6(data.public_ipv6)
    if (data.registered_ips !== undefined) setRegisteredIps(data.registered_ips)
    if (data.circuit_breaker) setCircuitBreaker(data.circuit_breaker)
    if (data.recent_signals) setRecentSignals(data.recent_signals)
    if (data.config) setConfig(data.config)
    if (data.timestamp) setLastUpdated(data.timestamp)
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

  onMount(() => {
    fetchInitial()
    pollTimer = setInterval(fetchInitial, POLL_INTERVAL_MS)

    subscription = cable.subscriptions.create('DashboardChannel', {
      connected() {
        setConnected(true)
      },
      disconnected() {
        setConnected(false)
      },
      received(data) {
        if (data.type === 'stats') {
          applyData(data)
        } else if (data.type === 'position_activated' || data.type === 'position_exited') {
          onPositionChange?.()
          fetchInitial()
        } else if (data.type === 'circuit_breaker') {
          setCircuitBreaker({ tripped: data.tripped, reason: data.reason, at: data.at })
        }
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { mode, connected, stats, balance, indices, system, publicIpv4, publicIpv6, registeredIps, circuitBreaker, lastUpdated, recentSignals, config }
}
