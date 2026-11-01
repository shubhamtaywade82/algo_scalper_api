import { createSignal, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'
import cable from '../cable'

// Facts are polled: the endpoint rebuilds them per request (≤3s cache) and never calls the LLM.
// Events and finished analyses are pushed over MarketBriefChannel as they happen, so the
// page updates at once instead of waiting for the next poll.
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
  const [streaming, setStreaming] = createSignal(false)
  const [now, setNow] = createSignal(Date.now())
  let timer = null
  let inFlight = false
  let stopped = false
  let subscription = null
  // Server time of the newest payload received over the socket. A poll answered
  // earlier than that must not overwrite it, or pushed commentary would flicker back.
  let lastPushedAt = null

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
      const polledAt = res.data?.fetched_at
      if (!(lastPushedAt && polledAt && polledAt < lastPushedAt)) setBrief(res.data)
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

  // Event and report frames carry the same payload as the endpoint.
  function applyFrame(frame) {
    if (!frame?.live) return
    lastPushedAt = frame.live.fetched_at ?? lastPushedAt
    setBrief(frame.live)
    setLastSuccessAt(Date.now())
    setError(null)
  }

  function subscribe() {
    if (subscription || typeof cable?.subscriptions?.create !== 'function') return
    subscription = cable.subscriptions.create('MarketBriefChannel', {
      connected() {
        setStreaming(true)
      },
      disconnected() {
        setStreaming(false)
      },
      received(frame) {
        applyFrame(frame)
      }
    })
  }

  function unsubscribe() {
    subscription?.unsubscribe()
    subscription = null
    setStreaming(false)
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
    subscribe()
    tick()
  }

  function stop() {
    stopped = true
    clearTimeout(timer)
    clearInterval(clock)
    unsubscribe()
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
    brief, lastSuccessAt, error, consecutiveErrors, requestingAi, interrupted, now, streaming,
    start, stop, refreshNow: () => { clearTimeout(timer); return tick() }, requestAiRefresh
  }
}
