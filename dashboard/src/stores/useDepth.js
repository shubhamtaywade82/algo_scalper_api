import { createSignal, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'

const POLL_MS = 5000

export function useDepth(symbol = 'NIFTY') {
  const [depth, setDepth] = createSignal({ bid: [], ask: [], totalBidQty: 0, totalAskQty: 0 })
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  let timer

  async function fetchDepth() {
    setLoading(true)
    try {
      const res = await apiClient.get(`/depth?symbol=${encodeURIComponent(symbol)}`)
      setDepth(res.data)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  function startPolling() {
    fetchDepth()
    timer = setInterval(fetchDepth, POLL_MS)
  }

  function stopPolling() {
    clearInterval(timer)
  }

  onCleanup(() => clearInterval(timer))

  return { depth, loading, error, fetchDepth, startPolling, stopPolling }
}
