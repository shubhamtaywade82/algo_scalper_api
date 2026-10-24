import { createSignal, onMount, onCleanup } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'

export function useAlpha() {
  const [status, setStatus] = createSignal({
    enabled: false,
    indices: [],
    strategies: [],
    risk_stats: {},
    risk_limits: {}
  })
  const [history, setHistory] = createSignal([])
  const [performance, setPerformance] = createSignal({ by_source: {}, total_executed: 0 })
  const [loading, setLoading] = createSignal(false)

  async function fetchStatus() {
    try {
      const res = await fetch('/api/alpha/status', { headers: dashboardApiHeaders() })
      if (res.ok) setStatus(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchStatus failed:', e)
    }
  }

  async function fetchHistory() {
    try {
      const res = await fetch('/api/alpha/history', { headers: dashboardApiHeaders() })
      if (res.ok) setHistory(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchHistory failed:', e)
    }
  }

  async function fetchPerformance() {
    try {
      const res = await fetch('/api/alpha/performance', { headers: dashboardApiHeaders() })
      if (res.ok) setPerformance(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchPerformance failed:', e)
    }
  }

  onMount(() => {
    fetchStatus()
    fetchHistory()
    fetchPerformance()

    const timer = setInterval(() => {
      fetchStatus()
      fetchHistory()
    }, 10000)

    onCleanup(() => clearInterval(timer))
  })

  return {
    status, history, performance, loading,
    fetchStatus, fetchHistory, fetchPerformance
  }
}
