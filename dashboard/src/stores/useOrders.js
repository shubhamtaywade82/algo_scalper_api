import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'

export function useOrders() {
  const [orders, setOrders] = createSignal([])
  const [loading, setLoading] = createSignal(false)

  async function fetchOrders() {
    setLoading(true)
    try {
      const res = await apiClient.get('/orders')
      setOrders(res.data?.orders || [])
    } catch {
      setOrders([])
    } finally {
      setLoading(false)
    }
  }

  return { orders, loading, fetchOrders }
}
