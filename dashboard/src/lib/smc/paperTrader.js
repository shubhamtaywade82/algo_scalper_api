// Paper-trading engine (ported from sdk/dhanhq-charts/src/utils/paperTrader.ts).
// Simulates long-option entries/exits for a scrip; premium quotes fall back to
// an intrinsic+time-value estimate when no quote endpoint is reachable.

export const PAPER_START_EQUITY = 100000
export const DEFAULT_PAPER_SETTINGS = { stopPct: 20, targetPct: 40 }

export function lotSizeForSymbol(symbol) {
  const key = (symbol || '').toUpperCase()
  if (key === 'BANKNIFTY') return 15
  if (key === 'SENSEX') return 10
  return 75
}

export function estimatePremium(spot, strike, optionType) {
  const intrinsic =
    optionType === 'CE' ? Math.max(0, spot - strike) : Math.max(0, strike - spot)
  return Number((intrinsic + strike * 0.005).toFixed(2))
}

export function minutesToISt(ms) {
  const d = new Date(ms)
  return (d.getUTCHours() * 60 + d.getUTCMinutes() + 330) % 1440
}

export const isSessionEndISt = (ms) => minutesToISt(ms) >= 925

export function createPaperAccount(symbol) {
  return {
    symbol,
    cash: PAPER_START_EQUITY,
    open: null,
    closed: [],
    startedAt: Date.now(),
    totalTrades: 0,
    wins: 0
  }
}

export function paperEquity(acc) {
  const openValue = acc.open ? acc.open.lastPremium * acc.open.lotSize : 0
  return acc.cash + openValue
}

export function realizedPnl(acc) {
  return acc.closed.reduce((sum, t) => sum + t.pnl, 0)
}

export function openPaperPosition(acc, opts) {
  if (acc.open || opts.entryPremium <= 0) return acc
  const { stopPct, targetPct } = DEFAULT_PAPER_SETTINGS
  const position = {
    id: `${acc.symbol}-${opts.optionType}-${opts.strike}-${opts.now}`,
    symbol: acc.symbol,
    optionType: opts.optionType,
    strike: opts.strike,
    lotSize: lotSizeForSymbol(acc.symbol),
    entryTime: opts.now,
    entryPremium: opts.entryPremium,
    stopPremium: Number((opts.entryPremium * (1 - stopPct / 100)).toFixed(2)),
    targetPremium: Number((opts.entryPremium * (1 + targetPct / 100)).toFixed(2)),
    estimatedEntry: opts.estimatedEntry,
    lastPremium: opts.entryPremium,
    lastTime: opts.now,
    maePct: 0,
    mfePct: 0
  }
  return { ...acc, cash: Number((acc.cash - opts.entryPremium * position.lotSize).toFixed(2)), open: position }
}

export function closePaperPosition(acc, premium, now, reason) {
  if (!acc.open) return { acc, trade: null }
  const open = acc.open
  const pnl = (premium - open.entryPremium) * open.lotSize
  const trade = {
    ...open,
    exitTime: now,
    exitPremium: premium,
    exitReason: reason,
    pnl: Number(pnl.toFixed(2)),
    returnPct: Number((((premium - open.entryPremium) / open.entryPremium) * 100).toFixed(2))
  }
  return {
    acc: {
      ...acc,
      cash: Number((acc.cash + premium * open.lotSize).toFixed(2)),
      open: null,
      closed: [...acc.closed, trade],
      totalTrades: acc.totalTrades + 1,
      wins: acc.wins + (pnl > 0 ? 1 : 0)
    },
    trade
  }
}

export function markPaperPosition(acc, premium, now) {
  if (!acc.open || premium <= 0) return { acc, trade: null }
  const open = acc.open
  const returnPct = ((premium - open.entryPremium) / open.entryPremium) * 100
  const updated = {
    ...open,
    lastPremium: premium,
    lastTime: now,
    maePct: Number(Math.min(open.maePct, returnPct).toFixed(2)),
    mfePct: Number(Math.max(open.mfePct, returnPct).toFixed(2))
  }
  if (premium <= updated.stopPremium) {
    return closePaperPosition({ ...acc, open: updated }, premium, now, 'STOP')
  }
  if (premium >= updated.targetPremium) {
    return closePaperPosition({ ...acc, open: updated }, premium, now, 'TARGET')
  }
  return { acc: { ...acc, open: updated }, trade: null }
}

export function loadPaperAccount(symbol) {
  try {
    const raw = localStorage.getItem(`dhan_paper_${symbol.toLowerCase()}`)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

export function savePaperAccount(acc) {
  try {
    localStorage.setItem(`dhan_paper_${acc.symbol.toLowerCase()}`, JSON.stringify(acc))
  } catch {}
}

export function resetPaperAccount(symbol) {
  try {
    localStorage.removeItem(`dhan_paper_${symbol.toLowerCase()}`)
  } catch {}
  return createPaperAccount(symbol)
}

export async function fetchPaperQuote(symbol, strike, optionType, spot) {
  try {
    const res = await fetch(`/api/paper/quote?symbol=${encodeURIComponent(symbol)}&strike=${strike}&optionType=${optionType}`)
    const json = await res.json()
    if (json && json.premium > 0) return { premium: Number(json.premium), estimated: false }
  } catch {}
  return { premium: estimatePremium(spot, strike, optionType), estimated: true }
}
