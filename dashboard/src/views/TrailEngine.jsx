/* @refresh reload */
import {
  createSignal,
  createMemo,
  createResource,
  createEffect,
  For,
  Show,
  onMount
} from 'solid-js'
import { A, useSearchParams } from '@solidjs/router'
import { dashboardApiHeaders } from '../lib/dashboardApi'
import { usePositions } from '../stores/usePositions'
import { aggregateCandles } from '../lib/trailEngine/aggregate'
import {
  TRAIL_STAGES,
  computeChopScore,
  engineDecide,
  getStage
} from '../lib/trailEngine/trail'
import {
  consecutiveAgainstBars,
  currentIstClock,
  estimateBidAsk,
  normalizeApiCandles,
  openingRangePoints,
  optionTypeFromSymbol,
  peakPremiumFromPosition,
  positionDirFromOption
} from '../lib/trailEngine/marketData'
import { runUnitTests } from '../lib/trailEngine/unitTests'

const C = {
  bg: '#07070E',
  panel: '#0C0C18',
  border: '#181830',
  muted: '#3A3A5A',
  dim: '#8892B0',
  text: '#E2E8F0',
  amber: '#F0A500',
  green: '#00FF88',
  red: '#FF4444',
  blue: '#00CFFF',
  purple: '#BD93F9'
}
const MO = "'JetBrains Mono','Fira Code','Courier New',monospace"

async function fetchCandles1m(indexKey) {
  const res = await fetch(`/api/candles/${indexKey}?interval=1&days=2`, { headers: dashboardApiHeaders() })
  if (!res.ok) throw new Error(`candles: ${res.status}`)
  const data = await res.json()
  return normalizeApiCandles(data.candles || [])
}

async function fetchVix() {
  const res = await fetch('/api/market/vix', { headers: dashboardApiHeaders() })
  if (!res.ok) return { vix: null }
  return res.json()
}

function Tag(props) {
  return (
    <span
      style={{
        display: 'inline-flex',
        'align-items': 'center',
        gap: '4px',
        padding: '2px 8px',
        'border-radius': '3px',
        border: '1px solid ' + props.color + '44',
        background: props.color + '12',
        color: props.color,
        'font-family': MO,
        'font-size': '9px',
        'font-weight': '700',
        'letter-spacing': '0.1em'
      }}
      class={props.class || ''}
    >
      <Show when={props.dot}>
        <span style={{ width: '5px', height: '5px', 'border-radius': '50%', background: props.color, 'flex-shrink': '0' }} />
      </Show>
      {props.text}
    </span>
  )
}

function TestPanel(props) {
  return (
    <Show
      when={props.results}
      fallback={<div style={{ 'font-size': '9px', color: C.muted, 'font-family': MO }}>— run tests first —</div>}
    >
      {results => {
        const pass = results.filter(r => r.pass).length
        return (
          <div>
            <div style={{ display: 'flex', 'justify-content': 'space-between', 'margin-bottom': '8px' }}>
              <span style={{ 'font-size': '9px', color: C.dim, 'font-family': MO }}>UNIT TESTS</span>
              <Tag color={pass === results.length ? C.green : C.red} text={`${pass}/${results.length} PASS`} dot />
            </div>
            <For each={results}>
              {r => (
                <div style={{ display: 'flex', gap: '6px', padding: '4px 0', 'border-bottom': '1px solid ' + C.border }}>
                  <span style={{ 'font-size': '9px', color: r.pass ? C.green : C.red, 'font-family': MO, 'flex-shrink': '0' }}>
                    {r.pass ? '✓' : '✗'}
                  </span>
                  <div>
                    <div style={{ 'font-size': '9px', color: r.pass ? C.text : C.red, 'font-family': MO }}>{r.name}</div>
                    <div style={{ 'font-size': '8px', color: C.muted, 'font-family': MO }}>{r.detail}</div>
                  </div>
                </div>
              )}
            </For>
          </div>
        )
      }}
    </Show>
  )
}

function ChopMeter(props) {
  return (
    <Show
      when={props.result}
      fallback={
        <div style={{ 'font-size': '9px', color: C.muted, 'font-family': MO, 'text-align': 'center', padding: '20px' }}>
          — awaiting index candles —
        </div>
      }
    >
      {result => {
        const pct = Math.min((result.score / result.maxScore) * 100, 100)
        const color = result.blocked ? C.red : result.borderline ? C.amber : C.green
        const stateLabel = result.blocked ? 'HIGH CHOP (BLOCKED)' : result.borderline ? 'MODERATE CHOP' : 'CLEAR TREND'
        return (
          <div>
            <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center', 'margin-bottom': '8px' }}>
              <span style={{ 'font-size': '9px', color: C.muted, 'font-family': MO, 'letter-spacing': '0.1em' }}>
                CHOP SCORE (LIVE INDEX)
              </span>
              <div style={{ display: 'flex', gap: '6px', 'align-items': 'center' }}>
                <span style={{ 'font-family': MO, 'font-size': '16px', 'font-weight': '800', color }}>
                  {result.score}
                  <span style={{ 'font-size': '9px', color: C.dim }}>/{result.maxScore}</span>
                </span>
                <Tag color={color} text={stateLabel} dot />
              </div>
            </div>
            <div style={{ background: C.muted + '30', 'border-radius': '3px', height: '5px', 'margin-bottom': '10px' }}>
              <div style={{ width: `${pct}%`, height: '100%', background: color, 'border-radius': '3px', transition: 'width 0.4s' }} />
            </div>
            
            <div style={{ display: 'grid', 'grid-template-columns': '1fr 1fr', gap: '5px', 'margin-top': '8px' }}>
              <For
                each={[
                  { label: `ADX ${result.adxVal?.toFixed(1)}`, ok: !result.adxFail, desc: result.adxFail ? 'No Trend' : 'Trend Active' },
                  { label: `ST Flips ${result.flips}×`, ok: result.flips < 3, desc: `${result.flips} flips` },
                  { label: `BBW ${(result.bbw * 100).toFixed(2)}%`, ok: result.bbw >= 0.005, desc: result.bbw < 0.005 ? 'Squeeze' : 'Expanded' },
                  { label: `ST TFs`, ok: !result.tfFail, desc: result.tfFail ? 'Conflict' : 'Aligned' }
                ]}
              >
                {item => (
                  <div
                    style={{
                      background: (item.ok ? C.green : C.red) + '04',
                      border: '1px solid ' + (item.ok ? C.border : C.red + '1a'),
                      padding: '4px 6px',
                      'border-radius': '3px',
                      display: 'flex',
                      'justify-content': 'space-between',
                      'align-items': 'center'
                    }}
                  >
                    <span style={{ 'font-size': '8.5px', color: item.ok ? C.text : C.red, 'font-family': MO }}>
                      {item.ok ? '✓' : '✗'} {item.label}
                    </span>
                    <span style={{ 'font-size': '7px', color: C.dim, 'font-family': MO }}>{item.desc}</span>
                  </div>
                )}
              </For>
            </div>
          </div>
        )
      }}
    </Show>
  )
}

function TrailChart(props) {
  return (
    <Show
      when={props.path?.length}
      fallback={
        <div
          style={{
            display: 'flex',
            'align-items': 'center',
            'justify-content': 'center',
            height: '100%',
            color: C.muted,
            'font-size': '10px',
            'font-family': MO
          }}
        >
          — awaiting live premium ticks —
        </div>
      }
    >
      {() => {
        const path = props.path
        const entry = props.entry
        const effectiveStop = props.effectiveStop
        const hardStop = props.hardStop
        const exitTick = props.exitTick
        
        const W = 480
        const H = 130
        const prices = path.map(p => p.lastPrice)
        
        // Collect all price values to determine y-scale bounding box
        const all = [...prices, entry]
        if (effectiveStop != null) all.push(effectiveStop)
        if (hardStop != null) all.push(hardStop)
        
        const minV = Math.min(...all) * 0.985
        const maxV = Math.max(...all) * 1.015
        
        const sx = (i, len) => (i / Math.max(len - 1, 1)) * W
        const sy = v => H - ((v - minV) / (Math.max(maxV - minV, 0.1))) * H
        
        const pricePts = prices.map((p, i) => `${sx(i, prices.length)},${sy(p)}`).join(' ')
        
        const areaPts = prices.length > 0
          ? `0,${H} ` + prices.map((p, i) => `${sx(i, prices.length)},${sy(p)}`).join(' ') + ` ${W},${H}`
          : null

        const currentP = prices.at(-1) ?? entry
        const priceColor = currentP >= entry ? C.green : C.red

        return (
          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: '100%', display: 'block', overflow: 'hidden' }}>
            <defs>
              <linearGradient id="chart-area-grad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color={priceColor} stop-opacity={0.15} />
                <stop offset="100%" stop-color={priceColor} stop-opacity={0.0} />
              </linearGradient>
            </defs>

            <For each={[0.25, 0.5, 0.75]}>
              {f => (
                <line x1={0} y1={H * f} x2={W} y2={H * f} stroke={C.border} stroke-width={0.5} stroke-dasharray="2,4" opacity={0.4} />
              )}
            </For>
            <For each={[0.25, 0.5, 0.75]}>
              {f => (
                <line x1={W * f} y1={0} x2={W * f} y2={H} stroke={C.border} stroke-width={0.5} stroke-dasharray="2,4" opacity={0.4} />
              )}
            </For>
            <line x1={0} y1={sy(entry)} x2={W} y2={sy(entry)} stroke={C.blue} stroke-width={0.8} stroke-dasharray="3,3" opacity={0.6} />
            <Show when={hardStop != null}>
              <line x1={0} y1={sy(hardStop)} x2={W} y2={sy(hardStop)} stroke={C.red} stroke-width={0.8} stroke-dasharray="2,2" opacity={0.6} />
            </Show>
            <Show when={effectiveStop != null}>
              <line x1={0} y1={sy(effectiveStop)} x2={W} y2={sy(effectiveStop)} stroke={C.amber} stroke-width={0.8} stroke-dasharray="3,2" opacity={0.6} />
            </Show>
            <Show when={prices.length > 0}>
              <polygon points={areaPts} fill="url(#chart-area-grad)" />
            </Show>
            <Show when={exitTick != null && exitTick >= 0}>
              <line x1={sx(exitTick, prices.length)} y1={0} x2={sx(exitTick, prices.length)} y2={H} stroke={C.red} stroke-width={1.2} stroke-dasharray="3,3" />
            </Show>
            <Show when={prices.length > 1}>
              <polyline points={pricePts} fill="none" stroke={priceColor} stroke-width={1.8} />
            </Show>
            <Show when={prices.length > 0}>
              <circle cx={sx(prices.length - 1, prices.length)} cy={sy(prices.at(-1))} r={6} fill={priceColor} opacity={0.25} class="animate-ping" />
              <circle cx={sx(prices.length - 1, prices.length)} cy={sy(prices.at(-1))} r={3.2} fill={priceColor} />
            </Show>
          </svg>
        )
      }}
    </Show>
  )
}

function StageRail(props) {
  return (
    <div style={{ display: 'flex', 'flex-direction': 'column', gap: '5px' }}>
      <For each={TRAIL_STAGES}>
        {s => {
          const isPeak = s.id === props.peakId
          const isCurrent = s.id === props.currentId
          const active = isPeak || isCurrent
          
          return (
            <div
              style={{
                padding: '6px 10px',
                'border-radius': '5px',
                border: '1px solid ' + (active ? s.color : C.border),
                background: isCurrent 
                  ? s.color + '14' 
                  : isPeak 
                    ? s.color + '08' 
                    : C.panel,
                opacity: active ? 1 : 0.35,
                transition: 'all 0.3s ease',
                position: 'relative',
                overflow: 'hidden'
              }}
            >
              <Show when={isCurrent}>
                <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '3px', background: s.color }} />
              </Show>
              
              <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                <div style={{ display: 'flex', 'align-items': 'center', gap: '6px' }}>
                  <span style={{ 'font-size': '11px' }}>{s.icon}</span>
                  <div>
                    <span style={{ color: s.color, 'font-family': MO, 'font-size': '9.5px', 'font-weight': '800' }}>
                      {s.label.toUpperCase()}
                    </span>
                    <div style={{ 'font-size': '7.5px', color: C.dim }}>
                      {isCurrent ? 'Active Price Stage' : isPeak ? 'Peak Triggered Stage' : `Range: ${s.range[0]}% - ${s.range[1]}%`}
                    </div>
                  </div>
                </div>
                <div style={{ 'text-align': 'right' }}>
                  <span style={{ 'font-size': '10px', color: s.color, 'font-family': MO, 'font-weight': '800' }}>
                    {s.trailPct}%
                  </span>
                  <div style={{ 'font-size': '6.5px', color: C.muted }}>Stop Offset</div>
                </div>
              </div>
            </div>
          )
        }}
      </For>
    </div>
  )
}

const TF_ROWS = [
  { tf: '1M', dirKey: 'd1', matchKey: 'match1m' },
  { tf: '5M', dirKey: 'd5', matchKey: 'match5m' },
  { tf: '15M', dirKey: 'd15', matchKey: 'match15m' }
]

function TrendConfluencePanel(props) {
  const rows = createMemo(() => {
    const tc = props.confluence
    if (!tc) return []
    return TF_ROWS.map(row => ({
      tf: row.tf,
      dir: tc[row.dirKey],
      aligned: tc[row.matchKey]
    }))
  })

  return (
    <div style={{ display: 'grid', 'grid-template-columns': 'repeat(3, 1fr)', gap: '6px' }}>
      <For each={rows()}>
        {row => {
          const tfColor = row.aligned ? C.green : C.red
          const sign = row.dir === 1 ? '↑ BULL' : row.dir === -1 ? '↓ BEAR' : '—'
          return (
            <div
              style={{
                background: tfColor + '06',
                border: '1px solid ' + tfColor + '12',
                padding: '4px 3px',
                'border-radius': '3px',
                'text-align': 'center',
                display: 'flex',
                'flex-direction': 'column',
                gap: '1px'
              }}
            >
              <div style={{ 'font-size': '8px', color: C.dim, 'font-weight': 'bold' }}>{row.tf}</div>
              <div style={{ 'font-size': '9.5px', color: tfColor, 'font-weight': '900' }}>{sign}</div>
              <div style={{ 'font-size': '6.5px', color: C.muted }}>{row.aligned ? 'MATCH' : 'CONFLICT'}</div>
            </div>
          )
        }}
      </For>
    </div>
  )
}

function DecisionLog(props) {
  const events = createMemo(() => (props.decisions || []).filter(d => d.action !== 'HOLD').slice(-6).reverse())
  return (
    <Show when={events().length} fallback={<div style={{ 'font-size': '9px', color: C.muted, 'font-family': MO }}>— holding active position —</div>}>
      <For each={events()}>
        {d => {
          const color = d.action === 'EXIT' ? C.red : d.action === 'WARN' ? C.amber : C.green
          return (
            <div
              style={{
                display: 'flex',
                gap: '8px',
                'align-items': 'center',
                padding: '6px 8px',
                background: color + '06',
                'border-left': '3px solid ' + color,
                'border-radius': '0 4px 4px 0',
                'margin-bottom': '4px',
                border: '1px solid ' + color + '15',
                'border-left-width': '3px'
              }}
            >
              <Tag color={color} text={d.action} />
              <span style={{ 'font-size': '9px', color: C.text, 'font-family': MO, flex: '1' }}>{d.reason}</span>
              <span style={{ 'font-size': '8px', color: C.dim, 'font-family': MO }}>{d.execution?.regime ?? ''}</span>
            </div>
          )
        }}
      </For>
    </Show>
  )
}

/**
 * Fullscreen trail engine — live position + index candles. Route: /trail-engine (not in Header nav).
 */
export default function TrailEngine() {
  const [searchParams] = useSearchParams()
  const { open, connected: positionsConnected, fetchPositions, closeOpenPosition, closingPositionId } = usePositions()

  const [selectedId, setSelectedId] = createSignal(null)
  const [activeTab, setActiveTab] = createSignal('engine')
  const [testResults, setTestResults] = createSignal(null)
  const [premiumPath, setPremiumPath] = createSignal([])
  const [decisions, setDecisions] = createSignal([])
  const [lastDecision, setLastDecision] = createSignal(null)
  const [trackedPeak, setTrackedPeak] = createSignal(0)

  // 1-second timer for hold duration
  const [timeNow, setTimeNow] = createSignal(Date.now())
  const [exitConfirm, setExitConfirm] = createSignal(false)
  let confirmTimeout

  const position = createMemo(() => {
    const list = open() || []
    const id = selectedId() ?? searchParams.position
    if (id) return list.find(p => String(p.id) === String(id)) ?? list[0] ?? null
    return list[0] ?? null
  })

  const indexKey = createMemo(() => (position()?.index_key || 'NIFTY').toUpperCase())

  const [candles1m, { refetch: refetchCandles }] = createResource(indexKey, fetchCandles1m)
  const [vixPayload] = createResource(fetchVix)

  const candles5m = createMemo(() => aggregateCandles(candles1m() || [], 5))
  const candles15m = createMemo(() => aggregateCandles(candles1m() || [], 15))

  const chopResult = createMemo(() => {
    const c1 = candles1m()
    if (!c1?.length) return null
    const vix = vixPayload()?.vix ?? 15
    const last = c1.at(-1)
    return computeChopScore({
      candles1m: c1,
      candles5m: candles5m(),
      candles15m: candles15m(),
      vix,
      indexName: indexKey(),
      openingRangePts: openingRangePoints(c1),
      minutesSinceOpen: last?.minutesSinceOpen ?? 0
    })
  })

  createEffect(() => {
    const pos = position()
    if (!pos) {
      setPremiumPath([])
      setDecisions([])
      setLastDecision(null)
      setTrackedPeak(0)
      return
    }

    const entry = Number(pos.entry_price) || 0
    const ltp = Number(pos.ltp) || entry
    setTrackedPeak(prev => peakPremiumFromPosition(pos, prev))
    setPremiumPath(prev => {
      const clock = currentIstClock()
      const next = [
        ...prev,
        {
          t: prev.length,
          lastPrice: ltp,
          hour: clock.hour,
          minute: clock.minute,
          ts: Date.now()
        }
      ]
      return next.slice(-120)
    })
  })

  createEffect(() => {
    const pos = position()
    const c1 = candles1m()
    const path = premiumPath()
    if (!pos || !c1?.length || !path.length) return

    const entry = Number(pos.entry_price) || 0
    const ltp = Number(pos.ltp) || entry
    const qty = Number(pos.quantity) || 1
    const optionType = optionTypeFromSymbol(pos.symbol)
    const positionDir = positionDirFromOption(optionType)
    const peak = peakPremiumFromPosition(pos, trackedPeak())
    const vix = vixPayload()?.vix ?? 15
    const { bid, ask } = estimateBidAsk(ltp, vix)
    const clock = currentIstClock()

    const decision = engineDecide({
      entry,
      peak,
      bid,
      ask,
      lastPrice: ltp,
      positionDir,
      candles1m: c1,
      vix,
      indexName: indexKey(),
      openingRangePts: openingRangePoints(c1),
      minutesSinceOpen: c1.at(-1)?.minutesSinceOpen ?? 0,
      currentHour: clock.hour,
      currentMinute: clock.minute,
      consecutiveAgainst: consecutiveAgainstBars(c1, positionDir),
      lotSize: qty
    })

    setLastDecision(decision)
    setDecisions(prev => {
      const last = prev.at(-1)
      if (last?.reason === decision.reason && last?.action === decision.action) return prev
      return [...prev.slice(-119), { ...decision, t: path.length - 1 }]
    })
  })

  let pollId
  onMount(() => {
    fetchPositions()
    pollId = setInterval(() => {
      refetchCandles()
      fetchPositions()
    }, 30000)

    const timer = setInterval(() => setTimeNow(Date.now()), 1000)

    return () => {
      clearInterval(pollId)
      clearInterval(timer)
      clearTimeout(confirmTimeout)
    }
  })

  const entry = () => Number(position()?.entry_price) || 0
  const currentP = () => Number(position()?.ltp) || entry()
  const peak = () => peakPremiumFromPosition(position() || {}, trackedPeak())
  const peakPct = () => (entry() > 0 ? ((peak() - entry()) / entry()) * 100 : 0)
  const currentPct = () => (entry() > 0 ? ((currentP() - entry()) / entry()) * 100 : 0)
  const ld = () => lastDecision()

  // Hold time helpers
  const holdTimeSec = createMemo(() => {
    const pos = position()
    if (!pos) return null
    if (pos.created_at) {
      const entryMs = new Date(pos.created_at).getTime()
      return Math.max(0, Math.floor((timeNow() - entryMs) / 1000))
    }
    return pos.time_in_position_sec ?? null
  })

  const formatHoldTime = (sec) => {
    if (sec == null) return '—'
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}m ${s}s`
  }

  const thetaDanger = createMemo(() => {
    const sec = holdTimeSec()
    if (sec == null) return { label: 'NO POSITION', color: C.muted, level: 'none' }
    if (sec < 300) return { label: 'SAFE (LOW)', color: C.green, level: 'low' }
    if (sec < 600) return { label: 'MODERATE', color: C.amber, level: 'moderate' }
    if (sec < 900) return { label: 'HIGH DECAY', color: C.amber, level: 'high' }
    return { label: 'SEVERE DECAY', color: C.red, level: 'severe' }
  })

  // Drawdown helpers
  const peakDrawdownRs = createMemo(() => {
    const pos = position()
    if (!pos) return 0
    const qty = Number(pos.quantity) || 1
    const pk = peak()
    const ltp = currentP()
    return Math.max(0, (pk - ltp) * qty)
  })

  const peakDrawdownPct = createMemo(() => {
    const pk = peak()
    if (pk <= 0) return 0
    const ltp = currentP()
    return ((pk - ltp) / pk) * 100
  })

  // Bid-Ask and Regime helpers
  const spreadInfo = createMemo(() => {
    const ltp = currentP()
    const vix = vixPayload()?.vix ?? 15
    const { bid, ask, spread } = estimateBidAsk(ltp, vix)
    const midpoint = (bid + ask) / 2
    const spreadPct = midpoint > 0 ? (spread / midpoint) * 100 : 0

    let regime = 'NORMAL'
    let slippageMult = 0.3
    let color = C.green

    if (spreadPct < 0.8) {
      regime = 'NORMAL'
      slippageMult = 0.3
      color = C.green
    } else if (spreadPct < 1.5) {
      regime = 'FAST'
      slippageMult = 0.6
      color = C.amber
    } else if (spreadPct < 3.0) {
      regime = 'PANIC'
      slippageMult = 1.2
      color = C.red
    } else {
      regime = 'CIRCUIT'
      slippageMult = 2.5
      color = C.purple
    }

    const slippage = spread * slippageMult
    return {
      bid,
      ask,
      spread,
      spreadPct,
      regime,
      slippage,
      color
    }
  })

  // Trend Confluence
  const trendConfluence = createMemo(() => {
    const chop = chopResult()
    const pos = position()
    if (!chop || !pos) return null

    const optionType = optionTypeFromSymbol(pos.symbol)
    const posDir = positionDirFromOption(optionType)

    const match1m = chop.d1 === posDir
    const match5m = chop.d5 === posDir
    const match15m = chop.d15 === posDir

    const count = (match1m ? 1 : 0) + (match5m ? 1 : 0) + (match15m ? 1 : 0)

    let label = 'MISMATCH'
    let color = C.red
    if (count === 3) {
      label = `3/3 ${optionType} CONFLUENCE`
      color = C.green
    } else if (count === 2) {
      label = `2/3 ALIGNED`
      color = C.amber
    } else {
      label = `TREND MISMATCH`
      color = C.red
    }

    return { count, label, color, match1m, match5m, match15m, d1: chop.d1, d5: chop.d5, d15: chop.d15, posDir, optionType }
  })

  const isClosing = () => closingPositionId() === position()?.id

  function handleManualExit() {
    const pos = position()
    if (!pos) return

    if (!exitConfirm()) {
      setExitConfirm(true)
      clearTimeout(confirmTimeout)
      confirmTimeout = setTimeout(() => setExitConfirm(false), 4000)
    } else {
      setExitConfirm(false)
      clearTimeout(confirmTimeout)
      closeOpenPosition(pos.id)
    }
  }

  function runTests() {
    setTestResults(runUnitTests())
    setActiveTab('tests')
  }

  const cell = { background: C.panel, border: `1px solid ${C.border}`, 'border-radius': '6px', padding: '10px 12px' }

  return (
    <div style={{ background: C.bg, 'min-height': '100vh', 'font-family': MO, color: C.text }}>
      
      {/* Cockpit Title bar */}
      <div
        style={{
          'border-bottom': `1px solid ${C.border}`,
          padding: '11px 20px',
          display: 'flex',
          'align-items': 'center',
          'justify-content': 'space-between',
          background: '#090914'
        }}
      >
        <div style={{ display: 'flex', 'align-items': 'center', gap: '16px' }}>
          <A href="/" style={{ 'font-size': '10px', color: C.dim, 'text-decoration': 'none', 'letter-spacing': '0.1em' }}>
            ← Terminal
          </A>
          <div>
            <div style={{ 'font-size': '11px', 'font-weight': '800', 'letter-spacing': '0.2em', color: C.amber }}>
              ◈ TRAIL ENGINE v3 — OPTIONS COCKPIT
            </div>
            <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', marginTop: '1px' }}>
              MOMENTUM CONFLUENCE · THETA DECAY ALERTS · SLIPPAGE EST · WS LTP
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: '6px', 'align-items': 'center' }}>
          <Tag color={positionsConnected() ? C.green : C.red} text={positionsConnected() ? 'POSITIONS WS' : 'WS OFFLINE'} dot />
          <Tag color={position() ? C.green : C.amber} text={position() ? 'POSITION LIVE' : 'NO OPEN POSITION'} dot />
        </div>
      </div>

      {/* Tabs / Sub-header bar */}
      <div style={{ display: 'flex', 'border-bottom': `1px solid ${C.border}`, background: '#09090F', 'align-items': 'center' }}>
        <For each={[
          ['engine', '◈ COCKPIT ENGINE'],
          ['tests', '⊕ UNIT TESTS']
        ]}>
          {([id, lbl]) => (
            <button
              type="button"
              onClick={() => setActiveTab(id)}
              style={{
                padding: '8px 20px',
                background: 'transparent',
                border: 'none',
                'border-bottom': `2px solid ${activeTab() === id ? C.amber : 'transparent'}`,
                color: activeTab() === id ? C.amber : C.muted,
                'font-family': MO,
                'font-size': '10px',
                cursor: 'pointer'
              }}
            >
              {lbl}
            </button>
          )}
        </For>
        
        {/* Unit Tests Button */}
        <button
          type="button"
          onClick={runTests}
          style={{
            'margin-left': 'auto',
            'margin-right': '12px',
            padding: '5px 14px',
            background: `${C.blue}14`,
            border: `1px solid ${C.blue}44`,
            color: C.blue,
            'font-family': MO,
            'font-size': '9px',
            cursor: 'pointer',
            'border-radius': '3px'
          }}
        >
          ▷ RUN TESTS
        </button>
      </div>

      <Show when={activeTab() === 'tests'} fallback={null}>
        <div style={{ padding: '20px', 'max-width': '700px' }}>
          <TestPanel results={testResults()} />
        </div>
      </Show>

      {/* Cockpit Engine View */}
      <Show when={activeTab() === 'engine'}>
        <div style={{ padding: '16px 20px', display: 'grid', 'grid-template-columns': '1fr 310px', gap: '14px' }}>
          
          {/* Main Console Area */}
          <div style={{ display: 'flex', 'flex-direction': 'column', gap: '12px' }}>
            
            {/* Top selection & actions panel */}
            <div style={{ ...cell, display: 'grid', 'grid-template-columns': '3fr 2fr', gap: '12px', 'align-items': 'center' }}>
              <div>
                <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '4px' }}>ACTIVE OPTION CONTRACT SELECTOR</div>
                <select
                  value={position()?.id ?? ''}
                  onChange={e => setSelectedId(e.target.value)}
                  style={{
                    width: '100%',
                    background: C.bg,
                    border: `1px solid ${C.border}`,
                    color: C.text,
                    padding: '6px',
                    'border-radius': '4px',
                    'font-family': MO,
                    'font-size': '10px'
                  }}
                  class="glass-select"
                >
                  <Show when={!(open()?.length)} fallback={null}>
                    <option value="">No open positions</option>
                  </Show>
                  <For each={open() || []}>
                    {p => (
                      <option value={p.id}>
                        {p.symbol} · ₹{p.ltp} · PnL {p.pnl >= 0 ? '+' : ''}₹{p.pnl} ({p.pnl_pct >= 0 ? '+' : ''}{p.pnl_pct}%)
                      </option>
                    )}
                  </For>
                </select>
              </div>
              
              {/* Emergency Close Action */}
              <div style={{ 'text-align': 'right', display: 'flex', 'flex-direction': 'column', 'align-items': 'flex-end', gap: '4px' }}>
                <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '2px' }}>CRITICAL EXIT OVERRIDE</div>
                <Show
                  when={position()}
                  fallback={
                    <div style={{ 'font-size': '9px', color: C.muted }}>— no active contract —</div>
                  }
                >
                  <button
                    type="button"
                    onClick={handleManualExit}
                    disabled={isClosing()}
                    style={{
                      width: '100%',
                      padding: '7px 14px',
                      background: isClosing()
                        ? '#44444433'
                        : exitConfirm()
                          ? '#ff4444ee'
                          : 'rgba(255, 68, 68, 0.12)',
                      border: `1px solid ${isClosing() ? '#444444' : '#FF4444'}`,
                      color: exitConfirm() ? '#000000' : '#FF4444',
                      'font-family': MO,
                      'font-weight': '900',
                      'font-size': '9px',
                      'border-radius': '4px',
                      cursor: isClosing() ? 'not-allowed' : 'pointer',
                      transition: 'all 0.2s ease',
                      'letter-spacing': '0.08em'
                    }}
                    class={exitConfirm() ? 'pulse-theta-severe' : 'glass-hover'}
                  >
                    {isClosing() 
                      ? '⚡ PROCESSING EXIT...' 
                      : exitConfirm() 
                        ? '⚠️ CLICK TO CONFIRM EMERGENCY EXIT' 
                        : '⚡ EMERGENCY MANUAL EXIT'}
                  </button>
                </Show>
              </div>
            </div>

            {/* Grid of 6 Key Option-Trading Cards */}
            <div style={{ display: 'grid', 'grid-template-columns': 'repeat(3, 1fr)', gap: '10px' }}>
              
              {/* Card 1: LTP & Symbol details */}
              <div style={cell}>
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>OPTION LTP & SIDE</div>
                <div style={{ display: 'flex', 'align-items': 'baseline', gap: '6px' }}>
                  <span style={{ 'font-size': '16px', 'font-weight': '900', color: C.text }}>
                    ₹{currentP().toFixed(1)}
                  </span>
                  <span style={{ 'font-size': '9.5px', color: currentP() >= entry() ? C.green : C.red, 'font-weight': '700' }}>
                    {currentP() >= entry() ? '▲' : '▼'} {Math.abs(currentP() - entry()).toFixed(1)}
                  </span>
                </div>
                <div style={{ display: 'flex', 'align-items': 'center', gap: '5px', 'margin-top': '4px' }}>
                  <Tag 
                    color={optionTypeFromSymbol(position()?.symbol) === 'CE' ? C.green : C.red} 
                    text={optionTypeFromSymbol(position()?.symbol)} 
                    dot 
                  />
                  <span style={{ 'font-size': '8px', color: C.dim }}>
                    QTY: {position()?.quantity ?? 0}
                  </span>
                </div>
              </div>

              {/* Card 2: Unrealized PnL & ROI */}
              <div 
                style={{ ...cell, border: `1px solid ${currentP() >= entry() ? C.green : C.red}40` }} 
                class={currentP() >= entry() ? 'glow-card-green glow-pulse-green' : 'glow-card-red glow-pulse-red'}
              >
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>UNREALIZED PNL & ROI</div>
                <div style={{ 'font-size': '16px', 'font-weight': '900', color: currentP() >= entry() ? C.green : C.red, 'font-family': MO }}>
                  {currentP() >= entry() ? '+' : ''}₹{(position()?.pnl ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 1 })}
                </div>
                <div style={{ 'font-size': '9.5px', color: currentP() >= entry() ? C.green : C.red, 'margin-top': '2px', 'font-weight': '700' }}>
                  ROI: {currentPct() >= 0 ? '+' : ''}{currentPct().toFixed(2)}%
                </div>
              </div>

              {/* Card 3: Time Duration & Theta decay risk */}
              <div style={cell} class={thetaDanger().level === 'severe' ? 'pulse-theta-severe' : ''}>
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>DURATION & THETA</div>
                <div style={{ 'font-size': '16px', 'font-weight': '900', color: C.text, 'font-family': MO }}>
                  {formatHoldTime(holdTimeSec())}
                </div>
                <div style={{ 'font-size': '8px', color: thetaDanger().color, 'margin-top': '2px', 'font-weight': '700', 'letter-spacing': '0.05em' }}>
                  DECAY RISK: {thetaDanger().label}
                </div>
              </div>

              {/* Card 4: Stops and Entry levels */}
              <div style={cell}>
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>STOPS & BREAK-EVEN</div>
                <div style={{ display: 'flex', 'flex-direction': 'column', gap: '2px', 'font-family': MO }}>
                  <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                    <span style={{ 'font-size': '8px', color: C.dim }}>TRAIL:</span>
                    <span style={{ 'font-size': '9.5px', 'font-weight': '700', color: C.amber }}>
                      {ld()?.stops?.effectiveStop != null ? `₹${ld().stops.effectiveStop.toFixed(1)}` : '—'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                    <span style={{ 'font-size': '8px', color: C.dim }}>HARD:</span>
                    <span style={{ 'font-size': '9.5px', 'font-weight': '700', color: C.red }}>
                      {ld()?.stops?.hardStop != null ? `₹${ld().stops.hardStop.toFixed(1)}` : '—'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                    <span style={{ 'font-size': '8px', color: C.dim }}>ENTRY:</span>
                    <span style={{ 'font-size': '9.5px', 'font-weight': '700', color: C.blue }}>
                      ₹{entry().toFixed(1)}
                    </span>
                  </div>
                </div>
              </div>

              {/* Card 5: High water mark (Peak) & Pullback */}
              <div style={cell}>
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>PEAK & DRAWDOWN</div>
                <div style={{ 'font-size': '11.5px', 'font-weight': '800', color: C.amber }}>
                  PEAK: ₹{peak().toFixed(1)} <span style={{ 'font-size': '8px', color: C.dim }}>({peakPct() >= 0 ? '+' : ''}{peakPct().toFixed(0)}%)</span>
                </div>
                <div style={{ 'font-size': '9px', color: peakDrawdownPct() > 5 ? C.red : C.dim, 'margin-top': '4px', 'font-weight': '700' }}>
                  GIVEBACK: {peakDrawdownPct() > 0 ? `-${peakDrawdownPct().toFixed(1)}%` : '0.0%'}
                  <span style={{ 'font-size': '7.5px', 'font-weight': 'normal', color: C.muted, 'margin-left': '4px' }}>
                    (₹{peakDrawdownRs().toFixed(0)})
                  </span>
                </div>
              </div>

              {/* Card 6: Slippage, Bid-Ask and Regime */}
              <div style={cell}>
                <div style={{ 'font-size': '8px', color: C.muted, 'letter-spacing': '0.12em', 'margin-bottom': '4px' }}>SPREAD & MARKET REGIME</div>
                <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'baseline' }}>
                  <span style={{ 'font-size': '10px', 'font-weight': '700', color: C.text }}>
                    SPREAD: ₹{spreadInfo().spread.toFixed(2)}
                  </span>
                  <span style={{ 'font-size': '7.5px', color: C.dim }}>
                    ({spreadInfo().spreadPct.toFixed(1)}%)
                  </span>
                </div>
                <div style={{ display: 'flex', 'align-items': 'center', gap: '4px', 'margin-top': '4px' }}>
                  <Tag color={spreadInfo().color} text={spreadInfo().regime} />
                  <span style={{ 'font-size': '7px', color: C.muted }}>
                    Est. Slip: ₹{spreadInfo().slippage.toFixed(1)}
                  </span>
                </div>
              </div>

            </div>

            {/* Premium Trail Chart Card */}
            <div style={{ ...cell, padding: '14px' }}>
              <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                <span style={{ 'font-size': '8.5px', color: C.muted }}>
                  PREMIUM TRAIL · {position()?.symbol ?? 'NO ACTIVE POSITION'}
                </span>
                <Show when={position()?.entry_strategy}>
                  <Tag color={C.blue} text={position()?.entry_strategy} />
                </Show>
              </div>

              {/* Premium Trail Chart Legend */}
              <div style={{ display: 'flex', gap: '12px', 'margin-top': '4px', 'flex-wrap': 'wrap' }}>
                <span style={{ 'font-size': '8px', color: C.blue, 'font-weight': 'bold', 'font-family': MO }}>
                  ● ENTRY: ₹{entry().toFixed(1)}
                </span>
                <Show when={ld()?.stops?.effectiveStop != null}>
                  <span style={{ 'font-size': '8px', color: C.amber, 'font-weight': 'bold', 'font-family': MO }}>
                    ● TRAIL STOP: ₹{ld().stops.effectiveStop.toFixed(1)}
                  </span>
                </Show>
                <Show when={ld()?.stops?.hardStop != null}>
                  <span style={{ 'font-size': '8px', color: C.red, 'font-weight': 'bold', 'font-family': MO }}>
                    ● HARD STOP: ₹{ld().stops.hardStop.toFixed(1)}
                  </span>
                </Show>
                <Show when={premiumPath().length > 0}>
                  <span style={{ 'font-size': '8px', color: currentP() >= entry() ? C.green : C.red, 'font-weight': 'bold', 'font-family': MO }}>
                    ● LTP: ₹{currentP().toFixed(1)}
                  </span>
                </Show>
              </div>

              <div style={{ height: '140px', 'margin-top': '8px' }}>
                <TrailChart 
                  path={premiumPath()} 
                  entry={entry()} 
                  effectiveStop={ld()?.stops?.effectiveStop} 
                  hardStop={ld()?.stops?.hardStop}
                  exitTick={decisions().find(d => d.action === 'EXIT')?.t}
                />
              </div>
            </div>

            {/* Decision Log Card */}
            <div style={cell}>
              <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '8px' }}>DECISION LOG</div>
              <DecisionLog decisions={decisions()} />
            </div>

          </div>

          {/* Side Panels Area */}
          <div style={{ display: 'flex', 'flex-direction': 'column', gap: '12px' }}>
            
            {/* Index / VIX Panel */}
            <div style={cell}>
              <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '4px' }}>UNDERLYING INDEX</div>
              <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                <span style={{ 'font-size': '14px', 'font-weight': '800', color: C.text }}>
                  {indexKey()}
                </span>
                <span style={{ 'font-size': '11px', 'font-weight': '700', color: C.blue }}>
                  VIX: {vixPayload()?.vix?.toFixed(1) ?? '—'}
                </span>
              </div>
              <div style={{ 'font-size': '7.5px', color: C.dim, 'margin-top': '4px' }}>
                OHLC bars: {candles1m()?.length ?? 0} · 30s auto-refresh
              </div>
            </div>

            {/* Chop Score Meter Panel */}
            <div style={cell}>
              <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '8px' }}>CHOP (INDEX PRE-TRADE CONTEXT)</div>
              <ChopMeter result={chopResult()} />
            </div>
            
            {/* Supertrend Confluence Panel */}
            <Show when={position()}>
              <div style={cell}>
                <div style={{ display: 'flex', 'flex-direction': 'column', gap: '8px' }}>
                  <div style={{ display: 'flex', 'justify-content': 'space-between', 'align-items': 'center' }}>
                    <span style={{ 'font-size': '8.5px', color: C.muted }}>TREND CONFLUENCE</span>
                    <span style={{ 'font-size': '8px', 'font-weight': '900', color: trendConfluence()?.color }}>
                      {trendConfluence()?.label ?? 'NO POSITION'}
                    </span>
                  </div>
                  
                  <TrendConfluencePanel confluence={trendConfluence()} />
                </div>
              </div>
            </Show>

            {/* Trail Stages Panel */}
            <div style={cell}>
              <div style={{ 'font-size': '8px', color: C.muted, 'margin-bottom': '8px' }}>TRAIL STAGES</div>
              <StageRail peakId={getStage(peakPct()).id} currentId={getStage(currentPct()).id} />
            </div>

            {/* System Decision Display */}
            <Show when={ld()?.action === 'EXIT'}>
              <div
                style={{
                  ...cell,
                  background: (ld()?.livePnl ?? 0) >= 0 ? '#00FF8812' : '#FF444412',
                  border: '1px solid ' + ((ld()?.livePnl ?? 0) >= 0 ? C.green : C.red)
                }}
                class={isClosing() ? '' : (ld()?.livePnl ?? 0) >= 0 ? 'glow-pulse-green' : 'glow-pulse-red'}
              >
                <div style={{ 'font-size': '9px', color: C.dim }}>WOULD EXIT · {ld()?.reason}</div>
                <div style={{ 'font-size': '20px', 'font-weight': '900', color: (ld()?.livePnl ?? 0) >= 0 ? C.green : C.red }}>
                  {(ld()?.livePnl ?? 0) >= 0 ? '+' : ''}₹{(ld()?.livePnl ?? 0).toFixed(0)}
                </div>
                <div style={{ 'font-size': '7.5px', color: C.dim, 'margin-top': '4px' }}>
                  Dashboard mirror only — backend ExitEngine executes exits.
                </div>
              </div>
            </Show>
          </div>

        </div>
      </Show>
    </div>
  )
}

