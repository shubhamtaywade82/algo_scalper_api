// Lot calculation and formatting helper for Indian market instruments (NSE / BSE)

export function getLotSize(symbol = '') {
  if (!symbol) return 1
  const sym = String(symbol).toUpperCase()

  if (sym.includes('BANKNIFTY')) return 15
  if (sym.includes('NIFTY') && !sym.includes('MIDCP')) return 25
  if (sym.includes('FINNIFTY')) return 25
  if (sym.includes('MIDCPNIFTY') || sym.includes('MIDCP')) return 50
  if (sym.includes('SENSEX')) return 10
  if (sym.includes('BANKEX')) return 15

  return 1
}

export function getLotInfo(symbol = '', quantity = 0) {
  const qty = Math.abs(Number(quantity) || 0)
  const lotSize = getLotSize(symbol)
  if (!qty) return { qty: 0, lots: 0, lotSize, hasLots: lotSize > 1 }

  const rawLots = qty / lotSize
  const lots = Math.round(rawLots * 100) / 100
  const hasLots = lotSize > 1

  return {
    qty,
    lots,
    lotSize,
    hasLots
  }
}

export function formatQtyLots(symbol = '', quantity = 0) {
  const info = getLotInfo(symbol, quantity)
  if (!info.hasLots) return `${info.qty}`
  const lotLabel = info.lots === 1 ? 'Lot' : 'Lots'
  return `${info.qty} (${info.lots} ${lotLabel})`
}
