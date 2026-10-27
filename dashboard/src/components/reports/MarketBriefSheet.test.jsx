import { describe, it, expect } from 'vitest'
import { render, screen } from '@solidjs/testing-library'
import MarketBriefSheet from './MarketBriefSheet'
// Real payloads captured from the Rails pipeline (controlled test data).
import maxText from '../../../scripts/fixtures/market_brief_max_text.json'
import degraded from '../../../scripts/fixtures/market_brief_degraded.json'

const clone = (o) => JSON.parse(JSON.stringify(o))

function noTradeBrief() {
  const b = clone(maxText)
  b.snapshot.setup = {
    status: 'ok', decision: 'NO_TRADE', candidate: null, blockers: [], approved_count: 0, evaluated_count: 3,
    message: 'NO TRADE — No setup satisfies the current qualification and risk requirements.',
    rejection_reasons: [{ reason: 'spread_too_wide', count: 2 }, { reason: 'adx_below_threshold', count: 1 }]
  }
  b.ai = { status: 'unavailable', error: 'timeout_after_90s', analysis: null }
  return b
}

describe('MarketBriefSheet', () => {
  it('renders a qualified setup with levels taken from the snapshot', () => {
    render(() => <MarketBriefSheet brief={maxText} variant="screen" />)
    expect(screen.getByText('QUALIFIED')).toBeTruthy()
    expect(screen.getByText('NIFTY-Oct2026-24500-CE')).toBeTruthy()
    expect(screen.getByText('104.20')).toBeTruthy() // stop-loss
    expect(screen.getByText('124.32')).toBeTruthy() // target
    expect(screen.getByText('0.42 : 1')).toBeTruthy()
  })

  it('renders NO TRADE with the actual guard rejection reasons', () => {
    render(() => <MarketBriefSheet brief={noTradeBrief()} variant="screen" />)
    expect(screen.getByText(/NO TRADE — No setup satisfies/)).toBeTruthy()
    expect(screen.getByText('spread too wide ×2')).toBeTruthy()
    expect(screen.getByText('adx below threshold ×1')).toBeTruthy()
  })

  it('keeps deterministic risk and health visible when AI is unavailable', () => {
    render(() => <MarketBriefSheet brief={noTradeBrief()} variant="screen" />)
    expect(screen.getByText('AI ANALYSIS UNAVAILABLE')).toBeTruthy()
    expect(screen.getByText(/timeout after 90s/)).toBeTruthy()
    expect(screen.getByText('Account & risk')).toBeTruthy()
    expect(screen.getByText('System health')).toBeTruthy()
    expect(screen.getAllByText('₹2,500.00', { selector: 'strong' })).toHaveLength(2) // unrealized + total
  })

  it('labels stale and missing data instead of showing zeros', () => {
    render(() => <MarketBriefSheet brief={degraded} variant="screen" />)
    expect(screen.getAllByText('STALE').length).toBeGreaterThan(0)
    expect(screen.getAllByText('NO DATA').length).toBeGreaterThan(0) // SENSEX quote + VIX
    expect(screen.getByText('BLOCKED')).toBeTruthy()
    expect(screen.getByText('circuit breaker tripped')).toBeTruthy()
    expect(screen.getByText('DOWN')).toBeTruthy() // market feed heartbeat
  })

  it('surfaces AI/deterministic disagreement without changing the decision', () => {
    render(() => <MarketBriefSheet brief={maxText} variant="screen" />)
    expect(screen.getByText(/SENSEX: AI reads BEARISH.*deterministic decision stands/)).toBeTruthy()
    expect(screen.getByText('QUALIFIED')).toBeTruthy()
  })

  it('flags live commentary that predates a decision change', () => {
    const b = clone(maxText)
    b.live = true
    b.fetched_at = new Date().toISOString()
    b.snapshot.setup.decision = 'BLOCKED'
    b.ai = { ...b.ai, report_id: 7, based_on_snapshot_at: b.snapshot.generated_at, age_seconds: 1500, stale: true,
             decision_changed: true, decision_at_analysis: 'QUALIFIED',
             latest_attempt: { report_id: 9, status: 'invalid', error: 'unparseable_json' } }
    render(() => <MarketBriefSheet brief={b} variant="screen" />)
    expect(screen.getByTestId('ai-decision-changed').textContent).toMatch(/was QUALIFIED, now BLOCKED/)
    expect(screen.getByText(/Latest AI refresh: AI ANALYSIS UNAVAILABLE — output failed validation/)).toBeTruthy()
    expect(screen.getByText(/At analysis time, why it qualified:/)).toBeTruthy()
    expect(screen.getByTestId('live-badge').textContent).toMatch(/^LIVE/)
  })

  it('shows an interrupted live badge when polling has stalled', () => {
    const b = { ...clone(maxText), live: true, fetched_at: new Date().toISOString() }
    render(() => <MarketBriefSheet brief={b} variant="screen" interrupted />)
    expect(screen.getByTestId('live-badge').textContent).toMatch(/LIVE UPDATES INTERRUPTED/)
  })

  it('renders model text as text, never as HTML', () => {
    const b = clone(maxText)
    b.ai.analysis.executive_summary = '<img src=x onerror=alert(1)>Trend intact'
    const { container } = render(() => <MarketBriefSheet brief={b} variant="screen" />)
    expect(container.querySelector('img')).toBeNull()
    expect(screen.getByText(/<img src=x onerror=alert\(1\)>Trend intact/)).toBeTruthy()
  })

  describe('live events', () => {
    const now = new Date().toISOString()
    const withEvents = () => {
      const b = clone(maxText)
      b.live = true
      b.fetched_at = now
      b.events = [
        { kind: 'quote_state_changed', at: now, ai_trigger: false, message: 'NIFTY quote live → stale' },
        { kind: 'level_crossed', at: now, ai_trigger: true, message: 'NIFTY crossed LTF swing high 24,520.00 upward (LTP 24,530.00)' }
      ]
      return b
    }

    it('lists the day\'s events newest first on the screen view, marking the AI-triggering ones', () => {
      render(() => <MarketBriefSheet brief={withEvents()} variant="screen" />)
      const items = screen.getByTestId('event-list').querySelectorAll('li')
      expect(items).toHaveLength(2)
      expect(items[0].textContent).toMatch(/crossed LTF swing high/)
      expect(items[0].textContent).toMatch(/AI run/)
      expect(items[1].textContent).not.toMatch(/AI run/)
    })

    it('keeps the event timeline out of the printed copy', () => {
      render(() => <MarketBriefSheet brief={withEvents()} />)
      expect(screen.queryByTestId('event-list')).toBeNull()
    })

    it('shows the in-flight run and why it was started', () => {
      const b = withEvents()
      b.in_progress = { id: 9, status: 'building', trigger: 'event', reasons: ['NIFTY crossed LTF swing high'] }
      render(() => <MarketBriefSheet brief={b} variant="screen" />)
      expect(screen.getByTestId('ai-in-progress').textContent).toMatch(/AI analysis running · triggered by NIFTY crossed LTF swing high/)
    })

    it('states which change the displayed commentary was written for', () => {
      const b = withEvents()
      b.ai = { ...b.ai, trigger: 'event', trigger_reasons: ['NIFTY crossed LTF swing high'], report_id: 4 }
      render(() => <MarketBriefSheet brief={b} variant="screen" />)
      expect(screen.getByTestId('ai-trigger').textContent).toMatch(/Triggered by: NIFTY crossed LTF swing high/)
    })

    it('shows an empty timeline message before the first change of the session', () => {
      const b = clone(maxText)
      b.events = []
      render(() => <MarketBriefSheet brief={b} variant="screen" />)
      expect(screen.getByText('No state changes yet this session.')).toBeTruthy()
    })
  })
})
