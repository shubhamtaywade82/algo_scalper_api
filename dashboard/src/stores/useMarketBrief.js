import { createSignal, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'

const POLL_INTERVAL_MS = 3000
const POLL_TIMEOUT_MS = 180000

// A build is finished once the snapshot is ready and the AI stage has resolved
// (completed, unavailable, invalid, disabled or skipped) — or the build failed.
function isSettled(brief) {
  if (!brief) return false
  if (brief.status === 'failed') return true
  return brief.status === 'ready' && brief.ai?.status !== 'pending'
}

export function useMarketBrief() {
  const [brief, setBrief] = createSignal(null)
  const [inProgress, setInProgress] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [generating, setGenerating] = createSignal(false)
  const [error, setError] = createSignal(null)
  let pollTimer = null

  function stopPolling() {
    if (pollTimer) clearTimeout(pollTimer)
    pollTimer = null
  }
  onCleanup(stopPolling)

  async function fetchLatest() {
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.get(endpoints.reports.marketBrief)
      setBrief(res.data?.brief || null)
      setInProgress(res.data?.in_progress || null)
      if (res.data?.in_progress && !pollTimer) poll(res.data.in_progress.id, Date.now())
      return { ok: true }
    } catch (e) {
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function poll(id, startedAt) {
    setGenerating(true)
    pollTimer = setTimeout(async () => {
      try {
        const res = await apiClient.get(endpoints.reports.marketBrief, { params: { id } })
        const next = res.data?.brief
        // Show the deterministic report as soon as it exists; AI commentary fills in later.
        if (next?.status === 'ready') setBrief(next)
        if (isSettled(next)) {
          if (next.status === 'failed') setError(`Report build failed: ${next.error || 'unknown error'}`)
          finish()
          return
        }
      } catch (e) {
        setError(e.message)
        finish()
        return
      }
      if (Date.now() - startedAt > POLL_TIMEOUT_MS) {
        setError('Report generation is taking longer than expected — it will appear on the next refresh.')
        finish()
        return
      }
      poll(id, startedAt)
    }, POLL_INTERVAL_MS)
  }

  function finish() {
    stopPolling()
    setGenerating(false)
    setInProgress(null)
  }

  async function requestRefresh() {
    if (generating()) return { ok: false, error: 'already_generating' }
    setError(null)
    try {
      const res = await apiClient.post(endpoints.reports.marketBrief)
      const requested = res.data?.brief
      if (!requested) throw new Error('Empty response from report endpoint')
      if (isSettled(requested) && requested.status !== 'failed') {
        setBrief(requested)
        return { ok: true, reused: true }
      }
      setInProgress({ id: requested.id, status: requested.status })
      stopPolling()
      poll(requested.id, Date.now())
      return { ok: true }
    } catch (e) {
      setError(e.message)
      return { ok: false, error: e.message }
    }
  }

  return { brief, inProgress, loading, generating, error, fetchLatest, requestRefresh }
}
