import { For, Show } from 'solid-js'
import './marketBrief.css'

// Pure renderer for one persisted Market Brief (GET /api/reports/market_brief).
// Every value shown comes from brief.snapshot (deterministic) or brief.ai.analysis
// (validated interpretation). Nothing is computed here beyond formatting, so the
// dashboard view and the printed PDF always show the same facts.

const IST = 'Asia/Kolkata'
const INDEX_ORDER = ['NIFTY', 'BANKNIFTY', 'SENSEX']

const TONE = {
  live: 'ok', fresh: 'ok', ok: 'ok', open: 'ok', completed: 'ok', AGREE: 'ok', QUALIFIED: 'ok',
  ALIGNED_BULLISH: 'ok', ALIGNED_BEARISH: 'ok', not_required: 'muted', ALLOWED: 'ok',
  stale: 'warn', partial: 'warn', last_session: 'muted', pre_market: 'warn', post_close: 'muted',
  market_closed: 'muted', closed: 'muted', holiday: 'muted', PARTIAL: 'warn', MIXED: 'warn', NO_TRADE: 'warn',
  discrepancies: 'warn', skipped_market_closed: 'muted', disabled: 'muted', pending: 'muted', not_observed: 'warn',
  unavailable: 'bad', invalid: 'bad', error: 'bad', down: 'bad', degraded: 'bad', failed: 'bad', halted: 'bad',
  CONFLICT: 'bad', BLOCKED: 'bad', UNAVAILABLE: 'muted'
}

const STATUS_LABEL = {
  live: 'LIVE', fresh: 'FRESH', stale: 'STALE', last_session: 'LAST SESSION', unavailable: 'NO DATA',
  invalid: 'INVALID', error: 'ERROR', ok: 'OK', down: 'DOWN', not_required: 'N/A', not_observed: 'NOT OBSERVED',
  discrepancies: 'DISCREPANCIES', halted: 'HALTED', failed: 'FAILED', partial: 'PARTIAL', degraded: 'DEGRADED',
  market_closed: 'MARKET CLOSED', pre_market: 'PRE-MARKET', post_close: 'POST-CLOSE', open: 'OPEN',
  closed: 'CLOSED', holiday: 'HOLIDAY', NO_TRADE: 'NO TRADE', skipped_market_closed: 'SKIPPED (MARKET CLOSED)'
}

const AI_STATUS_TEXT = {
  completed: 'AI analysis validated',
  pending: 'AI analysis in progress…',
  unavailable: 'AI ANALYSIS UNAVAILABLE',
  invalid: 'AI ANALYSIS UNAVAILABLE — output failed validation',
  disabled: 'AI ANALYSIS UNAVAILABLE — AI disabled',
  skipped_market_closed: 'AI ANALYSIS UNAVAILABLE — paused while market is closed'
}

export function fmtNum(value, digits = 2) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return '—'
  return Number(value).toLocaleString('en-IN', { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

function fmtSigned(value, digits = 2, suffix = '') {
  if (value === null || value === undefined) return '—'
  const n = Number(value)
  return `${n > 0 ? '+' : ''}${fmtNum(n, digits)}${suffix}`
}

function fmtTime(iso) {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleTimeString('en-IN', { timeZone: IST, hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

function fmtDateTime(iso) {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString('en-IN', { timeZone: IST, hour12: false, day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function fmtAge(seconds) {
  if (seconds === null || seconds === undefined) return ''
  if (seconds < 90) return `${seconds}s ago`
  if (seconds < 5400) return `${Math.round(seconds / 60)}m ago`
  return `${Math.round(seconds / 3600)}h ago`
}

function humanize(value) {
  if (value === null || value === undefined || value === '') return '—'
  return String(value).replace(/_/g, ' ')
}

function Pill(props) {
  const tone = () => props.tone || TONE[props.status] || 'muted'
  return <span class={`mb-pill mb-tone-${tone()}`}>{props.label || STATUS_LABEL[props.status] || humanize(props.status)}</span>
}

function Section(props) {
  return (
    <section class={`mb-section ${props.class || ''}`}>
      <header class="mb-section-head">
        <h3>{props.title}</h3>
        <Show when={props.badge}>{props.badge}</Show>
      </header>
      <div class="mb-section-body">{props.children}</div>
    </section>
  )
}

function KV(props) {
  return (
    <div class={`mb-kv ${props.wrapClass || ''}`}>
      <span>{props.label}</span>
      <strong class={props.class || ''}>{props.children}</strong>
    </div>
  )
}

function IndexCard(props) {
  const idx = () => props.index || {}
  const quote = () => idx().quote || {}
  const regime = () => idx().regime || {}
  const bias = () => idx().bias || {}
  const change = () => quote().change_pct
  return (
    <div class="mb-index-card">
      <div class="mb-index-top">
        <span class="mb-index-name">{idx().index_key}</span>
        <Pill status={quote().status || 'unavailable'} />
      </div>
      <div class="mb-index-price">
        <span class="mb-ltp">{fmtNum(quote().ltp)}</span>
        <span class={`mb-change ${change() > 0 ? 'mb-up' : change() < 0 ? 'mb-down' : ''}`}>{fmtSigned(change(), 2, '%')}</span>
      </div>
      <div class="mb-index-meta">
        Prev close {fmtNum(quote().prev_close)} · tick {fmtTime(quote().observed_at)}
      </div>
      <div class="mb-index-grid">
        <KV label="Regime (5m)">{humanize(regime().label)} <Pill status={regime().status || 'unavailable'} /></KV>
        <KV label="ADX">{fmtNum(regime().adx, 1)}</KV>
        <KV label="Supertrend">{idx().supertrend?.status === 'unavailable' ? 'Unavailable' : humanize(idx().supertrend?.direction)}</KV>
        <KV label="MTF (SMC)"><Pill status={bias().mtf_alignment || 'UNAVAILABLE'} label={humanize(bias().mtf_alignment)} /></KV>
        <KV label="Tech vs SMC"><Pill status={bias().agreement || 'UNAVAILABLE'} label={humanize(bias().agreement)} /></KV>
        <KV label="Expiry">{idx().expiry?.nearest_expiry ? `${idx().expiry.nearest_expiry} (${idx().expiry.days_to_expiry}d)` : '—'}</KV>
      </div>
    </div>
  )
}

function ConfluenceTable(props) {
  const frame = (idx, tf) => idx?.smc?.timeframes?.[tf] || {}
  const ARROW = { BULLISH: '▲', BEARISH: '▼', NEUTRAL: '■' }
  const tfTrend = (idx) => ['htf', 'mtf', 'ltf'].map(tf => ARROW[frame(idx, tf).trend] || '—').join(' ')
  const bos = (idx) => {
    const b = frame(idx, 'ltf').last_bos
    if (!b) return '—'
    return [b.type, b.price !== undefined ? fmtNum(b.price) : null].filter(Boolean).join(' @ ')
  }
  return (
    <table class="mb-table">
      <colgroup>
        <col style="width: 12%" /><col style="width: 11%" /><col style="width: 13%" /><col style="width: 11%" />
        <col style="width: 17%" /><col style="width: 9%" /><col style="width: 7%" /><col style="width: 9%" /><col style="width: 11%" />
      </colgroup>
      <thead>
        <tr>
          <th>Index</th><th>Technical</th><th>SMC decision</th><th title="▲ bullish ▼ bearish ■ range">HTF MTF LTF</th><th>LTF last BOS</th>
          <th>Sweep</th><th>FVG / OB</th><th>Zone</th><th>Agreement</th>
        </tr>
      </thead>
      <tbody>
        <For each={props.indices}>
          {(idx) => (
            <tr>
              <td class="mb-strong">{idx.index_key}</td>
              <td>{humanize(idx.bias?.technical)}</td>
              <td>{idx.smc?.status === 'unavailable' ? 'NO DATA' : humanize(idx.smc?.decision)} <Show when={idx.smc?.status === 'stale'}><Pill status="stale" /></Show></td>
              <td>{tfTrend(idx)}</td>
              <td>{bos(idx)}</td>
              <td>{frame(idx, 'ltf').liquidity_sweep === true ? humanize(frame(idx, 'ltf').sweep_direction || 'yes') : frame(idx, 'ltf').liquidity_sweep === false ? 'no' : '—'}</td>
              <td>{frame(idx, 'ltf').active_fvg_count ?? '—'} / {frame(idx, 'ltf').active_order_block_count ?? '—'}</td>
              <td>{humanize(frame(idx, 'ltf').zone)}</td>
              <td><Pill status={idx.bias?.agreement || 'UNAVAILABLE'} label={humanize(idx.bias?.agreement)} /></td>
            </tr>
          )}
        </For>
      </tbody>
    </table>
  )
}

function SetupPanel(props) {
  const setup = () => props.setup || {}
  const cand = () => setup().candidate
  const trade = () => cand()?.trade
  return (
    <div class="mb-setup">
      <div class="mb-setup-decision">
        <Pill status={setup().decision || 'UNAVAILABLE'} label={setup().decision ? humanize(setup().decision) : 'NO DATA'} />
        <span class="mb-muted">policy: latest guard-approved signal today ({setup().approved_count ?? 0} approved / {setup().evaluated_count ?? 0} evaluated)</span>
      </div>
      <Show when={setup().message}>
        <p class="mb-no-trade">{setup().message}</p>
      </Show>
      <Show when={(setup().blockers || []).length > 0}>
        <div class="mb-chips"><span class="mb-muted">Blocked by:</span>
          <For each={setup().blockers}>{(b) => <span class="mb-chip mb-tone-bad">{humanize(b)}</span>}</For>
        </div>
      </Show>
      <Show when={cand()}>
        <div class="mb-candidate">
          <div class="mb-strong">
            {setup().decision === 'QUALIFIED' ? 'Qualified' : 'Last approved (not actionable now)'}: {cand().index_key} {cand().option_type} · {cand().strategy || 'strategy'} · {fmtTime(cand().emitted_at)}
          </div>
          <Show when={trade()} fallback={<div class="mb-muted">Trade parameters not linked to this signal — none displayed.</div>}>
            <div class="mb-setup-grid">
              <KV label="Contract" wrapClass="mb-span-2">{trade().symbol || '—'}</KV>
              <KV label="Entry">{fmtNum(trade().entry_price)}</KV>
              <KV label="Strike / Expiry" wrapClass="mb-span-2">{fmtNum(trade().strike, 0)} / {trade().expiry || '—'}</KV>
              <KV label="Stop-loss">{fmtNum(trade().stop_loss)}</KV>
              <KV label="Target">{fmtNum(trade().target)}</KV>
              <KV label="Reward : risk">{trade().reward_to_risk != null ? `${fmtNum(trade().reward_to_risk)} : 1` : '—'}</KV>
              <KV label="Quantity">{trade().quantity ?? '—'}</KV>
              <KV label="Capital">₹{fmtNum(trade().capital_required, 0)}</KV>
              <KV label="Position">{humanize(trade().position_status)}</KV>
              <KV label="Spread guard">{trade().spread_guard_pct != null ? `${fmtNum(trade().spread_guard_pct * 100, 1)}%` : '—'}</KV>
            </div>
          </Show>
          <div class="mb-muted mb-clamp-2">Strategy reason: {cand().strategy_reason || '—'}</div>
        </div>
      </Show>
      <Show when={(setup().rejection_reasons || []).length > 0}>
        <div class="mb-rejections">
          <span class="mb-muted">Today's guard rejections:</span>
          <For each={setup().rejection_reasons}>{(r) => <span class="mb-chip">{humanize(r.reason)} ×{r.count}</span>}</For>
        </div>
      </Show>
    </div>
  )
}

function AiPanel(props) {
  const ai = () => props.ai || {}
  const analysis = () => ai().analysis
  const indices = () => {
    const list = analysis()?.indices || []
    return INDEX_ORDER.map(k => list.find(i => i.index_key === k)).filter(Boolean)
  }
  return (
    <Show
      when={ai().status === 'completed' && analysis()}
      fallback={
        <div class="mb-ai-unavailable">
          <strong>{AI_STATUS_TEXT[ai().status] || 'AI ANALYSIS UNAVAILABLE'}</strong>
          <Show when={ai().error}><span class="mb-muted"> ({humanize(ai().error)})</span></Show>
          <div class="mb-muted">Deterministic market, setup, risk and health data above are unaffected.</div>
        </div>
      }
    >
      <p class="mb-ai-summary mb-clamp-3">{analysis().executive_summary}</p>
      <Show when={(analysis().disagreements || []).length > 0}>
        <div class="mb-disagree">
          <For each={analysis().disagreements}>
            {(d) => <span>⚠ {d.index_key}: AI reads {d.ai_bias}, deterministic technical {d.deterministic_technical} / SMC {d.deterministic_smc} — deterministic decision stands.</span>}
          </For>
        </div>
      </Show>
      <div class="mb-ai-grid">
        <For each={indices()}>
          {(i) => (
            <div class="mb-ai-index">
              <div class="mb-ai-index-head"><span class="mb-strong">{i.index_key}</span> <Pill status={i.bias} label={i.bias} tone={i.bias === 'BULLISH' ? 'ok' : i.bias === 'BEARISH' ? 'bad' : 'muted'} /></div>
              <ul class="mb-evidence">
                <For each={(i.evidence || []).slice(0, 3)}>{(e) => <li class="mb-clamp-1">{e.observation} <code>{e.source_key}</code></li>}</For>
              </ul>
              <Show when={i.bullish_scenario}><div class="mb-clamp-2"><b>Bull:</b> {i.bullish_scenario.condition} <i>Invalid if:</i> {i.bullish_scenario.invalidation}</div></Show>
              <Show when={i.bearish_scenario}><div class="mb-clamp-2"><b>Bear:</b> {i.bearish_scenario.condition} <i>Invalid if:</i> {i.bearish_scenario.invalidation}</div></Show>
            </div>
          )}
        </For>
        <div class="mb-ai-index">
          <Show when={analysis().setup_explanation || analysis().no_trade_explanation}>
            <div class="mb-clamp-3"><b>{analysis().setup_explanation ? 'Why it qualified:' : 'Why no trade:'}</b> {analysis().setup_explanation || analysis().no_trade_explanation}</div>
          </Show>
          <Show when={(analysis().key_risks || []).length > 0}>
            <div class="mb-strong">Key risks</div>
            <ul class="mb-evidence"><For each={analysis().key_risks.slice(0, 3)}>{(r) => <li class="mb-clamp-1">{r}</li>}</For></ul>
          </Show>
          <Show when={(analysis().limitations || []).length > 0}>
            <div class="mb-muted mb-clamp-2">Limitations: {analysis().limitations.join(' · ')}</div>
          </Show>
        </div>
      </div>
    </Show>
  )
}

export default function MarketBriefSheet(props) {
  const brief = () => props.brief || {}
  const snap = () => brief().snapshot || {}
  const indices = () => {
    const list = snap().indices || []
    const ordered = INDEX_ORDER.map(k => list.find(i => i.index_key === k)).filter(Boolean)
    return ordered.concat(list.filter(i => !INDEX_ORDER.includes(i.index_key)))
  }
  const risk = () => snap().risk || {}
  const pnl = () => risk().pnl || {}
  const loss = () => risk().daily_loss || {}
  const vix = () => snap().market_context?.vix || {}
  const health = () => snap().health?.components || {}
  const modeLabel = () => (snap().mode || brief().mode || '').toUpperCase()

  return (
    <article class="mb-sheet" data-testid="market-brief-sheet">
      <header class="mb-header">
        <div>
          <h1>Algo Scalper Market Brief</h1>
          <div class="mb-muted">NSE / BSE index options buying · NIFTY · BANKNIFTY · SENSEX</div>
        </div>
        <div class="mb-header-meta">
          <span class={`mb-mode mb-mode-${(snap().mode || 'paper')}`}>{modeLabel() || '—'}</span>
          <KV label="Trading date">{snap().trading_date || brief().trading_date || '—'} ({snap().timezone || IST})</KV>
          <KV label="Generated">{fmtDateTime(snap().generated_at)} IST</KV>
          <KV label="Session"><Pill status={snap().session?.status || 'unavailable'} /></KV>
          <KV label="Data"><Pill status={snap().freshness?.state || 'unavailable'} /> {snap().warnings?.length ? `${snap().warnings.length} warnings` : ''}</KV>
          <KV label="AI"><Pill status={brief().ai?.status || 'pending'} label={brief().ai?.status === 'completed' ? (brief().ai?.model || 'validated') : brief().ai?.status === 'unavailable' ? 'UNAVAILABLE' : undefined} /></KV>
        </div>
      </header>

      <div class="mb-indices">
        <For each={indices()} fallback={<div class="mb-empty">NO DATA — no index snapshot in this report.</div>}>
          {(idx) => <IndexCard index={idx} />}
        </For>
      </div>

      <div class="mb-middle">
        <Section title="Technical & SMC confluence" class="mb-confluence" badge={<span class="mb-muted">observations · SMC from AnalysisStore, regime 5m</span>}>
          <ConfluenceTable indices={indices()} />
          <div class="mb-muted">▲ bullish · ▼ bearish · ■ range · — unavailable. Supertrend is not shown: no cross-process Supertrend snapshot exists.</div>
        </Section>
        <Section title="Best qualified options setup" class="mb-setup-section" badge={<span class="mb-muted">deterministic pipeline</span>}>
          <SetupPanel setup={snap().setup} />
        </Section>
      </div>

      <div class="mb-lower">
        <Section title="Market context">
          <KV label="India VIX">{fmtNum(vix().value)} <Pill status={vix().status || 'unavailable'} /></KV>
          <KV label="VIX entry gate">{vix().entry_allowed === false ? 'BLOCKING' : vix().entry_allowed === true ? 'allows entries' : '—'}{vix().force_exit_active ? ' · FORCE EXIT' : ''}</KV>
          <KV label="VIX observed">{fmtTime(vix().observed_at)} {fmtAge(vix().age_seconds)}</KV>
          <div class="mb-muted mb-clamp-2">Unavailable (no verified source): {(snap().market_context?.unavailable || []).map(humanize).join(', ') || '—'}</div>
        </Section>
        <Section title="Account & risk" badge={<Pill status={risk().circuit_breaker?.tripped ? 'BLOCKED' : (risk().status || 'unavailable')} label={risk().circuit_breaker?.tripped ? 'BREAKER TRIPPED' : undefined} />}>
          <div class="mb-two-col">
            <KV label="Realized P&L" class={pnl().realized_rupees < 0 ? 'mb-down' : ''}>₹{fmtNum(pnl().realized_rupees)}</KV>
            <KV label="Unrealized P&L" class={pnl().unrealized_rupees < 0 ? 'mb-down' : ''}>₹{fmtNum(pnl().unrealized_rupees)}</KV>
            <KV label="Total day P&L" class={pnl().total_rupees < 0 ? 'mb-down' : 'mb-up'}>₹{fmtNum(pnl().total_rupees)}</KV>
            <KV label="Closed W / L">{pnl().closed_trades ?? '—'} ({pnl().winners ?? '—'} / {pnl().losers ?? '—'})</KV>
            <KV label="Active positions">{risk().active_positions_count ?? '—'}</KV>
            <KV label="Exposure">₹{fmtNum(risk().exposure_rupees, 0)} ({fmtNum(risk().exposure_pct_of_capital, 1)}%)</KV>
            <KV label="Daily loss used">{fmtNum(loss().utilization_pct, 1)}% of ₹{fmtNum(loss().global_limit_rupees, 0)}</KV>
            <KV label="Circuit breaker">{risk().circuit_breaker ? (risk().circuit_breaker.tripped ? `TRIPPED${risk().circuit_breaker.reason ? ` (${risk().circuit_breaker.reason})` : ''}` : 'armed') : '—'}</KV>
          </div>
          <Show when={risk().reconciliation_discrepancies?.unresolved_count > 0}>
            <div class="mb-chip mb-tone-bad">Broker/DB discrepancies unresolved: {risk().reconciliation_discrepancies.unresolved_count}</div>
          </Show>
          <div class="mb-muted">Loss utilization basis: {humanize(loss().basis)}</div>
        </Section>
        <Section title="System health" badge={<Pill status={snap().health?.status || 'unavailable'} />}>
          <KV label="Market feed"><Pill status={health().market_feed?.status || 'unavailable'} /> last tick {fmtTime(health().market_feed?.last_tick_at)}</KV>
          <KV label="Signal scheduler"><Pill status={health().signal_scheduler?.status || 'unavailable'} /></KV>
          <KV label="Trading daemon"><Pill status={health().trading_daemon?.status || 'unavailable'} /></KV>
          <KV label="Order-update feed"><Pill status={health().order_update_feed?.status || 'unavailable'} /></KV>
          <KV label="Reconciliation"><Pill status={health().reconciliation?.status || 'unavailable'} /> {fmtAge(health().reconciliation?.age_seconds)}</KV>
        </Section>
      </div>

      <Section title="AI interpretation" class="mb-ai" badge={<span class="mb-muted">analysis of the facts above · not a trading signal · cannot change the setup decision</span>}>
        <AiPanel ai={brief().ai} />
      </Section>

      <footer class="mb-footer">
        <span>Report #{brief().id ?? '—'} · schema v{snap().schema_version ?? brief().schema_version ?? '—'} · digest {(brief().snapshot_digest || '').slice(0, 12) || '—'}</span>
        <span>Generated from cached authoritative sources; "—" / NO DATA means the value was unavailable, never zero. Not investment advice.</span>
      </footer>
    </article>
  )
}
