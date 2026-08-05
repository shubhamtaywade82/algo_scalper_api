// ICT session / kill-zone / OTE / Judas / AMD engines (ported from
// sdk/dhanhq-charts/src/utils/ictEngine.ts). All times are IST windows derived
// from unix-second candle timestamps (UTC-based).

const IST_OFFSET_MIN = 330

function toISTMinutes(unixSec) {
  const date = new Date(unixSec * 1000)
  const istMins = date.getUTCHours() * 60 + date.getUTCMinutes() + IST_OFFSET_MIN
  return ((istMins % 1440) + 1440) % 1440
}

export function detectICTSessions(candles) {
  if (!candles || candles.length === 0) return []

  const sessions = []
  let currentSession = null

  const pushCurrentSession = () => {
    if (!currentSession || currentSession.candles.length === 0) return
    const cList = currentSession.candles
    sessions.push({
      id: `session-${currentSession.type}-${cList[0].time}`,
      name: currentSession.name,
      type: currentSession.type,
      startTime: cList[0].time,
      endTime: cList[cList.length - 1].time,
      high: Math.max(...cList.map((c) => c.high)),
      low: Math.min(...cList.map((c) => c.low))
    })
  }

  candles.forEach((candle) => {
    const normalizedMinutes = toISTMinutes(candle.time)

    let targetType = null
    let name = ''

    if (normalizedMinutes >= 90 && normalizedMinutes < 360) {
      targetType = 'ASIA'
      name = 'ASIA RANGE'
    } else if (normalizedMinutes >= 750 && normalizedMinutes < 930) {
      targetType = 'LONDON'
      name = 'LONDON KZ'
    } else if (normalizedMinutes >= 1050 && normalizedMinutes < 1230) {
      targetType = 'NEW_YORK'
      name = 'NY KZ'
    }

    if (targetType) {
      if (!currentSession || currentSession.type !== targetType) {
        pushCurrentSession()
        currentSession = { type: targetType, name, candles: [candle] }
      } else {
        currentSession.candles.push(candle)
      }
    } else {
      if (currentSession) {
        pushCurrentSession()
        currentSession = null
      }
    }
  })

  pushCurrentSession()

  return sessions
}

export function detectSilverBulletWindows(candles) {
  if (!candles || candles.length === 0) return []

  const windows = []
  let currentSB = null

  const pushCurrentSB = () => {
    if (!currentSB || currentSB.candles.length === 0) return
    const cList = currentSB.candles
    windows.push({
      id: `sb-${currentSB.type}-${cList[0].time}`,
      name: currentSB.name,
      type: currentSB.type,
      startTime: cList[0].time,
      endTime: cList[cList.length - 1].time
    })
  }

  candles.forEach((candle) => {
    const normalizedMinutes = toISTMinutes(candle.time)

    let targetType = null
    let name = ''

    if (normalizedMinutes >= 810 && normalizedMinutes < 870) {
      targetType = 'LONDON_SB'
      name = 'SILVER BULLET (LDN)'
    } else if (normalizedMinutes >= 1170 && normalizedMinutes < 1230) {
      targetType = 'NY_AM_SB'
      name = 'SILVER BULLET (NY AM)'
    } else if (normalizedMinutes >= 1410 || normalizedMinutes < 30) {
      targetType = 'NY_PM_SB'
      name = 'SILVER BULLET (NY PM)'
    }

    if (targetType) {
      if (!currentSB || currentSB.type !== targetType) {
        pushCurrentSB()
        currentSB = { type: targetType, name, candles: [candle] }
      } else {
        currentSB.candles.push(candle)
      }
    } else {
      if (currentSB) {
        pushCurrentSB()
        currentSB = null
      }
    }
  })

  pushCurrentSB()

  return windows
}

export function detectICTOTEZone(candles, lookback = 80) {
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

  const range = maxHigh - minLow
  const isBullish = highTime > lowTime
  const trend = isBullish ? 'BULLISH' : 'BEARISH'

  let fib618 = 0
  let fib705 = 0
  let fib790 = 0

  if (isBullish) {
    fib618 = maxHigh - range * 0.618
    fib705 = maxHigh - range * 0.705
    fib790 = maxHigh - range * 0.790
  } else {
    fib618 = minLow + range * 0.618
    fib705 = minLow + range * 0.705
    fib790 = minLow + range * 0.790
  }

  const startTime = Math.min(highTime, lowTime)

  return {
    swingHigh: maxHigh,
    swingLow: minLow,
    trend,
    fib618,
    fib705,
    fib790,
    startTime
  }
}

export function detectJudasSwings(candles) {
  if (!candles || candles.length < 15) return []

  const judasList = []
  const sessions = detectICTSessions(candles)
  const asiaSessions = sessions.filter((s) => s.type === 'ASIA')

  asiaSessions.forEach((asia) => {
    const postAsiaCandles = candles.filter((c) => c.time > asia.endTime)

    postAsiaCandles.forEach((c) => {
      const normalizedMinutes = toISTMinutes(c.time)

      const isKillZone =
        (normalizedMinutes >= 750 && normalizedMinutes < 930) ||
        (normalizedMinutes >= 1050 && normalizedMinutes < 1230)
      if (!isKillZone) return

      if (c.high > asia.high && c.close < asia.high) {
        const id = `judas-bear-${asia.id}-${c.time}`
        if (!judasList.some((j) => j.id === id)) {
          judasList.push({
            id,
            type: 'BEARISH_JUDAS',
            candleTime: c.time,
            level: c.high,
            asiaHigh: asia.high,
            asiaLow: asia.low
          })
        }
      }

      if (c.low < asia.low && c.close > asia.low) {
        const id = `judas-bull-${asia.id}-${c.time}`
        if (!judasList.some((j) => j.id === id)) {
          judasList.push({
            id,
            type: 'BULLISH_JUDAS',
            candleTime: c.time,
            level: c.low,
            asiaHigh: asia.high,
            asiaLow: asia.low
          })
        }
      }
    })
  })

  return judasList
}

export function detectAMDCycles(candles) {
  if (!candles || candles.length < 20) return []

  const cycles = []

  const dayMap = new Map()
  candles.forEach((c) => {
    const date = new Date(c.time * 1000)
    const istMs = date.getTime() + IST_OFFSET_MIN * 60 * 1000
    const dayKey = new Date(istMs).toISOString().slice(0, 10)
    if (!dayMap.has(dayKey)) dayMap.set(dayKey, [])
    dayMap.get(dayKey).push(c)
  })

  dayMap.forEach((dayCandles, dayKey) => {
    const accumCandles = dayCandles.filter((c) => {
      const istMins = toISTMinutes(c.time)
      return istMins >= 90 && istMins < 360
    })
    const manipCandles = dayCandles.filter((c) => {
      const istMins = toISTMinutes(c.time)
      return istMins >= 750 && istMins < 870
    })
    const distribCandles = dayCandles.filter((c) => {
      const istMins = toISTMinutes(c.time)
      return istMins >= 870 && istMins < 1230
    })

    if (accumCandles.length < 2 || manipCandles.length < 1 || distribCandles.length < 1) return

    const accumHigh = Math.max(...accumCandles.map((c) => c.high))
    const accumLow = Math.min(...accumCandles.map((c) => c.low))

    const manipHigh = Math.max(...manipCandles.map((c) => c.high))
    const manipLow = Math.min(...manipCandles.map((c) => c.low))

    const distribClose = distribCandles[distribCandles.length - 1].close
    const distribOpen = distribCandles[0].open

    if (manipLow < accumLow && distribClose > accumHigh) {
      cycles.push({
        id: `amd-bull-${dayKey}`,
        trend: 'BULLISH',
        accumStartTime: accumCandles[0].time,
        accumEndTime: accumCandles[accumCandles.length - 1].time,
        accumHigh,
        accumLow,
        manipStartTime: manipCandles[0].time,
        manipEndTime: manipCandles[manipCandles.length - 1].time,
        manipLevel: manipLow,
        distribStartTime: distribCandles[0].time,
        distribEndTime: distribCandles[distribCandles.length - 1].time,
        distribLevel: distribClose
      })
    }

    if (manipHigh > accumHigh && distribClose < accumLow) {
      cycles.push({
        id: `amd-bear-${dayKey}`,
        trend: 'BEARISH',
        accumStartTime: accumCandles[0].time,
        accumEndTime: accumCandles[accumCandles.length - 1].time,
        accumHigh,
        accumLow,
        manipStartTime: manipCandles[0].time,
        manipEndTime: manipCandles[manipCandles.length - 1].time,
        manipLevel: manipHigh,
        distribStartTime: distribCandles[0].time,
        distribEndTime: distribCandles[distribCandles.length - 1].time,
        distribLevel: distribClose
      })
    }
  })

  return cycles.sort((a, b) => a.accumStartTime - b.accumStartTime)
}
