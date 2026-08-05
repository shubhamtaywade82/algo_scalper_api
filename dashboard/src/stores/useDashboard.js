import { createSignal, onMount, onCleanup } from 'solid-js'
import toast from 'solid-toast'
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
  const [indices, setIndices] = createSignal({
    nifty: null,
    banknifty: null,
    sensex: null,
    nifty_prev_close: null,
    banknifty_prev_close: null,
    sensex_prev_close: null
  })
  const [subscribedIndices, setSubscribedIndices] = createSignal([])
  const [optionsBuying, setOptionsBuying] = createSignal({ nifty: {}, banknifty: {}, sensex: {} })
  const [isStale, setIsStale] = createSignal(false)
  const [system, setSystem] = createSignal({ ws_market_feed: false, ws_order_update: false, scheduler: 'unknown' })
  const [publicIpv4, setPublicIpv4] = createSignal('Unknown')
  const [publicIpv6, setPublicIpv6] = createSignal('Unknown')
  const [registeredIps, setRegisteredIps] = createSignal(null)
  const [circuitBreaker, setCircuitBreaker] = createSignal({})
  const [lastUpdated, setLastUpdated] = createSignal(null)
  const [recentSignals, setRecentSignals] = createSignal([])
  const [strategiesSummary, setStrategiesSummary] = createSignal([])
  const [config, setConfig] = createSignal({ risk: {}, signals: {}, time_restrictions: {} })

  let subscription = null
  let pollTimer = null

  function applyData(data) {
    if (data.mode != null) setMode(data.mode)
    if (data.balance) setBalance(data.balance)
    if (data.today) setStats(data.today)
    else if (data.stats) setStats(data.stats)
    else if (data.today_stats) setStats(data.today_stats)

    // Flat index updates or nested updates
    const current = { ...indices() }
    let changed = false
    
    // Search top-level AND nested under 'indices' or 'market_indices'
    const sources = [data, data.indices, data.market_indices].filter(Boolean)
    
    for (const src of sources) {
      if (src.nifty) { current.nifty = src.nifty; changed = true }
      if (src.banknifty) { current.banknifty = src.banknifty; changed = true }
      if (src.sensex) { current.sensex = src.sensex; changed = true }
      if (src.nifty_prev_close !== undefined && src.nifty_prev_close !== null) { current.nifty_prev_close = src.nifty_prev_close; changed = true }
      if (src.banknifty_prev_close !== undefined && src.banknifty_prev_close !== null) { current.banknifty_prev_close = src.banknifty_prev_close; changed = true }
      if (src.sensex_prev_close !== undefined && src.sensex_prev_close !== null) { current.sensex_prev_close = src.sensex_prev_close; changed = true }
    }

    if (changed) {
      console.debug('📈 [Dashboard:Indices] Updated:', current)
      setIndices(current)
    }

    if (data.system) {
      // pnl_updater_running and ws_order_update are checked via in-process .running?
      // in the web process — they are always false there. Only the WS heartbeat
      // (type: "stats") comes from the trading process and has the real values.
      // Preserve those fields across REST polls so they don't flicker to false.
      const fromWs = !!data.type
      setSystem(prev => {
        const next = { ...prev, ...data.system }
        if (!fromWs) {
          next.pnl_updater_running = prev.pnl_updater_running
          next.ws_order_update     = prev.ws_order_update
        }
        return next
      })
    }
    if (data.public_ipv4) setPublicIpv4(data.public_ipv4)
    if (data.public_ipv6) setPublicIpv6(data.public_ipv6)
    if (data.registered_ips !== undefined) setRegisteredIps(data.registered_ips)
    if (data.circuit_breaker) setCircuitBreaker(data.circuit_breaker)
    if (data.recent_signals) setRecentSignals(data.recent_signals)
    if (data.strategies_summary) setStrategiesSummary(data.strategies_summary)
    if (data.config) setConfig(data.config)
    if (data.subscribed_indices) setSubscribedIndices(data.subscribed_indices)

    setLastUpdated(data.timestamp || new Date().toISOString())
  }

  const fetchInitial = async () => {
    try {
      const res = await fetch('/api/dashboard', { headers: { 'Accept': 'application/json' } })
      if (res.ok) {
        const data = await res.json()
        applyData(data)
      }
    } catch (e) {
      console.error('[useDashboard] fetchInitial error:', e)
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
        console.debug('⚡ [WS:Dashboard] Update:', data)
        setIsStale(false)
        applyData(data)
        
        if (data.type === 'position_activated') {
          toast.success(`Entry Taken: ${data.position.symbol} @ ₹${data.position.entry_price}`)
          onPositionChange?.()
          fetchInitial()
        } else if (data.type === 'position_exited') {
          const pnlText = data.position.pnl >= 0 ? `+₹${data.position.pnl}` : `-₹${Math.abs(data.position.pnl)}`
          if (data.position.pnl >= 0) {
            toast.success(`Position Exited: ${data.position.symbol} (${pnlText})`)
          } else {
            toast.error(`Position Exited: ${data.position.symbol} (${pnlText})`)
          }
          onPositionChange?.()
          fetchInitial()
        } else if (data.type === 'toast') {
          const body = data.title ? `${data.title}\n${data.message}` : data.message
          if (data.level === 'error') toast.error(body)
          else if (data.level === 'warning') toast(body, { icon: '⚠️' })
          else toast.success(body)
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

  return {
    mode, connected, isStale, stats, balance, indices, subscribedIndices, system,
    publicIpv4, publicIpv6, registeredIps, circuitBreaker, lastUpdated, recentSignals, strategiesSummary, config,
    marketStatus: () => {
      const sys = system()
      if (sys?.market_status) return sys.market_status
      const now = new Date()
      const hour = now.getHours()
      const minute = now.getMinutes()
      const currentTime = hour * 60 + minute
      // Market hours: 9:15 - 15:30 IST
      return (currentTime >= 9 * 60 + 15 && currentTime <= 15 * 60 + 30) ? 'open' : 'closed'
    }
  }
}
