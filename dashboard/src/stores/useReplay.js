import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useReplay() {
  const [result, setResult] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function loadReplay(params = {}) {
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.post('/replays', {
        symbol: params.symbol || 'NIFTY',
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

  return { result, loading, error, loadReplay, reset }
}
