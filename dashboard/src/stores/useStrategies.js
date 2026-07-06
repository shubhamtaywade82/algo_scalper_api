import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useStrategies() {
  const [strategies, setStrategies] = createSignal([])
  const [currentStrategy, setCurrentStrategy] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchAll() {
    setLoading(true)
    try {
      const res = await apiClient.get('/trading_strategies')
      setStrategies(res.data)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function fetchOne(id) {
    setLoading(true)
    try {
      const res = await apiClient.get(`/trading_strategies/${id}`)
      setCurrentStrategy(res.data)
      setError(null)
      return res.data
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function create(data) {
    setLoading(true)
    try {
      const res = await apiClient.post('/trading_strategies', { trading_strategy: data })
      setCurrentStrategy(res.data)
      setError(null)
      return res.data
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function update(id, data) {
    setLoading(true)
    try {
      const res = await apiClient.patch(`/trading_strategies/${id}`, { trading_strategy: data })
      setCurrentStrategy(res.data)
      setError(null)
      return res.data
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function archive(id) {
    try {
      await apiClient.delete(`/trading_strategies/${id}`)
      setStrategies(prev => prev.filter(s => s.id !== id))
    } catch (e) {
      setError(e.message)
    }
  }

  async function validateStrategy(id) {
    try {
      const res = await apiClient.post(`/trading_strategies/${id}/validate`)
      setCurrentStrategy(res.data)
      return res.data
    } catch (e) {
      setError(e.message)
    }
  }

  return { strategies, currentStrategy, setCurrentStrategy, loading, error, fetchAll, fetchOne, create, update, archive, validateStrategy }
}
