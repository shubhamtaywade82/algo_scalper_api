import { registry } from '@nemesis-oss/pine-ts'

/**
 * Runs a pine-ts registry indicator over candles and returns one {time, value}[] per plot,
 * skipping warm-up bars where the value is undefined/NaN.
 *
 * Candle time stays in unix seconds: pine-ts's time-aware indicators (ta.vwap's daily anchor
 * multiplies `time` by 1000 to build a Date) expect seconds, although `Bar.time` is documented
 * as milliseconds. With milliseconds VWAP reset on almost every bar.
 *
 * @param {string} indicatorId  registry id, e.g. 'sma', 'macd', 'vwap'
 * @param {Array<{time:number,open:number,high:number,low:number,close:number,volume:number}>} candles  time in unix seconds
 * @param {object} inputs  indicator inputs keyed by id, e.g. { length: 20 }
 * @returns {Promise<Record<string, Array<{time:number,value:number}>>>}
 */
export async function runPineIndicator(indicatorId, candles, inputs = {}) {
  const instance = registry.instantiate(indicatorId, inputs)
  if (!instance) throw new Error(`Unknown pine-ts indicator: ${indicatorId}`)

  const plots = {}
  let barIndex = 0
  for await (const row of instance.run(candles)) {
    const time = candles[barIndex].time
    for (const [plotId, value] of Object.entries(row)) {
      if (value === undefined || Number.isNaN(value)) continue
      ;(plots[plotId] ??= []).push({ time, value })
    }
    barIndex++
  }
  return plots
}
