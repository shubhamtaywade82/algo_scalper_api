import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useEquityCurve() {
  const [data, setData] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchCurve(dateFrom, dateTo) {
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (dateFrom) params.set('date_from', dateFrom)
      if (dateTo) params.set('date_to', dateTo)
      const res = await apiClient.get(`/equity_curve?${params.toString()}`)
      setData(res.data)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  return { data, loading, error, fetchCurve }
}
