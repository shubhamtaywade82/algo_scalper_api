// Backend endpoints: GET /api/alerts, POST /api/alerts, PATCH /api/alerts/:id, DELETE /api/alerts/:id
// Response shape: [{ id, type, severity, message, read, created_at }]
// TODO: Wire to ActionCable AlertsChannel when available

import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import toast from 'solid-toast'

const POLL_MS = 10000

export function useAlerts() {
  const [alerts, setAlerts] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchAlerts() {
    setLoading(true)
    try {
      const res = await apiClient.get('/alerts')
      setAlerts(res.data || [])
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function createAlert(data) {
    try {
      const res = await apiClient.post('/alerts', data)
      toast.success('Alert created')
      await fetchAlerts()
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Failed to create alert: ${e.message}`)
      return { ok: false }
    }
  }

  async function updateAlert(id, data) {
    try {
      const res = await apiClient.patch(`/alerts/${id}`, data)
      await fetchAlerts()
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Failed to update alert: ${e.message}`)
      return { ok: false }
    }
  }

  async function deleteAlert(id) {
    try {
      await apiClient.delete(`/alerts/${id}`)
      toast.success('Alert deleted')
      await fetchAlerts()
      return { ok: true }
    } catch (e) {
      toast.error(`Failed to delete alert: ${e.message}`)
      return { ok: false }
    }
  }

  async function markRead(id) {
    return updateAlert(id, { read: true })
  }

  onMount(() => {
    fetchAlerts()
    const timer = setInterval(fetchAlerts, POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  return { alerts, loading, error, fetchAlerts, createAlert, updateAlert, deleteAlert, markRead }
}
