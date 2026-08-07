import { createSignal } from 'solid-js'
import { apiClient, endpoints } from '../lib/api'

export function useStrategies() {
  const [strategies, setStrategies] = createSignal([])
  const [currentStrategy, setCurrentStrategy] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchAll() {
    setLoading(true)
    try {
      const res = await apiClient.get(endpoints.strategies?.list || '/strategies')
      const list = Array.isArray(res.data) ? res.data : (res.data?.strategies || [])
      setStrategies(list)
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
      const res = await apiClient.get(endpoints.strategies?.one?.(id) || `/strategies/${id}`)
      const strat = res.data?.strategy || res.data
      setCurrentStrategy(strat)
      setError(null)
      return strat
    } catch (e) {


      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function create(data) {
    setLoading(true)
    try {
      const res = await apiClient.post(endpoints.tradingStrategies.list, { trading_strategy: data })
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
      const res = await apiClient.patch(endpoints.tradingStrategies.one(id), { trading_strategy: data })
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
      await apiClient.delete(endpoints.tradingStrategies.one(id))
      setStrategies(prev => prev.filter(s => s.id !== id))
    } catch (e) {
      setError(e.message)
    }
  }

  async function validateStrategy(id) {
    try {
      const res = await apiClient.post(endpoints.tradingStrategies.validate(id))
      setCurrentStrategy(prev => ({ ...prev, ...res.data.strategy }))
      return res.data
    } catch (e) {
      setError(e.message)
      return null
    }
  }

  async function deployStrategy(id) {
    try {
      const res = await apiClient.post(endpoints.tradingStrategies.deploy(id))
      setCurrentStrategy(prev => ({ ...prev, ...res.data.strategy }))
      return res.data
    } catch (e) {
      const payload = e.response?.data
      setError(payload?.errors?.join(', ') || e.message)
      return payload ? { success: false, errors: payload.errors } : null
    }
  }

  return {
    strategies, currentStrategy, setCurrentStrategy, loading, error,
    fetchAll, fetchOne, create, update, archive, validateStrategy, deployStrategy
  }
}
