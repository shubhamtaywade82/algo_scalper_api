export function shouldShowColumn(colKey, viewMode) {
  if (colKey === 'strike') return true

  switch (viewMode) {
    case 'LTP':
      return colKey === 'ltp' || colKey === 'chg'
    case 'OI':
      return ['oi', 'choi', 'vol', 'chg', 'ltp'].includes(colKey)
    case 'Greeks':
    default:
      return true
  }
}
