// Backend endpoint: GET /api/holdings
// WebSocket: HoldingsChannel — receives { type: "holdings_changed" } signals to refetch
import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import cable from '../cable'

const POLL_MS = 15000

export function useHoldings() {
  const [holdings, setHoldings] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  let subscription = null
  let pollTimer = null

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
    pollTimer = setInterval(fetchHoldings, POLL_MS)

    subscription = cable.subscriptions.create('HoldingsChannel', {
      connected() {
        console.log('✅ [WS:Holdings] Connected')
      },
      received(data) {
        console.debug('⚡ [WS:Holdings] Update:', data)
        if (data.type === 'holdings_changed') fetchHoldings()
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { holdings, loading, error, fetchHoldings }
}
