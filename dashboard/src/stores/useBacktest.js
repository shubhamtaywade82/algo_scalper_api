import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useBacktest() {
  const [result, setResult] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function runBacktest(params = {}) {
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.post('/backtests', {
        symbol: params.symbol || 'NIFTY',
        interval: params.interval || '5',
        days_back: params.days_back || 30
      })
      setResult(res.data)
      return { ok: true, data: res.data }
    } catch (e) {
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function reset() {
    setResult(null)
    setError(null)
  }

  return { result, loading, error, runBacktest, reset }
}
