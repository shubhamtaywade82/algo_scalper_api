import { createSignal, onMount, onCleanup } from 'solid-js'
import toast from 'solid-toast'

export function useAlpha() {
  const [status, setStatus] = createSignal({
    enabled: false,
    indices: [],
    strategies: [],
    auto_execute_threshold: 0.75,
    risk_stats: {},
    risk_limits: {}
  })
  const [history, setHistory] = createSignal([])
  const [performance, setPerformance] = createSignal({ by_source: {}, total_executed: 0 })
  const [loading, setLoading] = createSignal(false)
  const [scanning, setScanning] = createSignal(false)

  async function fetchStatus() {
    try {
      const res = await fetch('/api/alpha/status')
      if (res.ok) setStatus(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchStatus failed:', e)
    }
  }

  async function fetchHistory() {
    try {
      const res = await fetch('/api/alpha/history')
      if (res.ok) setHistory(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchHistory failed:', e)
    }
  }

  async function fetchPerformance() {
    try {
      const res = await fetch('/api/alpha/performance')
      if (res.ok) setPerformance(await res.json())
    } catch (e) {
      console.error('[AlphaStore] fetchPerformance failed:', e)
    }
  }

  async function triggerScan() {
    setScanning(true)
    try {
      const res = await fetch('/api/alpha/scan', { method: 'POST' })
      const data = await res.json()
      if (res.ok) {
        toast.success(`Scan complete: Found ${data.count} signals`)
        fetchHistory()
      } else {
        toast.error(`Scan failed: ${data.reason || 'Unknown error'}`)
      }
    } catch (e) {
      toast.error(`Scan failed: ${e.message}`)
    } finally {
      setScanning(false)
    }
  }

  async function executeSignal(signal) {
    try {
      const res = await fetch('/api/alpha/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ signal })
      })
      const data = await res.json()
      if (res.ok) {
        toast.success(`Order placed: ${data.order_id}`)
        fetchHistory()
      } else {
        toast.error(`Execution failed: ${data.reason || 'Unknown error'}`)
      }
    } catch (e) {
      toast.error(`Execution failed: ${e.message}`)
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
    status, history, performance, loading, scanning,
    fetchStatus, fetchHistory, fetchPerformance, triggerScan, executeSignal
  }
}
