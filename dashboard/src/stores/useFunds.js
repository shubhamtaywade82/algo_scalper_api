// Backend endpoints: GET /api/funds, POST /api/funds/add, POST /api/funds/withdraw
// WebSocket: FundsChannel — receives { type: "funds_changed" } signals to refetch
import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import cable from '../cable'
import toast from 'solid-toast'

const POLL_MS = 30000

export function useFunds() {
  const [funds, setFunds] = createSignal({
    cash: 0, equity: 0, mtm: 0, exposure: 0,
    margin_used: 0, available: 0, total_collateral: 0, day_pnl: 0
  })
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  let subscription = null
  let pollTimer = null

  async function fetchFunds() {
    setLoading(true)
    try {
      const res = await apiClient.get('/funds')
      setFunds(res.data)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function addFunds(amount) {
    try {
      const res = await apiClient.post('/funds/add', { amount })
      toast.success(`₹${amount} added successfully`)
      await fetchFunds()
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Failed to add funds: ${e.message}`)
      return { ok: false }
    }
  }

  async function withdrawFunds(amount) {
    try {
      const res = await apiClient.post('/funds/withdraw', { amount })
      toast.success(`₹${amount} withdrawal initiated`)
      await fetchFunds()
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Withdrawal failed: ${e.message}`)
      return { ok: false }
    }
  }

  onMount(() => {
    fetchFunds()
    pollTimer = setInterval(fetchFunds, POLL_MS)

    subscription = cable.subscriptions.create('FundsChannel', {
      connected() {
        console.log('✅ [WS:Funds] Connected')
      },
      received(data) {
        console.debug('⚡ [WS:Funds] Update:', data)
        if (data.type === 'funds_changed') fetchFunds()
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { funds, loading, error, fetchFunds, addFunds, withdrawFunds }
}
