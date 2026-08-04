import { tvSupertrend } from './supertrend'

export const TRAIL_STAGES = [
  { id: 'ENTRY_GUARD', label: 'Entry Guard', range: [0, 20], trailPct: 40, hardStopPct: 30, color: '#FF4444', icon: '🛡' },
  { id: 'MOMENTUM_RIDE', label: 'Momentum Ride', range: [20, 60], trailPct: 35, hardStopPct: null, color: '#F0A500', icon: '🚀' },
  { id: 'PROFIT_LOCK', label: 'Profit Lock', range: [60, 120], trailPct: 28, hardStopPct: null, color: '#00CFFF', icon: '🔒' },
  { id: 'RUNNER_MODE', label: 'Runner Mode', range: [120, Infinity], trailPct: 22, hardStopPct: null, color: '#00FF88', icon: '⚡' }
]

export const CHOP_WEIGHTS = {
  adx: { weight: 3 },
  tfMismatch: { weight: 3 },
  stFlips: { weight: 2 },
  bbWidth: { weight: 1 },
  openRange: { weight: 1 },
  vixHigh: { weight: 1 },
  vixLow: { weight: 1 }
}

export const CHOP_MAX_SCORE = Object.values(CHOP_WEIGHTS).reduce((sum, w) => sum + w.weight, 0)

export function getStage(profitPct) {
  return TRAIL_STAGES.find(s => profitPct >= s.range[0] && profitPct < s.range[1]) ?? TRAIL_STAGES.at(-1)
}

/** Legacy stop — used by unit test T6. */
export function computeStop(entry, peak, current, stage) {
  const peakProfit = Math.max(peak - entry, 0)
  const trailStop = peakProfit > 0 ? peak - (stage.trailPct / 100) * peakProfit : entry
  const hardStop = stage.hardStopPct ? entry * (1 - stage.hardStopPct / 100) : null
  const effectiveStop = hardStop != null ? Math.max(trailStop, hardStop) : trailStop
  return { trailStop, hardStop, effectiveStop, hardStopActive: hardStop != null }
}

/** Hard stop follows CURRENT price stage, not peak stage. */
export function computeStopV3(entry, peak, current, peakStage, currentPriceStage) {
  const peakProfit = Math.max(peak - entry, 0)
  const trailStop = peakProfit > 0 ? peak - (peakStage.trailPct / 100) * peakProfit : entry

  const currentProfitPct = entry > 0 ? ((current - entry) / entry) * 100 : 0
  const hardStopActive = currentProfitPct < 20 && entry > 0
  const hardPct = currentPriceStage.hardStopPct ?? 30
  const hardStop = hardStopActive ? entry * (1 - hardPct / 100) : null
  const effectiveStop = hardStopActive && hardStop != null ? Math.max(trailStop, hardStop) : trailStop

  return { trailStop, hardStop, effectiveStop, hardStopActive }
}

function simpleAdx(candles, period = 14) {
  if (!candles?.length || candles.length < period + 2) return 50

  const tr = []
  const dmp = []
  const dmm = []

  for (let i = 1; i < candles.length; i++) {
    const up = candles[i].h - candles[i - 1].h
    const down = candles[i - 1].l - candles[i].l
    tr.push(Math.max(candles[i].h - candles[i].l, Math.abs(candles[i].h - candles[i - 1].c), Math.abs(candles[i].l - candles[i - 1].c)))
    dmp.push(up > down && up > 0 ? up : 0)
    dmm.push(down > up && down > 0 ? down : 0)
  }

  const rmaTr = wilderRmaInline(tr, period)
  const rmaDmp = wilderRmaInline(dmp, period)
  const rmaDmm = wilderRmaInline(dmm, period)

  const dx = rmaTr.map((atr, i) => {
    if (!atr || atr === 0) return 0
    const dip = (rmaDmp[i] / atr) * 100
    const dim = (rmaDmm[i] / atr) * 100
    const s = dip + dim
    return s > 0 ? (Math.abs(dip - dim) / s) * 100 : 0
  }).filter(v => v > 0)

  if (!dx.length) return 50
  const slice = dx.slice(-period)
  return slice.reduce((a, b) => a + b, 0) / slice.length
}

function wilderRmaInline(values, period) {
  const out = new Array(values.length).fill(null)
  if (values.length < period) return out
  let seed = 0
  for (let i = 0; i < period; i++) seed += values[i]
  seed /= period
  out[period - 1] = seed
  const alpha = 1 / period
  for (let i = period; i < values.length; i++) {
    out[i] = alpha * values[i] + (1 - alpha) * out[i - 1]
  }
  return out
}

function bbWidth(candles, period = 20) {
  const cl = candles.map(c => c.c)
  if (cl.length < period) return 1
  const slice = cl.slice(-period)
  const mean = slice.reduce((a, b) => a + b, 0) / period
  const sd = Math.sqrt(slice.reduce((a, b) => a + (b - mean) ** 2, 0) / period)
  return mean > 0 ? (4 * sd) / mean : 1
}

export function computeChopScore({
  candles1m,
  candles5m,
  candles15m,
  vix,
  indexName,
  openingRangePts,
  minutesSinceOpen
}) {
  let score = 0
  const reasons = []

  const adxVal = simpleAdx(candles5m, 14)
  const adxFail = adxVal < 20
  if (adxFail) {
    score += CHOP_WEIGHTS.adx.weight
    reasons.push(`ADX ${adxVal.toFixed(1)} < 20 (5M)`)
  }

  const st1m = tvSupertrend(candles1m.map(c => c.h), candles1m.map(c => c.l), candles1m.map(c => c.c))
  const st5m = tvSupertrend(candles5m.map(c => c.h), candles5m.map(c => c.l), candles5m.map(c => c.c))
  const st15m = tvSupertrend(candles15m.map(c => c.h), candles15m.map(c => c.l), candles15m.map(c => c.c))

  const d1 = st1m.at(-1)?.dir ?? 0
  const d5 = st5m.at(-1)?.dir ?? 0
  const d15 = st15m.at(-1)?.dir ?? 0
  const tfFail = !(d1 === d5 && d5 === d15 && d1 !== 0)
  if (tfFail) {
    score += CHOP_WEIGHTS.tfMismatch.weight
    reasons.push(`TF mismatch 1M=${d1 === 1 ? '↑' : '↓'} 5M=${d5 === 1 ? '↑' : '↓'} 15M=${d15 === 1 ? '↑' : '↓'}`)
  }

  const recent15 = st1m.slice(-15)
  let flips = 0
  for (let i = 1; i < recent15.length; i++) {
    if (recent15[i].dir !== recent15[i - 1].dir) flips += 1
  }
  if (flips >= 3) {
    score += CHOP_WEIGHTS.stFlips.weight
    reasons.push(`ST flipped ${flips}× in last 15 1M bars`)
  }

  const bbw = bbWidth(candles5m)
  if (bbw < 0.005) {
    score += CHOP_WEIGHTS.bbWidth.weight
    reasons.push(`BB width ${(bbw * 100).toFixed(2)}% < 0.5%`)
  }

  const orLimit = indexName === 'SENSEX' ? 150 : 50
  if (minutesSinceOpen < 30 && openingRangePts < orLimit) {
    score += CHOP_WEIGHTS.openRange.weight
    reasons.push(`OR ${openingRangePts.toFixed(0)}pts < ${orLimit}`)
  }

  if (vix != null && vix > 22) {
    score += CHOP_WEIGHTS.vixHigh.weight
    reasons.push(`VIX ${vix.toFixed(1)} > 22`)
  }
  if (vix != null && vix < 12) {
    score += CHOP_WEIGHTS.vixLow.weight
    reasons.push(`VIX ${vix.toFixed(1)} < 12`)
  }

  const blocked = score >= 5
  const borderline = score >= 3 && score < 5

  return {
    score,
    maxScore: CHOP_MAX_SCORE,
    blocked,
    borderline,
    reasons,
    adxVal,
    adxFail,
    tfFail,
    flips,
    bbw,
    d1,
    d5,
    d15
  }
}

export function detectExhaustion({ candles1m, positionDir, currentHour, currentMinute, consecutiveAgainst }) {
  const triggers = []
  const stWarmup = 9

  if (candles1m.length >= stWarmup) {
    const st = tvSupertrend(candles1m.map(c => c.h), candles1m.map(c => c.l), candles1m.map(c => c.c))
    const stDir = st.at(-1)?.dir ?? 0
    if (stDir !== 0 && stDir !== positionDir) {
      triggers.push({ key: 'SUPERTREND_FLIP', label: '1M Supertrend flipped', critical: true })
    }
  }

  if (consecutiveAgainst >= 3) {
    triggers.push({
      key: 'REVERSAL_CANDLES',
      label: `${consecutiveAgainst} consecutive contra candles`,
      critical: false
    })
  }

  if (currentHour > 15 || (currentHour === 15 && currentMinute >= 20)) {
    triggers.push({ key: 'TIME_STOP', label: 'Past 3:20 PM — STT trap exit', critical: true })
  }

  return { triggers, hardExit: triggers.some(t => t.critical) }
}

export function modelExecution({ stopPrice, bid, ask }) {
  const spread = Math.max(ask - bid, 0.05)
  const midpoint = (bid + ask) / 2
  const spreadPct = midpoint > 0 ? (spread / midpoint) * 100 : 0

  let regime
  let slippageMult
  if (spreadPct < 0.8) {
    regime = 'NORMAL'
    slippageMult = 0.3
  } else if (spreadPct < 1.5) {
    regime = 'FAST'
    slippageMult = 0.6
  } else if (spreadPct < 3.0) {
    regime = 'PANIC'
    slippageMult = 1.2
  } else {
    regime = 'CIRCUIT'
    slippageMult = 2.5
  }

  const slippage = spread * slippageMult
  const expectedFill = parseFloat((stopPrice - slippage).toFixed(2))
  const warning = regime !== 'NORMAL' ? `${regime} market — fill ₹${expectedFill}` : null

  return {
    expectedFill,
    slippage: parseFloat(slippage.toFixed(2)),
    spreadPct: parseFloat(spreadPct.toFixed(2)),
    regime,
    warning
  }
}

export function engineDecide(state) {
  const {
    entry,
    peak,
    bid,
    ask,
    lastPrice,
    positionDir,
    candles1m,
    currentHour,
    currentMinute,
    consecutiveAgainst,
    lotSize
  } = state

  const peakProfitPct = entry > 0 ? ((peak - entry) / entry) * 100 : 0
  const currentProfitPct = entry > 0 ? ((lastPrice - entry) / entry) * 100 : 0
  const peakStage = getStage(peakProfitPct)
  const currentStage = getStage(currentProfitPct)
  const stops = computeStopV3(entry, peak, lastPrice, peakStage, currentStage)
  const exhaustion = detectExhaustion({
    candles1m,
    positionDir,
    currentHour,
    currentMinute,
    consecutiveAgainst
  })
  const execution = modelExecution({ stopPrice: stops.effectiveStop, bid, ask })
  const livePnl = (execution.expectedFill - entry) * lotSize
  const peakPnl = (peak - entry) * lotSize

  if (exhaustion.triggers.find(t => t.key === 'TIME_STOP')) {
    return {
      action: 'EXIT',
      reason: 'TIME_STOP',
      source: 'EXHAUSTION_OVERRIDE',
      stops,
      execution,
      exhaustion,
      livePnl,
      peakPnl,
      peakStage,
      currentStage
    }
  }

  if (exhaustion.triggers.find(t => t.key === 'SUPERTREND_FLIP')) {
    return {
      action: 'EXIT',
      reason: 'SUPERTREND_FLIP',
      source: 'EXHAUSTION_OVERRIDE',
      stops,
      execution,
      exhaustion,
      livePnl,
      peakPnl,
      peakStage,
      currentStage
    }
  }

  if (stops.hardStopActive && lastPrice <= stops.hardStop) {
    return {
      action: 'EXIT',
      reason: 'HARD_STOP',
      source: 'RISK',
      stops,
      execution,
      exhaustion,
      livePnl,
      peakPnl,
      peakStage,
      currentStage
    }
  }

  if (lastPrice <= stops.effectiveStop) {
    return {
      action: 'EXIT',
      reason: 'TRAIL_STOP',
      source: 'TRAIL',
      stops,
      execution,
      exhaustion,
      livePnl,
      peakPnl,
      peakStage,
      currentStage
    }
  }

  if (exhaustion.triggers.find(t => t.key === 'REVERSAL_CANDLES')) {
    return {
      action: 'WARN',
      reason: 'REVERSAL_CANDLES',
      source: 'EXHAUSTION_WATCH',
      stops,
      execution,
      exhaustion,
      livePnl,
      peakPnl,
      peakStage,
      currentStage
    }
  }

  return {
    action: 'HOLD',
    reason: 'TRAIL_ACTIVE',
    source: 'ENGINE',
    stops,
    execution,
    exhaustion,
    livePnl,
    peakPnl,
    peakStage,
    currentStage
  }
}

export function buildMockState({ entry, peak, current, hour, minute }) {
  const n = 20
  const upward = Array.from({ length: n }, (_, i) => ({
    h: entry + i * 2 + 1,
    l: entry + i * 2 - 1,
    c: entry + i * 2,
    o: entry + i * 2,
    t: i,
    minutesSinceOpen: i
  }))

  return {
    entry,
    peak,
    bid: current - 0.5,
    ask: current + 0.5,
    lastPrice: current,
    positionDir: 1,
    candles1m: upward,
    vix: 15,
    indexName: 'NIFTY',
    openingRangePts: 80,
    minutesSinceOpen: 45,
    currentHour: hour,
    currentMinute: minute,
    consecutiveAgainst: 0,
    lotSize: 50
  }
}
