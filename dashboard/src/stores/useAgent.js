// Backend endpoint: GET /api/agent/status — options-trading-agent heartbeat (agent-snapshot/1) + recent trade intents
import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'

const POLL_MS = 2000

export function useAgent() {
  const [status, setStatus] = createSignal(null)
  const [error, setError] = createSignal(null)
  let timer = null
  let disposed = false

  // Single-flight: the next poll starts only after the previous one settles.
  async function poll() {
    if (!document.hidden) {
      try {
        const res = await apiClient.get('/agent/status')
        setStatus(res.data)
        setError(null)
      } catch (e) {
        setError(e.message)
      }
    }
    if (!disposed) timer = setTimeout(poll, POLL_MS)
  }

  onMount(poll)
  onCleanup(() => { disposed = true; clearTimeout(timer) })

  return { status, error }
}
