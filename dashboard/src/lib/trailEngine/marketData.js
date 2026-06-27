/** Normalize Rails `/api/candles` bars for trail engine consumption. */

const MARKET_OPEN_MINUTES = 9 * 60 + 15

export function istClock(unixSec) {
  const d = new Date(unixSec * 1000)
  const parts = new Intl.DateTimeFormat('en-IN', {
    timeZone: 'Asia/Kolkata',
    hour: 'numeric',
    minute: 'numeric',
    hour12: false
  }).formatToParts(d)

  const hour = Number(parts.find(p => p.type === 'hour')?.value ?? 0)
  const minute = Number(parts.find(p => p.type === 'minute')?.value ?? 0)
  return { hour, minute, minutesSinceOpen: Math.max(0, hour * 60 + minute - MARKET_OPEN_MINUTES) }
}

export function normalizeApiCandles(apiCandles) {
  if (!apiCandles?.length) return []

  return [...apiCandles]
    .sort((a, b) => a.time - b.time)
    .map(bar => {
      const { hour, minute, minutesSinceOpen } = istClock(bar.time)
      return {
        o: bar.open,
        h: bar.high,
        l: bar.low,
        c: bar.close,
        t: bar.time,
        hour,
        minute,
        minutesSinceOpen
      }
    })
}

export function openingRangePoints(candles1m, windowMins = 30) {
  const session = candles1m.filter(c => c.minutesSinceOpen >= 0 && c.minutesSinceOpen < windowMins)
  if (session.length < 2) return 0
  const hi = Math.max(...session.map(c => c.h))
  const lo = Math.min(...session.map(c => c.l))
  return hi - lo
}

export function consecutiveAgainstBars(candles1m, positionDir, lookback = 5) {
  if (!candles1m.length || positionDir === 0) return 0

  const recent = candles1m.slice(-lookback)
  let count = 0
  for (let i = recent.length - 1; i >= 1; i--) {
    const bullish = recent[i].c >= recent[i - 1].c
    const against = positionDir === 1 ? !bullish : bullish
    if (against) count += 1
    else break
  }
  return count
}

export function optionTypeFromSymbol(symbol) {
  const s = (symbol || '').toUpperCase()
  if (s.includes(' PE') || s.endsWith('PE') || s.includes('-PE')) return 'PE'
  return 'CE'
}

export function positionDirFromOption(optionType) {
  return optionType === 'CE' ? 1 : -1
}

export function peakPremiumFromPosition(position, trackedPeak) {
  const entry = Number(position.entry_price) || 0
  const qty = Number(position.quantity) || 1
  const hwmPnl = Number(position.hwm_pnl) || 0
  const hwmPremium = entry + hwmPnl / qty
  const ltp = Number(position.ltp) || entry
  return Math.max(entry, hwmPremium, trackedPeak ?? 0, ltp)
}

export function estimateBidAsk(ltp, vix = 15) {
  const price = Number(ltp) || 0
  const spreadFactor = vix > 18 ? 0.025 : 0.012
  const spread = Math.max(price * spreadFactor, 0.3)
  return { bid: price - spread / 2, ask: price + spread / 2, spread }
}

export function currentIstClock() {
  return istClock(Math.floor(Date.now() / 1000))
}
