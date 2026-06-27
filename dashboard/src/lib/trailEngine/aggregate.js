/** Fold 1m candles into N-minute OHLC buckets (session-aligned by minutesSinceOpen). */

export function aggregateCandles(candles1m, periodMins) {
  if (!candles1m?.length) return []

  const out = []
  let bucket = null

  for (const bar of candles1m) {
    const bucketIdx = Math.floor(bar.minutesSinceOpen / periodMins)
    if (bucket === null || bucket.idx !== bucketIdx) {
      if (bucket) out.push({ ...bucket })
      bucket = {
        idx: bucketIdx,
        o: bar.o ?? bar.c,
        h: bar.h,
        l: bar.l,
        c: bar.c,
        t: bar.t,
        minutesSinceOpen: bar.minutesSinceOpen
      }
    } else {
      bucket.h = Math.max(bucket.h, bar.h)
      bucket.l = Math.min(bucket.l, bar.l)
      bucket.c = bar.c
    }
  }

  if (bucket) out.push({ ...bucket })
  return out
}

export function candlesToArrays(candles) {
  return {
    highs: candles.map(c => c.h),
    lows: candles.map(c => c.l),
    closes: candles.map(c => c.c)
  }
}
