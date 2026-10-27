import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@solidjs/testing-library'
import fixture from '../../scripts/fixtures/market_brief_degraded.json'

vi.mock('../lib/api', () => ({ apiClient: { get: vi.fn(), post: vi.fn() }, endpoints: {} }))
const cableMock = vi.hoisted(() => ({ create: vi.fn() }))
vi.mock('../cable', () => ({ default: { subscriptions: { create: (...args) => cableMock.create(...args) } } }))
vi.mock('../lib/api/endpoints', () => ({
  endpoints: { reports: { marketBrief: '/reports/market_brief', marketBriefLive: '/reports/market_brief/live' } }
}))

import { apiClient } from '../lib/api'
import MarketBrief from './MarketBrief'

describe('MarketBrief (Market Mood) view', () => {
  beforeEach(() => {
    cableMock.create.mockReset()
    cableMock.create.mockReturnValue({ unsubscribe: vi.fn() })
    apiClient.get.mockReset()
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false })
  })

  it('shows a loading state, then the live sheet plus a hidden print copy', async () => {
    apiClient.get.mockResolvedValue({ data: { ...fixture, live: true, fetched_at: new Date().toISOString() } })
    render(() => <MarketBrief />)
    expect(screen.getByText('Loading live market brief…')).toBeTruthy()
    await waitFor(() => expect(screen.getAllByTestId('market-brief-sheet').length).toBe(2))
    expect(document.querySelector('.mb-sheet--screen')).toBeTruthy()
    expect(document.querySelector('.mb-print-portal .mb-sheet')).toBeTruthy()
    expect(screen.getByTestId('poll-status').textContent).toMatch(/Polling · updated/) // no socket in this test
  })

  it('shows an explicit error when the first load fails', async () => {
    apiClient.get.mockRejectedValue(new Error('unauthorized'))
    render(() => <MarketBrief />)
    await waitFor(() => expect(screen.getByTestId('live-error').textContent).toMatch(/Could not load the Market Brief: unauthorized/))
    expect(screen.queryByTestId('market-brief-sheet')).toBeNull()
  })

  it('disables AI refresh while a build is in progress', async () => {
    apiClient.get.mockResolvedValue({ data: { ...fixture, live: true, in_progress: { id: 1, status: 'building' } } })
    render(() => <MarketBrief />)
    await waitFor(() => expect(screen.getByText('AI analysis running…')).toBeTruthy())
    expect(screen.getByText('Refresh AI analysis').disabled).toBe(true)
  })
})
