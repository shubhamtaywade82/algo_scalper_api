// Backend endpoint: GET /api/logs?level=&source=&page=&per_page=
// Response shape: { logs: [{id, timestamp, level, source, message}], meta: {total, page, per_page, pages} }
// TODO: Wire to ActionCable LogsChannel when available

import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'

const POLL_MS = 5000

export function useLogs() {
  const [logs, setLogs] = createSignal([])
  const [meta, setMeta] = createSignal({ total: 0, page: 1, per_page: 50, pages: 0 })
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchLogs(opts = {}) {
    const { level, source, page = 1, per_page = 50 } = opts
    setLoading(true)
    try {
      const params = { page, per_page }
      if (level) params.level = level
      if (source) params.source = source
      const res = await apiClient.get('/logs', { params })
      const data = res.data
      setLogs(data.logs || [])
      setMeta(data.meta || { total: 0, page: 1, per_page: 50, pages: 0 })
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  onMount(() => {
    fetchLogs()
    const timer = setInterval(() => fetchLogs({ page: meta().page, per_page: meta().per_page }), POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  return { logs, meta, loading, error, fetchLogs }
}
