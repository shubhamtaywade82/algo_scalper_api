import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'

export function useReports() {
  const [summary, setSummary] = createSignal(null)
  const [daily, setDaily] = createSignal([])
  const [trades, setTrades] = createSignal([])
  const [byStrategy, setByStrategy] = createSignal([])
  const [byInstrument, setByInstrument] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchAll(params = {}) {
    setLoading(true)
    setError(null)
    const q = { since: params.since || undefined, until: params.until || undefined }
    try {
      const [perfRes, pnlRes, tradesRes, stratRes, instrRes] = await Promise.all([
        apiClient.get(endpoints.reports.performance, { params: q }),
        apiClient.get(endpoints.reports.pnl, { params: q }),
        apiClient.get(endpoints.reports.trades, { params: { ...q, per_page: 10 } }),
        apiClient.get(endpoints.reports.pnlByStrategy, { params: q }),
        apiClient.get(endpoints.reports.pnlByInstrument, { params: q })
      ])
      setSummary({
        ...(perfRes.data?.summary || {}),
        ...(pnlRes.data?.summary || {})
      })
      setDaily(perfRes.data?.daily || [])
      setTrades(tradesRes.data?.trades || [])
      setByStrategy(stratRes.data?.breakdown || [])
      setByInstrument(instrRes.data?.breakdown || [])
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
    setByStrategy([])
    setByInstrument([])
    setError(null)
  }

  return { summary, daily, trades, byStrategy, byInstrument, loading, error, fetchAll, reset }
}
