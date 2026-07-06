import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useReports() {
  const [summary, setSummary] = createSignal(null)
  const [daily, setDaily] = createSignal([])
  const [trades, setTrades] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchAll() {
    setLoading(true)
    setError(null)
    try {
      const [perfRes, pnlRes, tradesRes] = await Promise.all([
        apiClient.get('/reports/performance'),
        apiClient.get('/reports/pnl'),
        apiClient.get('/reports/trades', { params: { per_page: 10 } })
      ])
      setSummary({
        ...(perfRes.data?.summary || {}),
        ...(pnlRes.data?.summary || {})
      })
      setDaily(perfRes.data?.daily || [])
      setTrades(tradesRes.data?.trades || [])
      return { ok: true }
    } catch (e) {
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function reset() {
    setSummary(null)
    setDaily([])
    setTrades([])
    setError(null)
  }

  return { summary, daily, trades, loading, error, fetchAll, reset }
}
