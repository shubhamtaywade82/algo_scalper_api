// DEPENDENCY: backend endpoint GET /api/holdings
// Expected shape: [{ id, symbol, quantity, avg_price, ltp, pnl, pnl_pct, exchange }]
// TODO: Wire to ActionCable HoldingsChannel when available

import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'

const POLL_MS = 15000

export function useHoldings() {
  const [holdings, setHoldings] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchHoldings() {
    setLoading(true)
    try {
      const res = await apiClient.get('/holdings')
      setHoldings(res.data || [])
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  onMount(() => {
    fetchHoldings()
    const timer = setInterval(fetchHoldings, POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  return { holdings, loading, error, fetchHoldings }
}
