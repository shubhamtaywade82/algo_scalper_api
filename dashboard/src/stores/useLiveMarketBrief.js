import { createSignal, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'

// Live facts are rebuilt server-side per poll (≤3s cache) and never call the LLM,
// so a 5s cadence matches the trading daemon's own dashboard broadcast interval.
export const LIVE_POLL_MS = 5000
const MAX_BACKOFF_MS = 30000
// The client marks the view interrupted when no successful poll landed recently.
export const LIVE_STALE_AFTER_MS = 15000

export function nextDelay(consecutiveErrors) {
  if (consecutiveErrors <= 0) return LIVE_POLL_MS
  return Math.min(LIVE_POLL_MS * 2 ** consecutiveErrors, MAX_BACKOFF_MS)
}

export function useLiveMarketBrief(options = {}) {
  const pollMs = options.pollMs ?? LIVE_POLL_MS
  const [brief, setBrief] = createSignal(null)
  const [lastSuccessAt, setLastSuccessAt] = createSignal(null)
  const [error, setError] = createSignal(null)
  const [consecutiveErrors, setConsecutiveErrors] = createSignal(0)
  const [requestingAi, setRequestingAi] = createSignal(false)
  const [now, setNow] = createSignal(Date.now())
  let timer = null
  let inFlight = false
  let stopped = false

  const clock = setInterval(() => setNow(Date.now()), 1000)

  function schedule(delay) {
    clearTimeout(timer)
    if (stopped) return
    timer = setTimeout(tick, delay)
  }

  async function tick() {
    // Pause while the tab is hidden; resume on visibilitychange.
    if (typeof document !== 'undefined' && document.hidden) return
    if (inFlight) return
    inFlight = true
    try {
      const res = await apiClient.get(endpoints.reports.marketBriefLive)
      setBrief(res.data)
      setLastSuccessAt(Date.now())
      setError(null)
      setConsecutiveErrors(0)
      schedule(pollMs)
    } catch (e) {
      setError(e.message)
      const errors = consecutiveErrors() + 1
      setConsecutiveErrors(errors)
      schedule(options.pollMs ? pollMs : nextDelay(errors))
    } finally {
      inFlight = false
    }
  }

  function onVisibility() {
    if (!document.hidden) {
      clearTimeout(timer)
      tick()
    }
  }

  function start() {
    stopped = false
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility)
    tick()
  }

  function stop() {
    stopped = true
    clearTimeout(timer)
    clearInterval(clock)
    if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility)
  }
  onCleanup(stop)

  // Bounded server-side: one report per 5-min slot, digest reuse, provider backoff.
  async function requestAiRefresh() {
    if (requestingAi() || brief()?.in_progress) return { ok: false, error: 'already_generating' }
    setRequestingAi(true)
    try {
      const res = await apiClient.post(endpoints.reports.marketBrief)
      clearTimeout(timer)
      tick()
      return { ok: true, enqueued: res.data?.enqueued === true }
    } catch (e) {
      setError(e.message)
      return { ok: false, error: e.message }
    } finally {
      setRequestingAi(false)
    }
  }

  const interrupted = () => {
    const last = lastSuccessAt()
    return last !== null && now() - last > LIVE_STALE_AFTER_MS
  }

  return {
    brief, lastSuccessAt, error, consecutiveErrors, requestingAi, interrupted, now,
    start, stop, refreshNow: () => { clearTimeout(timer); return tick() }, requestAiRefresh
  }
}
