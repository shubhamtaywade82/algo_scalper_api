import { describe, it, expect, vi, beforeEach } from 'vitest'
import { createSignal, createRoot } from 'solid-js'

vi.mock('../lib/api', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue({ data: { bid: [], ask: [], totalBidQty: 10, totalAskQty: 10 } })
  }
}))

import { apiClient } from '../lib/api'
import { useDepth } from './useDepth'

describe('useDepth', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('reactively updates request URL when symbol getter changes', async () => {
    await createRoot(async (dispose) => {
      const [symbol, setSymbol] = createSignal('NIFTY')
      const { fetchDepth } = useDepth(symbol)

      await fetchDepth()
      expect(apiClient.get).toHaveBeenCalledWith('/depth?symbol=NIFTY')

      setSymbol('BANKNIFTY')
      await fetchDepth()
      expect(apiClient.get).toHaveBeenCalledWith('/depth?symbol=BANKNIFTY')

      dispose()
    })
  })
})
