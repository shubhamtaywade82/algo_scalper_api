const VALID_COLUMNS = ['strike', 'ltp', 'chg', 'oi', 'choi', 'vol', 'iv', 'delta', 'theta', 'gamma', 'vega']

export function shouldShowColumn(colKey, viewMode) {
  if (colKey === 'strike') return true

  switch (viewMode) {
    case 'LTP':
      return colKey === 'ltp' || colKey === 'chg'
    case 'OI':
      return ['oi', 'choi', 'vol', 'chg', 'ltp'].includes(colKey)
    case 'Greeks':
      return VALID_COLUMNS.includes(colKey)
    default:
      return false
  }
}
