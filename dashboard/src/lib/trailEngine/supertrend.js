/** TV-exact Supertrend — Wilder RMA ATR, Pine band clamping, active-band flip only. */

export function wilderRma(values, period) {
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

export function tvSupertrend(highs, lows, closes, period = 7, mult = 3.0) {
  const n = closes.length
  if (n < 2) {
    return closes.map(() => ({ dir: 0, value: null, upper: null, lower: null }))
  }

  const tr = new Array(n).fill(0)
  tr[0] = highs[0] - lows[0]
  for (let i = 1; i < n; i++) {
    tr[i] = Math.max(
      highs[i] - lows[i],
      Math.abs(highs[i] - closes[i - 1]),
      Math.abs(lows[i] - closes[i - 1])
    )
  }

  const atr = wilderRma(tr, period)
  const result = new Array(n).fill(null).map(() => ({ dir: 0, value: null, upper: null, lower: null }))

  let prevUpper = null
  let prevLower = null
  let prevDir = 1

  for (let i = 0; i < n; i++) {
    if (atr[i] === null) continue

    const hl2 = (highs[i] + lows[i]) / 2
    const rawUpper = hl2 + mult * atr[i]
    const rawLower = hl2 - mult * atr[i]

    let upper
    let lower
    if (prevUpper === null) {
      upper = rawUpper
      lower = rawLower
    } else {
      upper = rawUpper < prevUpper || closes[i - 1] > prevUpper ? rawUpper : prevUpper
      lower = rawLower > prevLower || closes[i - 1] < prevLower ? rawLower : prevLower
    }

    let dir
    if (i === 0) {
      dir = closes[i] > upper ? 1 : -1
    } else if (prevDir === -1 && closes[i] > prevUpper) {
      dir = 1
    } else if (prevDir === 1 && closes[i] < prevLower) {
      dir = -1
    } else {
      dir = prevDir
    }

    const value = dir === 1 ? lower : upper
    result[i] = { dir, value, upper, lower, atr: atr[i] }
    prevUpper = upper
    prevLower = lower
    prevDir = dir
  }

  return result
}
