// SMC detection engine (ported from sdk/dhanhq-charts/src/utils/smcEngine.ts).
// Pure functions over candle arrays { time, open, high, low, close, volume? }.

export function detectFVGs(candles, minGapPct = 0.03) {
  if (!candles || candles.length < 3) return []

  const fvgs = []

  for (let i = 2; i < candles.length; i++) {
    const c1 = candles[i - 2]
    const c3 = candles[i]

    if (c3.low > c1.high) {
      const top = c3.low
      const bottom = c1.high
      const gapPct = ((top - bottom) / bottom) * 100

      if (gapPct >= minGapPct) {
        let mitigated = false
        let mitigatedTime

        for (let j = i + 1; j < candles.length; j++) {
          if (candles[j].low <= bottom) {
            mitigated = true
            mitigatedTime = candles[j].time
            break
          }
        }

        fvgs.push({
          id: `fvg-bull-${c1.time}-${i}`,
          type: 'BULLISH',
          startTime: c1.time,
          endTime: mitigatedTime || candles[candles.length - 1].time,
          top,
          bottom,
          mitigated,
          mitigatedTime
        })
      }
    } else if (c3.high < c1.low) {
      const top = c1.low
      const bottom = c3.high
      const gapPct = ((top - bottom) / bottom) * 100

      if (gapPct >= minGapPct) {
        let mitigated = false
        let mitigatedTime

        for (let j = i + 1; j < candles.length; j++) {
          if (candles[j].high >= top) {
            mitigated = true
            mitigatedTime = candles[j].time
            break
          }
        }

        fvgs.push({
          id: `fvg-bear-${c1.time}-${i}`,
          type: 'BEARISH',
          startTime: c1.time,
          endTime: mitigatedTime || candles[candles.length - 1].time,
          top,
          bottom,
          mitigated,
          mitigatedTime
        })
      }
    }
  }

  return fvgs
}

export function detectOrderBlocks(candles, minImpulseMult = 1.5) {
  if (!candles || candles.length < 5) return []

  const obs = []
  const recentSlice = candles.slice(-50)
  const avgRange = recentSlice.reduce((sum, c) => sum + (c.high - c.low), 0) / recentSlice.length

  for (let i = 1; i < candles.length - 2; i++) {
    const prevCandle = candles[i]
    const next1 = candles[i + 1]
    const next2 = candles[i + 2]

    const isBearishPrev = prevCandle.close < prevCandle.open
    const isBullishPrev = prevCandle.close > prevCandle.open

    const bullImpulse = (next1.close - next1.open) + (next2.close - next2.open)
    if (isBearishPrev && bullImpulse > avgRange * minImpulseMult) {
      const top = prevCandle.high
      const bottom = prevCandle.low

      let mitigated = false
      let mitigatedTime

      for (let j = i + 3; j < candles.length; j++) {
        if (candles[j].low <= top) {
          mitigated = true
          mitigatedTime = candles[j].time
          break
        }
      }

      obs.push({
        id: `ob-bull-${prevCandle.time}-${i}`,
        type: 'BULLISH_OB',
        startTime: prevCandle.time,
        endTime: mitigatedTime || candles[candles.length - 1].time,
        top,
        bottom,
        mitigated,
        mitigatedTime
      })
    }

    const bearImpulse = (prevCandle.open - next1.close) + (next1.open - next2.close)
    if (isBullishPrev && bearImpulse > avgRange * minImpulseMult) {
      const top = prevCandle.high
      const bottom = prevCandle.low

      let mitigated = false
      let mitigatedTime

      for (let j = i + 3; j < candles.length; j++) {
        if (candles[j].high >= bottom) {
          mitigated = true
          mitigatedTime = candles[j].time
          break
        }
      }

      obs.push({
        id: `ob-bear-${prevCandle.time}-${i}`,
        type: 'BEARISH_OB',
        startTime: prevCandle.time,
        endTime: mitigatedTime || candles[candles.length - 1].time,
        top,
        bottom,
        mitigated,
        mitigatedTime
      })
    }
  }

  return obs
}

export function detectMarketStructure(candles) {
  if (!candles || candles.length < 15) return []

  const breaks = []

  const scanStructurePass = (swingLength, category) => {
    const swingHighs = []
    const swingLows = []

    for (let i = swingLength; i < candles.length - swingLength; i++) {
      const currentHigh = candles[i].high
      const currentLow = candles[i].low

      let isHigh = true
      let isLow = true

      for (let k = i - swingLength; k <= i + swingLength; k++) {
        if (k === i) continue
        if (candles[k].high >= currentHigh) isHigh = false
        if (candles[k].low <= currentLow) isLow = false
      }

      if (isHigh) swingHighs.push({ index: i, time: candles[i].time, price: currentHigh })
      if (isLow) swingLows.push({ index: i, time: candles[i].time, price: currentLow })
    }

    let currentTrend = 'BULLISH'

    for (let i = swingLength; i < candles.length; i++) {
      const candle = candles[i]

      const prevHighs = swingHighs.filter((h) => h.index < i)
      const lastHigh = prevHighs[prevHighs.length - 1]

      if (lastHigh && candle.close > lastHigh.price) {
        const alreadyRecorded = breaks.some(
          (b) => b.category === category && b.swingTime === lastHigh.time
        )
        if (!alreadyRecorded) {
          const isChoch = currentTrend === 'BEARISH'
          breaks.push({
            id: `struct-${category.toLowerCase()}-high-${lastHigh.time}-${i}`,
            type: isChoch ? 'BULLISH_CHOCH' : 'BULLISH_BOS',
            category,
            level: lastHigh.price,
            swingTime: lastHigh.time,
            breakTime: candle.time,
            mitigated: false
          })
          currentTrend = 'BULLISH'
        }
      }

      const prevLows = swingLows.filter((l) => l.index < i)
      const lastLow = prevLows[prevLows.length - 1]

      if (lastLow && candle.close < lastLow.price) {
        const alreadyRecorded = breaks.some(
          (b) => b.category === category && b.swingTime === lastLow.time
        )
        if (!alreadyRecorded) {
          const isChoch = currentTrend === 'BULLISH'
          breaks.push({
            id: `struct-${category.toLowerCase()}-low-${lastLow.time}-${i}`,
            type: isChoch ? 'BEARISH_CHOCH' : 'BEARISH_BOS',
            category,
            level: lastLow.price,
            swingTime: lastLow.time,
            breakTime: candle.time,
            mitigated: false
          })
          currentTrend = 'BEARISH'
        }
      }
    }
  }

  scanStructurePass(7, 'MAJOR')
  scanStructurePass(3, 'INTERNAL')

  return breaks
}

export function detectLiquidityPools(candles, tolerancePct = 0.05) {
  if (!candles || candles.length < 10) return []

  const pools = []
  const swingLength = 4

  const highs = []
  const lows = []

  for (let i = swingLength; i < candles.length - swingLength; i++) {
    let isHigh = true
    let isLow = true

    for (let k = i - swingLength; k <= i + swingLength; k++) {
      if (k === i) continue
      if (candles[k].high >= candles[i].high) isHigh = false
      if (candles[k].low <= candles[i].low) isLow = false
    }

    if (isHigh) highs.push({ time: candles[i].time, price: candles[i].high, index: i })
    if (isLow) lows.push({ time: candles[i].time, price: candles[i].low, index: i })
  }

  for (let a = 0; a < highs.length - 1; a++) {
    for (let b = a + 1; b < highs.length; b++) {
      const diffPct = (Math.abs(highs[a].price - highs[b].price) / highs[a].price) * 100
      if (diffPct <= tolerancePct) {
        const poolLevel = Math.max(highs[a].price, highs[b].price)
        const startTime = highs[a].time

        let swept = false
        let sweepTime

        for (let j = highs[b].index + 1; j < candles.length; j++) {
          const c = candles[j]
          if (c.high > poolLevel && c.close < poolLevel) {
            swept = true
            sweepTime = c.time
            break
          }
        }

        pools.push({
          id: `bsl-${startTime}-${highs[b].time}`,
          type: 'BSL',
          level: poolLevel,
          startTime,
          swept,
          sweepTime,
          sweepCandleTime: sweepTime
        })

        break
      }
    }
  }

  for (let a = 0; a < lows.length - 1; a++) {
    for (let b = a + 1; b < lows.length; b++) {
      const diffPct = (Math.abs(lows[a].price - lows[b].price) / lows[a].price) * 100
      if (diffPct <= tolerancePct) {
        const poolLevel = Math.min(lows[a].price, lows[b].price)
        const startTime = lows[a].time

        let swept = false
        let sweepTime

        for (let j = lows[b].index + 1; j < candles.length; j++) {
          const c = candles[j]
          if (c.low < poolLevel && c.close > poolLevel) {
            swept = true
            sweepTime = c.time
            break
          }
        }

        pools.push({
          id: `ssl-${startTime}-${lows[b].time}`,
          type: 'SSL',
          level: poolLevel,
          startTime,
          swept,
          sweepTime,
          sweepCandleTime: sweepTime
        })

        break
      }
    }
  }

  return pools
}

export function detectPremiumDiscount(candles, lookback = 100) {
  if (!candles || candles.length < 20) return null

  const slice = candles.slice(-Math.min(candles.length, lookback))
  let maxHigh = -Infinity
  let minLow = Infinity
  let highTime = slice[0].time
  let lowTime = slice[0].time

  slice.forEach((c) => {
    if (c.high > maxHigh) {
      maxHigh = c.high
      highTime = c.time
    }
    if (c.low < minLow) {
      minLow = c.low
      lowTime = c.time
    }
  })

  if (maxHigh <= minLow) return null

  const equilibrium = (maxHigh + minLow) / 2
  const ote618 = minLow + (maxHigh - minLow) * 0.618
  const ote790 = minLow + (maxHigh - minLow) * 0.790
  const startTime = Math.min(highTime, lowTime)

  return {
    swingHigh: maxHigh,
    swingLow: minLow,
    equilibrium,
    ote618,
    ote790,
    startTime,
    highTime,
    lowTime
  }
}

export function detectSupplyDemandZones(candles, impulseFactor = 1.8, lookback = 5) {
  if (!candles || candles.length < lookback + 2) return []

  const zones = []
  const atr = calcATR(candles, 14)

  for (let i = lookback; i < candles.length - 1; i++) {
    const impulse = candles[i + 1]
    const impulseBody = Math.abs(impulse.close - impulse.open)
    const isBullImpulse = impulse.close > impulse.open && impulseBody >= atr * impulseFactor
    const isBearImpulse = impulse.close < impulse.open && impulseBody >= atr * impulseFactor

    if (!isBullImpulse && !isBearImpulse) continue

    const baseStart = Math.max(0, i - 2)
    const baseCandles = candles.slice(baseStart, i + 1)
    const zoneTop = Math.max(...baseCandles.map((c) => c.high))
    const zoneBot = Math.min(...baseCandles.map((c) => c.low))

    const zoneType = isBullImpulse ? 'DEMAND' : 'SUPPLY'
    const id = `sd-${zoneType}-${candles[baseStart].time}`

    if (zones.some((z) => z.id === id)) continue

    const futureCandles = candles.slice(i + 2)
    let strength = 'FRESH'
    let endTime = candles[candles.length - 1].time

    for (const fc of futureCandles) {
      if (zoneType === 'DEMAND') {
        if (fc.close < zoneBot) { strength = 'BROKEN'; endTime = fc.time; break }
        if (fc.low <= zoneTop && fc.close >= zoneBot) strength = 'TESTED'
      } else {
        if (fc.close > zoneTop) { strength = 'BROKEN'; endTime = fc.time; break }
        if (fc.high >= zoneBot && fc.close <= zoneTop) strength = 'TESTED'
      }
    }

    if (strength !== 'BROKEN') {
      zones.push({
        id,
        type: zoneType,
        strength,
        top: zoneTop,
        bottom: zoneBot,
        originTime: candles[baseStart].time,
        endTime,
        impulseSize: impulseBody
      })
    }
  }

  return zones
}

function calcATR(candles, period) {
  if (candles.length < period + 1) return 0
  const slice = candles.slice(-period - 1)
  let sum = 0
  for (let i = 1; i < slice.length; i++) {
    const tr = Math.max(
      slice[i].high - slice[i].low,
      Math.abs(slice[i].high - slice[i - 1].close),
      Math.abs(slice[i].low - slice[i - 1].close)
    )
    sum += tr
  }
  return sum / period
}

export function detectTrendlineLiquidity(candles, pivotLen = 5, minTouches = 2, tolerancePct = 0.002) {
  if (!candles || candles.length < pivotLen * 2 + 2) return []

  const atr = calcATR(candles, 14)
  const tol = atr * 0.3

  const pivotHighs = []
  const pivotLows = []

  for (let i = pivotLen; i < candles.length - pivotLen; i++) {
    const c = candles[i]
    let isHigh = true
    let isLow = true
    for (let j = i - pivotLen; j <= i + pivotLen; j++) {
      if (j === i) continue
      if (candles[j].high >= c.high) isHigh = false
      if (candles[j].low <= c.low) isLow = false
    }
    if (isHigh) pivotHighs.push({ idx: i, price: c.high, time: c.time })
    if (isLow) pivotLows.push({ idx: i, price: c.low, time: c.time })
  }

  const lines = []
  const lastCandle = candles[candles.length - 1]

  const processLine = (type, p1, p2, pivots) => {
    const slope = (p2.price - p1.price) / (p2.idx - p1.idx)
    const priceAt = (idx) => p1.price + slope * (idx - p1.idx)

    let touches = 2
    let status = 'ACTIVE'
    let breakTime
    let breakPrice

    for (let i = p2.idx + 1; i < candles.length; i++) {
      const c = candles[i]
      const linePrice = priceAt(i)

      const touchPivot = pivots.find((p) => p.idx === i)
      if (touchPivot && Math.abs(touchPivot.price - linePrice) <= tol) {
        touches++
      }

      if (type === 'RESISTANCE') {
        if (c.close > linePrice + tol) {
          status = 'BROKEN'
          breakTime = c.time
          breakPrice = c.close
          break
        } else if (c.high > linePrice + tol && c.close <= linePrice) {
          status = 'SWEPT'
        }
      } else {
        if (c.close < linePrice - tol) {
          status = 'BROKEN'
          breakTime = c.time
          breakPrice = c.close
          break
        } else if (c.low < linePrice - tol && c.close >= linePrice) {
          status = 'SWEPT'
        }
      }
    }

    if (touches < minTouches + 1) return

    const projectedPrice = priceAt(candles.length - 1)
    const id = `tl-${type}-${p1.time}-${p2.time}`

    lines.push({
      id,
      type,
      status,
      p1Time: p1.time,
      p1Price: p1.price,
      p2Time: p2.time,
      p2Price: p2.price,
      projectedPrice,
      touchCount: touches,
      breakTime,
      breakPrice
    })
  }

  for (let a = 0; a < pivotHighs.length - 1; a++) {
    for (let b = a + 1; b < pivotHighs.length; b++) {
      processLine('RESISTANCE', pivotHighs[a], pivotHighs[b], pivotHighs)
    }
  }

  for (let a = 0; a < pivotLows.length - 1; a++) {
    for (let b = a + 1; b < pivotLows.length; b++) {
      processLine('SUPPORT', pivotLows[a], pivotLows[b], pivotLows)
    }
  }

  return lines
    .sort((a, b) => b.touchCount - a.touchCount || b.p2Time - a.p2Time)
    .slice(0, 6)
}

export function detectCandlestickPatterns(candles) {
  if (!candles || candles.length < 3) return []

  const atr = calcATR(candles, 14)
  const patterns = []

  for (let i = 1; i < candles.length; i++) {
    const c = candles[i]
    const prev = candles[i - 1]
    const body = Math.abs(c.close - c.open)
    const totalRange = c.high - c.low
    const upperWick = c.high - Math.max(c.open, c.close)
    const lowerWick = Math.min(c.open, c.close) - c.low
    const isBullCandle = c.close > c.open

    if (totalRange < atr * 0.3) continue

    const dominantWickRatio = 2.5
    if (body > 0 && totalRange > 0) {
      if (lowerWick >= body * dominantWickRatio && upperWick <= totalRange * 0.2) {
        patterns.push({
          id: `pp-bull-${c.time}`,
          type: 'BULLISH_PINBAR',
          candleTime: c.time,
          high: c.high,
          low: c.low,
          open: c.open,
          close: c.close,
          strength: lowerWick >= body * 4 ? 'STRONG' : 'NORMAL'
        })
        continue
      }
      if (upperWick >= body * dominantWickRatio && lowerWick <= totalRange * 0.2) {
        patterns.push({
          id: `pp-bear-${c.time}`,
          type: 'BEARISH_PINBAR',
          candleTime: c.time,
          high: c.high,
          low: c.low,
          open: c.open,
          close: c.close,
          strength: upperWick >= body * 4 ? 'STRONG' : 'NORMAL'
        })
        continue
      }
    }

    const prevBody = Math.abs(prev.close - prev.open)
    const prevIsBull = prev.close > prev.open
    if (body > 0 && prevBody > 0) {
      const bullEngulf = isBullCandle && !prevIsBull
        && c.open <= Math.min(prev.open, prev.close)
        && c.close >= Math.max(prev.open, prev.close)
      const bearEngulf = !isBullCandle && prevIsBull
        && c.open >= Math.max(prev.open, prev.close)
        && c.close <= Math.min(prev.open, prev.close)

      if (bullEngulf) {
        patterns.push({
          id: `eng-bull-${c.time}`,
          type: 'BULLISH_ENGULF',
          candleTime: c.time,
          high: c.high,
          low: c.low,
          open: c.open,
          close: c.close,
          strength: body >= prevBody * 1.5 ? 'STRONG' : 'NORMAL'
        })
        continue
      }
      if (bearEngulf) {
        patterns.push({
          id: `eng-bear-${c.time}`,
          type: 'BEARISH_ENGULF',
          candleTime: c.time,
          high: c.high,
          low: c.low,
          open: c.open,
          close: c.close,
          strength: body >= prevBody * 1.5 ? 'STRONG' : 'NORMAL'
        })
        continue
      }
    }

    if (c.high < prev.high && c.low > prev.low && i >= 2) {
      const c2 = candles[i - 2]
      const isBullBias = prev.close > c2.close
      patterns.push({
        id: `ib-${isBullBias ? 'bull' : 'bear'}-${c.time}`,
        type: isBullBias ? 'INSIDE_BAR_BULL' : 'INSIDE_BAR_BEAR',
        candleTime: c.time,
        high: c.high,
        low: c.low,
        open: c.open,
        close: c.close,
        strength: (prev.high - prev.low) >= atr * 1.2 ? 'STRONG' : 'NORMAL'
      })
    }
  }

  return patterns.slice(-8)
}
