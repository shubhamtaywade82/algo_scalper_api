import { tvSupertrend, wilderRma } from './supertrend'
import { aggregateCandles } from './aggregate'
import {
  buildMockState,
  computeChopScore,
  computeStop,
  computeStopV3,
  engineDecide,
  getStage
} from './trail'

export function runUnitTests() {
  const results = []

  const test = (name, fn) => {
    try {
      const { pass, detail } = fn()
      results.push({ name, pass, detail })
    } catch (e) {
      results.push({ name, pass: false, detail: e.message })
    }
  }

  test('wilder_rma seeds with SMA of first period bars', () => {
    const vals = [2, 4, 6, 8, 10]
    const rma = wilderRma(vals, 3)
    const seed = rma[2]
    return { pass: Math.abs(seed - 4.0) < 0.001, detail: `seed=${seed?.toFixed(4)} expected=4.0` }
  })

  test('tv_supertrend: persistent uptrend → dir=+1', () => {
    const n = 30
    const highs = Array.from({ length: n }, (_, i) => 100 + i * 2 + 1)
    const lows = Array.from({ length: n }, (_, i) => 100 + i * 2 - 1)
    const closes = Array.from({ length: n }, (_, i) => 100 + i * 2)
    const st = tvSupertrend(highs, lows, closes, 7, 3)
    const lastDir = st.at(-1).dir
    return { pass: lastDir === 1, detail: `last dir=${lastDir}` }
  })

  test('tv_supertrend: persistent downtrend → dir=−1', () => {
    const n = 30
    const highs = Array.from({ length: n }, (_, i) => 200 - i * 2 + 1)
    const lows = Array.from({ length: n }, (_, i) => 200 - i * 2 - 1)
    const closes = Array.from({ length: n }, (_, i) => 200 - i * 2)
    const st = tvSupertrend(highs, lows, closes, 7, 3)
    const lastDir = st.at(-1).dir
    return { pass: lastDir === -1, detail: `last dir=${lastDir}` }
  })

  test('tv_supertrend: flip from up to down on reversal', () => {
    const highs = [...Array.from({ length: 20 }, (_, i) => 100 + i * 2 + 1), ...Array.from({ length: 10 }, (_, i) => 118 - i * 4 + 1)]
    const lows = [...Array.from({ length: 20 }, (_, i) => 100 + i * 2 - 1), ...Array.from({ length: 10 }, (_, i) => 118 - i * 4 - 1)]
    const closes = [...Array.from({ length: 20 }, (_, i) => 100 + i * 2), ...Array.from({ length: 10 }, (_, i) => 118 - i * 4)]
    const st = tvSupertrend(highs, lows, closes, 7, 3)
    const finalDirs = st.slice(-5).map(s => s.dir)
    const flipped = finalDirs.some(d => d === -1)
    return { pass: flipped, detail: `last 5 dirs: [${finalDirs.join(',')}]` }
  })

  test('aggregate_candles: 6×1M → 2×3M bars with correct OHLC', () => {
    const bars = [
      { o: 100, h: 105, l: 99, c: 103, t: 0, minutesSinceOpen: 0 },
      { o: 103, h: 107, l: 102, c: 106, t: 1, minutesSinceOpen: 1 },
      { o: 106, h: 108, l: 104, c: 105, t: 2, minutesSinceOpen: 2 },
      { o: 105, h: 110, l: 103, c: 109, t: 3, minutesSinceOpen: 3 },
      { o: 109, h: 112, l: 107, c: 111, t: 4, minutesSinceOpen: 4 },
      { o: 111, h: 115, l: 110, c: 114, t: 5, minutesSinceOpen: 5 }
    ]
    const agg = aggregateCandles(bars, 3)
    const ok =
      agg.length === 2 &&
      agg[0].h === 108 &&
      agg[0].l === 99 &&
      agg[0].c === 105 &&
      agg[1].h === 115 &&
      agg[1].l === 103 &&
      agg[1].c === 114
    return {
      pass: ok,
      detail: `got ${agg.length} bars. B0: h=${agg[0]?.h} l=${agg[0]?.l} c=${agg[0]?.c}. B1: h=${agg[1]?.h} l=${agg[1]?.l} c=${agg[1]?.c}`
    }
  })

  test('engineDecide: hard stop fires when current < 70% of entry in ENTRY_GUARD', () => {
    const entry = 100
    const peak = 108
    const current = 68
    const stage = getStage(((peak - entry) / entry) * 100)
    const stops = computeStop(entry, peak, current, stage)
    const hardFires = current <= stops.hardStop
    return {
      pass: hardFires && stage.id === 'ENTRY_GUARD',
      detail: `stage=${stage.id} hardStop=${stops.hardStop} current=${current} fires=${hardFires}`
    }
  })

  test('computeStop: ENTRY_GUARD hard stop survives when current near entry after peak', () => {
    const entry = 100
    const peak = 125
    const current = 102
    const peakStage = getStage(((peak - entry) / entry) * 100)
    const priceStage = getStage(((current - entry) / entry) * 100)
    const stops = computeStopV3(entry, peak, current, peakStage, priceStage)
    return {
      pass: stops.hardStopActive === true,
      detail: `peakStage=${peakStage.id} priceStage=${priceStage.id} hardActive=${stops.hardStopActive} hardStop=${stops.hardStop}`
    }
  })

  test('engineDecide: HOLD when current is comfortably above trail', () => {
    const mockState = buildMockState({ entry: 100, peak: 150, current: 145, hour: 10, minute: 30 })
    const dec = engineDecide(mockState)
    return { pass: dec.action === 'HOLD', detail: `action=${dec.action} reason=${dec.reason}` }
  })

  test('engineDecide: TIME_STOP fires at or after 15:20', () => {
    const mockState = buildMockState({ entry: 100, peak: 140, current: 135, hour: 15, minute: 20 })
    const dec = engineDecide(mockState)
    return {
      pass: dec.action === 'EXIT' && dec.reason === 'TIME_STOP',
      detail: `action=${dec.action} reason=${dec.reason}`
    }
  })

  test('computeChopScore: blocks when ADX < 20 and TF misaligned', () => {
    const flat = Array.from({ length: 25 }, (_, i) => ({
      o: 100,
      h: 100.5,
      l: 99.5,
      c: 100 + (i % 3) * 0.1,
      t: i,
      minutesSinceOpen: i
    }))
    const agg5m = aggregateCandles(flat, 5)
    const agg15m = aggregateCandles(flat, 15)
    const result = computeChopScore({
      candles1m: flat,
      candles5m: agg5m,
      candles15m: agg15m,
      vix: 15,
      indexName: 'NIFTY',
      openingRangePts: 30,
      minutesSinceOpen: 10
    })
    return {
      pass: result.score >= 3,
      detail: `score=${result.score} reasons=[${result.reasons.join(' | ')}]`
    }
  })

  return results
}
