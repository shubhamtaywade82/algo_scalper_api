// Backend endpoints: GET /api/alerts, POST /api/alerts, PATCH /api/alerts/:id, DELETE /api/alerts/:id
// WebSocket: AlertsChannel — receives { alert: { ... } } for real-time push
import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import cable from '../cable'
import toast from 'solid-toast'

const POLL_MS = 10000

export function useAlerts() {
  const [alerts, setAlerts] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  let subscription = null
  let pollTimer = null

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
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Failed to create alert: ${e.message}`)
      return { ok: false }
    }
  }

  async function updateAlert(id, data) {
    try {
      const res = await apiClient.patch(`/alerts/${id}`, data)
      setAlerts(prev => prev.map(a => a.id === id ? { ...a, ...res.data } : a))
      return { ok: true, data: res.data }
    } catch (e) {
      toast.error(`Failed to update alert: ${e.message}`)
      return { ok: false }
    }
  }

  async function deleteAlert(id) {
    try {
      await apiClient.delete(`/alerts/${id}`)
      setAlerts(prev => prev.filter(a => a.id !== id))
      toast.success('Alert deleted')
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
    pollTimer = setInterval(fetchAlerts, POLL_MS)

    subscription = cable.subscriptions.create('AlertsChannel', {
      connected() {
        console.log('✅ [WS:Alerts] Connected')
      },
      received(data) {
        console.debug('⚡ [WS:Alerts] Update:', data)
        if (data.alert) {
          setAlerts(prev => [data.alert, ...prev].slice(0, 100))
        }
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { alerts, loading, error, fetchAlerts, createAlert, updateAlert, deleteAlert, markRead }
}
