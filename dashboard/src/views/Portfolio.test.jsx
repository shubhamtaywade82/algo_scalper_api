import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@solidjs/testing-library'
import { createSignal } from 'solid-js'

vi.mock('@solidjs/router', () => ({
  useSearchParams: () => [{}, vi.fn()]
}))

vi.mock('./Positions', () => ({ default: () => <div data-testid="positions-content">Positions Content</div> }))
vi.mock('./Ledger', () => ({ default: () => <div data-testid="ledger-content">Ledger Content</div> }))
vi.mock('./Holdings', () => ({ default: () => <div data-testid="holdings-content">Holdings Content</div> }))
vi.mock('./Funds', () => ({ default: () => <div data-testid="funds-content">Funds Content</div> }))

import Portfolio from './Portfolio'

describe('Portfolio tab synchronization', () => {
  it('updates active tab when defaultTab prop changes', () => {
    const [tab, setTab] = createSignal('positions')
    render(() => <Portfolio defaultTab={tab()} />)

    expect(screen.getByTestId('positions-content')).toBeTruthy()

    setTab('funds')
    expect(screen.getByTestId('funds-content')).toBeTruthy()
  })
})
