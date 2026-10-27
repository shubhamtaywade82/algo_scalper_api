import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createRoot } from 'solid-js'

vi.mock('../lib/api', () => ({
  apiClient: { get: vi.fn(), post: vi.fn() },
  endpoints: {}
}))
vi.mock('../lib/api/endpoints', () => ({
  endpoints: { reports: { marketBrief: '/reports/market_brief', marketBriefLive: '/reports/market_brief/live' } }
}))

import { apiClient } from '../lib/api'
import { useLiveMarketBrief, nextDelay, LIVE_POLL_MS } from './useLiveMarketBrief'

const flush = () => new Promise((r) => setTimeout(r, 0))

function mount(options) {
  let api
  let dispose
  createRoot((d) => { dispose = d; api = useLiveMarketBrief(options) })
  return { api, dispose }
}

describe('useLiveMarketBrief', () => {
  beforeEach(() => {
    apiClient.get.mockReset()
    apiClient.post.mockReset()
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false })
  })
  afterEach(() => vi.useRealTimers())

  it('polls the live endpoint and stores the payload', async () => {
    apiClient.get.mockResolvedValue({ data: { live: true, snapshot: { setup: { decision: 'NO_TRADE' } } } })
    const { api, dispose } = mount({ pollMs: 20 })
    api.start()
    await flush()
    expect(apiClient.get).toHaveBeenCalledWith('/reports/market_brief/live')
    expect(api.brief().snapshot.setup.decision).toBe('NO_TRADE')
    await new Promise((r) => setTimeout(r, 50))
    expect(apiClient.get.mock.calls.length).toBeGreaterThanOrEqual(2)
    dispose()
  })

  it('keeps the last good data and reports the error when a poll fails', async () => {
    apiClient.get
      .mockRejectedValue(new Error('Network Error'))
      .mockResolvedValueOnce({ data: { live: true, fetched_at: 'first' } })
    const { api, dispose } = mount({ pollMs: 10 })
    api.start()
    await flush()
    await new Promise((r) => setTimeout(r, 30))
    expect(api.brief().fetched_at).toBe('first')
    expect(api.error()).toBe('Network Error')
    expect(api.consecutiveErrors()).toBeGreaterThanOrEqual(1)
    dispose()
  })

  it('backs off exponentially on consecutive errors, capped at 30s', () => {
    expect(nextDelay(0)).toBe(LIVE_POLL_MS)
    expect(nextDelay(1)).toBe(LIVE_POLL_MS * 2)
    expect(nextDelay(2)).toBe(LIVE_POLL_MS * 4)
    expect(nextDelay(10)).toBe(30000)
  })

  it('does not poll while the tab is hidden', async () => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true })
    const { api, dispose } = mount({ pollMs: 10 })
    api.start()
    await new Promise((r) => setTimeout(r, 30))
    expect(apiClient.get).not.toHaveBeenCalled()
    dispose()
  })

  it('requests one AI refresh and refuses while a build is in progress', async () => {
    apiClient.get.mockResolvedValue({ data: { live: true, in_progress: { id: 3, status: 'building' } } })
    apiClient.post.mockResolvedValue({ data: { enqueued: true } })
    const { api, dispose } = mount({ pollMs: 1000 })
    expect((await api.requestAiRefresh()).ok).toBe(true)
    expect(apiClient.post).toHaveBeenCalledTimes(1)
    await flush()
    expect(await api.requestAiRefresh()).toEqual({ ok: false, error: 'already_generating' })
    expect(apiClient.post).toHaveBeenCalledTimes(1)
    dispose()
  })

  it('stops polling after cleanup', async () => {
    apiClient.get.mockResolvedValue({ data: { live: true } })
    const { api, dispose } = mount({ pollMs: 10 })
    api.start()
    await flush()
    dispose()
    const calls = apiClient.get.mock.calls.length
    await new Promise((r) => setTimeout(r, 40))
    expect(apiClient.get.mock.calls.length).toBe(calls)
  })
})
