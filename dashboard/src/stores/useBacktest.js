import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

const POLL_INTERVAL_MS = 2000

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

export function useBacktest() {
  const [result, setResult] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function runBacktest(params = {}) {
    setLoading(true)
    setError(null)
    try {
      const { data } = await apiClient.post('/backtests', {
        symbol: params.symbol || 'NIFTY',
        interval: params.interval || '5',
        days_back: params.days_back || 30
      })

      // Backend runs the backtest as a background job (days_back: 365 can take a while);
      // poll the same run until it's done instead of holding the HTTP request open.
      let state = data
      while (state.status === 'queued' || state.status === 'running') {
        await sleep(POLL_INTERVAL_MS)
        state = (await apiClient.get(`/backtests/${data.backtest_run_id}`)).data
      }

      if (state.status === 'failed') {
        setError(state.error || 'Backtest failed')
        return { ok: false, error: state.error }
      }

      setResult(state)
      return { ok: true, data: state }
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
