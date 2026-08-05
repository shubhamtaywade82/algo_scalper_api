// CE/PE setup scanner (ported from sdk/dhanhq-charts/src/utils/setupScanner.ts).
// Combines SMC + ICT detector outputs into a directional bias and a long-options
// strike recommendation.

export function strikeIntervalForSymbol(symbol) {
  const key = (symbol || '').toLowerCase()
  if (key === 'banknifty' || key === 'sensex') return 100
  if (key === 'reliance' || key === 'tcs') return 20
  if (key === 'hdfcbank' || key === 'infy') return 10
  return 50
}

export function resampleCandles(candles, barSeconds) {
  const out = []
  let current = null
  let currentKey = -1

  for (const c of candles) {
    const key = Math.floor(c.time / barSeconds) * barSeconds
    if (current === null || key !== currentKey) {
      if (current) out.push(current)
      current = { time: key, open: c.open, high: c.high, low: c.low, close: c.close, volume: c.volume ?? 0 }
      currentKey = key
    } else {
      current.high = Math.max(current.high, c.high)
      current.low = Math.min(current.low, c.low)
      current.close = c.close
      current.volume = (current.volume ?? 0) + (c.volume ?? 0)
    }
  }
  if (current) out.push(current)
  return out
}

const RECENT_WINDOW = 6 * 3600

const voteFromStructure = (breaks) => {
  const last = [...breaks.slice(-6)].reverse().find((b) => b.category === 'MAJOR') ?? breaks[breaks.length - 1]
  if (!last) return { name: 'Market Structure', vote: 'neutral', detail: 'Insufficient data' }
  const bull = last.type.startsWith('BULLISH')
  return {
    name: 'Market Structure',
    vote: bull ? 'bullish' : 'bearish',
    detail: `Last ${last.category === 'MAJOR' ? 'MAJOR' : 'INTERNAL'} ${last.type.slice(0, -3)}`
  }
}

const voteFromAMD = (cycles) => {
  const last = cycles[cycles.length - 1]
  if (!last) return { name: 'AMD Power of 3', vote: 'neutral', detail: 'No cycle detected' }
  const bull = last.trend === 'BULLISH'
  return {
    name: 'AMD Power of 3',
    vote: bull ? 'bullish' : 'bearish',
    detail: bull ? 'Last cycle A→M→D bullish' : 'Last cycle A→M→D bearish'
  }
}

const voteFromSweep = (pools, judas, now) => {
  const recentSwept = pools.filter((p) => p.swept && p.sweepTime && now - p.sweepTime < RECENT_WINDOW)
  if (recentSwept.length > 0) {
    const last = recentSwept.reduce((a, b) => ((b.sweepTime ?? 0) > (a.sweepTime ?? 0) ? b : a))
    const bull = last.type === 'BSL'
    return {
      name: 'Liquidity Sweep',
      vote: bull ? 'bullish' : 'bearish',
      detail: `${bull ? 'BSL' : 'SSL'} swept ${bull ? 'above' : 'below'} (stop run done)`
    }
  }
  const lastJudas = judas[judas.length - 1]
  if (lastJudas && now - lastJudas.candleTime < RECENT_WINDOW) {
    const bull = lastJudas.type === 'BULLISH_JUDAS'
    return {
      name: 'Judas Swing',
      vote: bull ? 'bullish' : 'bearish',
      detail: `${bull ? 'Bullish' : 'Bearish'} Judas fakeout trap`
    }
  }
  return { name: 'Liquidity Sweep', vote: 'neutral', detail: 'No recent sweep — waiting for stop run' }
}

const kzTiming = (sessions, sb, now, bias) => {
  const inKZ = sessions.some((s) => s.type !== 'ASIA' && now >= s.startTime && now <= s.endTime + 900)
  const inSB = sb.some((w) => now >= w.startTime && now <= w.endTime + 900)
  const active = bias !== 'neutral' && (inKZ || inSB)
  return {
    name: 'KZ / Silver Bullet',
    vote: active ? bias : 'neutral',
    detail: inSB ? 'Inside Silver Bullet window' : inKZ ? 'Inside London/NY Kill Zone' : 'Outside KZ & SB windows',
    aligned: active
  }
}

const oteEntry = (ote, price, bias) => {
  if (!ote) return { name: 'OTE Zone', vote: 'neutral', detail: 'No OTE zone detected', aligned: false }
  const lo = Math.min(ote.fib618, ote.fib790)
  const hi = Math.max(ote.fib618, ote.fib790)
  const inside = price >= lo && price <= hi
  const active = bias !== 'neutral' && inside
  return {
    name: 'OTE Zone',
    vote: active ? bias : 'neutral',
    detail: inside ? `Price inside OTE ${lo.toFixed(2)}–${hi.toFixed(2)}` : `Price outside OTE ${lo.toFixed(2)}–${hi.toFixed(2)}`,
    aligned: active
  }
}

const premiumDiscount = (pd, price, bias) => {
  if (!pd) return { name: 'Premium/Discount', vote: 'neutral', detail: 'No swing range', aligned: false }
  const inDiscount = price < pd.equilibrium
  const inPremium = price > pd.equilibrium
  const active = bias !== 'neutral' && (bias === 'bullish' ? inDiscount : inPremium)
  return {
    name: 'Premium/Discount',
    vote: active ? bias : 'neutral',
    detail: `${inDiscount ? 'Discount' : 'Premium'} zone (EQ ${pd.equilibrium.toFixed(2)})`,
    aligned: active
  }
}

const zoneConfluence = (input, bias) => {
  if (bias === 'neutral') {
    return { name: 'OB / FVG / S&D', vote: 'neutral', detail: 'No bias — zone check skipped', aligned: false }
  }
  const zones = [
    ...input.ob.map((o) => ({ bull: o.type === 'BULLISH_OB', top: o.top, bottom: o.bottom })),
    ...input.fvg.map((f) => ({ bull: f.type === 'BULLISH', top: f.top, bottom: f.bottom })),
    ...input.sd.map((z) => ({ bull: z.type === 'DEMAND', top: z.top, bottom: z.bottom }))
  ]
  const matches = zones.filter((z) =>
    bias === 'bullish' ? z.bull && z.bottom < input.lastPrice : !z.bull && z.top > input.lastPrice
  )
  if (matches.length === 0) {
    return {
      name: 'OB / FVG / S&D',
      vote: 'neutral',
      detail: `No ${bias === 'bullish' ? 'demand' : 'supply'} zone ${bias === 'bullish' ? 'below' : 'above'} price`,
      aligned: false
    }
  }
  const nearest = matches.sort((a, b) => (bias === 'bullish' ? b.bottom - a.bottom : a.top - b.top))[0]
  const ref = bias === 'bullish' ? nearest.bottom : nearest.top
  return {
    name: 'OB / FVG / S&D',
    vote: bias,
    detail: `${bias === 'bullish' ? 'Demand' : 'Supply'} zone at ${ref.toFixed(2)}`,
    aligned: true
  }
}

const trendlineConf = (tl, price, bias) => {
  if (bias === 'neutral') {
    return { name: 'Trendline', vote: 'neutral', detail: 'No bias — trendline check skipped', aligned: false }
  }
  const active = tl.filter((t) => t.status === 'ACTIVE')
  if (bias === 'bullish') {
    const sup = active.filter((t) => t.type === 'SUPPORT' && t.p2Price <= price).sort((a, b) => b.p2Price - a.p2Price)[0]
    return sup
      ? { name: 'Trendline', vote: 'bullish', detail: `Active support ×${sup.touchCount} below price`, aligned: true }
      : { name: 'Trendline', vote: 'neutral', detail: 'No active support below price', aligned: false }
  }
  const res = active.filter((t) => t.type === 'RESISTANCE' && t.p2Price >= price).sort((a, b) => a.p2Price - b.p2Price)[0]
  return res
    ? { name: 'Trendline', vote: 'bearish', detail: `Active resistance ×${res.touchCount} above price`, aligned: true }
    : { name: 'Trendline', vote: 'neutral', detail: 'No active resistance above price', aligned: false }
}

const patternConf = (cp, bias) => {
  const last = cp[cp.length - 1]
  if (!last) return { name: 'Candle Pattern', vote: 'neutral', detail: 'No recent pattern', aligned: false }
  const bull = last.type.startsWith('BULLISH') || last.type === 'INSIDE_BAR_BULL'
  const active = bias !== 'neutral' && bull === (bias === 'bullish')
  return {
    name: 'Candle Pattern',
    vote: active ? bias : 'neutral',
    detail: `Last: ${last.type}${last.strength === 'STRONG' ? ' (strong)' : ''}`,
    aligned: active
  }
}

const longNotes = (input, price, side) => {
  if (side === 'CE') {
    const sweep = input.liquidity.filter((p) => p.type === 'BSL' && p.swept).sort((a, b) => (b.sweepTime ?? 0) - (a.sweepTime ?? 0))[0]
    const demand = input.ob.filter((o) => o.type === 'BULLISH_OB' && !o.mitigated).sort((a, b) => b.bottom - a.bottom)[0]
    const target = input.liquidity.filter((p) => p.type === 'BSL' && !p.swept && p.level > price).sort((a, b) => a.level - b.level)[0]
    return [
      `Buy CE on retrace into demand OB/FVG${demand ? ` (stop below ${demand.bottom.toFixed(2)})` : ''}${sweep ? ` — BSL swept at ${sweep.level.toFixed(2)}` : ''}`,
      target ? `Target: next untapped BSL at ${target.level.toFixed(2)}` : 'Target: nearest untapped BSL above'
    ]
  }
  const sweep = input.liquidity.filter((p) => p.type === 'SSL' && p.swept).sort((a, b) => (b.sweepTime ?? 0) - (a.sweepTime ?? 0))[0]
  const supply = input.ob.filter((o) => o.type === 'BEARISH_OB' && !o.mitigated).sort((a, b) => a.top - b.top)[0]
  const target = input.liquidity.filter((p) => p.type === 'SSL' && !p.swept && p.level < price).sort((a, b) => b.level - a.level)[0]
  return [
    `Buy PE on retrace into supply OB/FVG${supply ? ` (stop above ${supply.top.toFixed(2)})` : ''}${sweep ? ` — SSL swept at ${sweep.level.toFixed(2)}` : ''}`,
    target ? `Target: next untapped SSL at ${target.level.toFixed(2)}` : 'Target: nearest untapped SSL below'
  ]
}

const pick = (htf, ltf) => {
  if (htf && htf.vote !== 'neutral') return htf
  return ltf
}

const ATM = { label: 'ATM', rationale: 'Most liquid — delta ~0.5, tightest spread' }
const OTM1 = { label: 'OTM 1', rationale: 'Cheaper premium — delta ~0.35, best risk/reward' }
const OTM2 = { label: 'OTM 2', rationale: 'Cheapest premium — max leverage, needs strong momentum' }

export function recommendStrikes(price, direction, alignedCount, strikeInterval, symbol) {
  if (direction === 'NO_TRADE') return undefined
  const optionType = direction === 'CE_LONG' ? 'CE' : 'PE'
  const atm = Math.round(price / strikeInterval) * strikeInterval
  const dir = optionType === 'CE' ? 1 : -1
  const primaryOffset = alignedCount >= 5 ? 2 : 1
  const altOffset = primaryOffset === 2 ? 1 : 2
  const [primaryMeta, altMeta] = primaryOffset === 2 ? [OTM2, OTM1] : [OTM1, OTM2]
  return {
    instrument: (symbol || 'OPTION').toUpperCase(),
    optionType,
    primary: {
      strike: atm + primaryOffset * dir * strikeInterval,
      label: primaryMeta.label,
      rationale: primaryMeta.rationale
    },
    alternates: [
      { strike: atm, label: ATM.label, rationale: ATM.rationale },
      {
        strike: atm + altOffset * dir * strikeInterval,
        label: altMeta.label,
        rationale: altMeta.rationale
      }
    ]
  }
}

export function scanSetups(input) {
  const now = Math.floor(Date.now() / 1000)
  const price = input.lastPrice

  const htf = input.htf
  const htfFactors = htf
    ? [
        { ...voteFromStructure(htf.structure), tf: htf.tfLabel },
        { ...voteFromAMD(htf.amd), tf: htf.tfLabel },
        { ...voteFromSweep(htf.liquidity, htf.judas, now), tf: htf.tfLabel }
      ]
    : []

  const biasFactors = [
    pick(htfFactors[0], voteFromStructure(input.structure)),
    pick(htfFactors[1], voteFromAMD(input.amd)),
    pick(htfFactors[2], voteFromSweep(input.liquidity, input.judas, now))
  ]
  const bulls = biasFactors.filter((f) => f.vote === 'bullish').length
  const bears = biasFactors.filter((f) => f.vote === 'bearish').length
  const bias = bulls > bears ? 'bullish' : bears > bulls ? 'bearish' : 'neutral'
  const biasTf = biasFactors.find((f) => f.tf)?.tf

  const confluence = [
    kzTiming(input.sessions, input.sb, now, bias),
    oteEntry(input.ote, price, bias),
    premiumDiscount(input.pd, price, bias),
    zoneConfluence(input, bias),
    trendlineConf(input.tl, price, bias),
    patternConf(input.cp, bias)
  ]
  const alignedCount = confluence.filter((f) => f.aligned).length

  let direction = 'NO_TRADE'
  const notes = []
  if (bias === 'bullish' && bulls >= 2 && alignedCount >= 3) {
    direction = 'CE_LONG'
    notes.push(...longNotes(input, price, 'CE'))
  } else if (bias === 'bearish' && bears >= 2 && alignedCount >= 3) {
    direction = 'PE_LONG'
    notes.push(...longNotes(input, price, 'PE'))
  } else {
    if (bias === 'neutral') notes.push('Bias undecided — need 2/3 of structure, AMD, sweep agreement')
    if (alignedCount < 3) notes.push(`Only ${alignedCount}/6 confluence points aligned — waiting for more`)
  }

  return {
    direction,
    bias,
    biasFactors,
    confluence,
    alignedCount,
    biasTf,
    recommendedStrikes: recommendStrikes(price, direction, alignedCount, input.strikeInterval ?? 50, input.symbol ?? ''),
    notes
  }
}
