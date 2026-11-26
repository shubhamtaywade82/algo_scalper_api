import { describe, it, expect } from 'vitest'
import { shouldShowColumn } from './optionChainColumns'

describe('shouldShowColumn', () => {
  it('shows LTP and Chg % when in LTP mode', () => {
    expect(shouldShowColumn('ltp', 'LTP')).toBe(true)
    expect(shouldShowColumn('chg', 'LTP')).toBe(true)
    expect(shouldShowColumn('delta', 'LTP')).toBe(false)
  })

  it('shows OI metrics in OI mode but hides Greeks', () => {
    expect(shouldShowColumn('oi', 'OI')).toBe(true)
    expect(shouldShowColumn('choi', 'OI')).toBe(true)
    expect(shouldShowColumn('vol', 'OI')).toBe(true)
    expect(shouldShowColumn('vega', 'OI')).toBe(false)
  })

  it('shows all columns in Greeks mode', () => {
    expect(shouldShowColumn('delta', 'Greeks')).toBe(true)
    expect(shouldShowColumn('gamma', 'Greeks')).toBe(true)
    expect(shouldShowColumn('oi', 'Greeks')).toBe(true)
  })

  it('rejects unknown columns when viewMode is invalid', () => {
    expect(shouldShowColumn('unknown_column', 'INVALID_MODE')).toBe(false)
  })
})
