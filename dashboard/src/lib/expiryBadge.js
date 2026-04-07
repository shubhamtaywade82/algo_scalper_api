/**
 * @param {object} row — subscribed index row from /api/dashboard (nearest_expiry, days_to_expiry, expiry_today)
 * @returns {{ text: string, sub: string|null, className: string }}
 */
export function expiryBadgeMeta(row) {
  if (!row?.nearest_expiry) {
    return {
      text: 'NO EXPIRY',
      sub: null,
      className: 'text-gray-500 border-gray-600 bg-gray-500/10'
    }
  }
  const days = Number(row.days_to_expiry)
  if (row.expiry_today || days === 0) {
    return {
      text: 'EXPIRY TODAY',
      sub: formatShortDate(row.nearest_expiry),
      className: 'text-amber-200 border-amber-500/50 bg-amber-500/15'
    }
  }
  if (days === 1) {
    return {
      text: '1 DAY',
      sub: formatShortDate(row.nearest_expiry),
      className: 'text-yellow-200 border-yellow-500/40 bg-yellow-500/10'
    }
  }
  return {
    text: `${days} DAYS`,
    sub: formatShortDate(row.nearest_expiry),
    className: 'text-cyan-200/90 border-cyan-500/30 bg-cyan-500/10'
  }
}

function formatShortDate(isoDate) {
  if (!isoDate) return null
  try {
    const d = new Date(isoDate)
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })
  } catch {
    return null
  }
}

export function subscribedRowByKey(rows, indexKey) {
  const k = (indexKey || '').toString().toUpperCase()
  return (rows || []).find((r) => (r.key || '').toUpperCase() === k) || null
}

/** Compact L/S scores + signal ticks from dashboard subscribed_indices.smc_confluence_ltf */
export function confluenceLtfCompact(row) {
  const s = row?.smc_confluence_ltf
  if (!s || typeof s !== 'object') return null
  const parts = []
  if (s.long_score != null) parts.push(`L${s.long_score}`)
  if (s.short_score != null) parts.push(`S${s.short_score}`)
  if (s.long_signal) parts.push('L\u2713')
  if (s.short_signal) parts.push('S\u2713')
  if (parts.length === 0) return null
  return parts.join(' ')
}
