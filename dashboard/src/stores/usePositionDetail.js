import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'

export function usePositionDetail() {
  const [detail, setDetail] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchDetail(id) {
    if (id == null) return
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.get(endpoints.positionDetail(id))
      setDetail(res.data)
      return { ok: true }
    } catch (e) {
      setError(e.message)
      setDetail(null)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function clear() {
    setDetail(null)
    setError(null)
  }

  return { detail, loading, error, fetchDetail, clear }
}
