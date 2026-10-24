// Canvas overlay renderer for SMC/ICT/PA detector results — the layer that
// sits above the lightweight-charts canvas. Pure 2D canvas drawing: maps
// candle time → x (timeScale) and price → y (series) so boxes/lines/badges
// track pan, zoom and live-bar motion.

const FONT = 'bold 9px monospace'

function zoneBox(ctx, s, { top, bottom, startTime, endTime, fill, stroke, label }) {
  const yTop = s.series.priceToCoordinate(top)
  const yBot = s.series.priceToCoordinate(bottom)
  if (yTop === null || yBot === null) return
  const xStart = Math.max(0, s.timeScale.timeToCoordinate(startTime) ?? 0)
  const xEnd = Math.min(s.maxX, s.timeScale.timeToCoordinate(endTime) ?? s.maxX)
  const boxWidth = xEnd - xStart
  if (boxWidth <= 5 || xStart >= s.maxX) return
  ctx.fillStyle = fill
  ctx.fillRect(xStart, yTop, boxWidth, yBot - yTop)
  ctx.strokeStyle = stroke
  ctx.lineWidth = 1
  ctx.strokeRect(xStart, yTop, boxWidth, yBot - yTop)
  if (label) {
    ctx.fillStyle = stroke
    ctx.font = FONT
    ctx.fillText(label, xStart + 4, yTop + 11)
  }
}

function fullBand(ctx, s, { startTime, endTime, fill, stroke, label, labelY = 12 }) {
  const xStart = Math.max(0, s.timeScale.timeToCoordinate(startTime) ?? 0)
  const xEnd = Math.min(s.maxX, s.timeScale.timeToCoordinate(endTime) ?? s.maxX)
  const bandWidth = xEnd - xStart
  if (bandWidth <= 4 || xStart >= s.maxX) return
  ctx.fillStyle = fill
  ctx.fillRect(xStart, 0, bandWidth, s.height)
  if (stroke) {
    ctx.strokeStyle = stroke
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(xStart, 2)
    ctx.lineTo(xEnd, 2)
    ctx.stroke()
  }
  if (label) {
    ctx.fillStyle = stroke || fill
    ctx.font = FONT
    ctx.textAlign = 'center'
    ctx.fillText(label, xStart + bandWidth / 2, labelY)
    ctx.textAlign = 'left'
  }
}

function hLine(ctx, s, { price, x1, x2, color, width = 1, dash = [], label, labelAbove = true }) {
  const y = s.series.priceToCoordinate(price)
  if (y === null) return
  const startX = Math.max(0, x1 ?? 0)
  const endX = Math.min(s.maxX, x2 ?? s.maxX)
  if (endX - startX <= 5 || startX >= s.maxX) return
  ctx.strokeStyle = color
  ctx.lineWidth = width
  ctx.setLineDash(dash)
  ctx.beginPath()
  ctx.moveTo(startX, y)
  ctx.lineTo(endX, y)
  ctx.stroke()
  ctx.setLineDash([])
  if (label) {
    ctx.fillStyle = color
    ctx.font = FONT
    ctx.textAlign = 'center'
    ctx.fillText(label, startX + (endX - startX) / 2, labelAbove ? y - 4 : y + 11)
    ctx.textAlign = 'left'
  }
}

function tag(ctx, s, { time, price, text, fill, stroke, width = 90, above = true }) {
  const x = s.timeScale.timeToCoordinate(time)
  const y = s.series.priceToCoordinate(price)
  if (x === null || y === null || x >= s.maxX) return
  const tagY = above ? y - 22 : y + 6
  ctx.fillStyle = fill
  ctx.fillRect(x - width / 2, tagY, width, 15)
  ctx.strokeStyle = stroke
  ctx.lineWidth = 1
  ctx.strokeRect(x - width / 2, tagY, width, 15)
  ctx.fillStyle = '#fff'
  ctx.font = FONT
  ctx.textAlign = 'center'
  ctx.fillText(text, x, tagY + 11)
  ctx.textAlign = 'left'
}

export function drawSmcOverlays(ctx, opts) {
  const s = {
    series: opts.series,
    timeScale: opts.chart.timeScale(),
    width: opts.width,
    height: opts.height,
    maxX: opts.width - 70 // price-axis gutter — keep overlays off the scale
  }
  const { detections: d, toggles: t, candles } = opts
  const lastTime = candles[candles.length - 1].time

  // 1. FVG boxes (unmitigated, last 4)
  if (t.fvg && d.fvg.length >= 3) {
    d.fvg.filter((f) => !f.mitigated).slice(-4).forEach((fvg) => {
      zoneBox(ctx, s, {
        top: fvg.top, bottom: fvg.bottom, startTime: fvg.startTime, endTime: fvg.endTime,
        fill: fvg.type === 'BULLISH' ? 'rgba(0,245,160,0.14)' : 'rgba(255,73,92,0.14)',
        stroke: fvg.type === 'BULLISH' ? 'rgba(0,245,160,0.6)' : 'rgba(255,73,92,0.6)',
        label: fvg.type === 'BULLISH' ? 'BULL FVG' : 'BEAR FVG'
      })
    })
  }

  // 2. Order Block boxes (unmitigated, last 3)
  if (t.ob && d.ob.length >= 5) {
    d.ob.filter((o) => !o.mitigated).slice(-3).forEach((ob) => {
      zoneBox(ctx, s, {
        top: ob.top, bottom: ob.bottom, startTime: ob.startTime, endTime: ob.endTime,
        fill: ob.type === 'BULLISH_OB' ? 'rgba(0,229,255,0.18)' : 'rgba(236,72,153,0.18)',
        stroke: ob.type === 'BULLISH_OB' ? 'rgba(0,229,255,0.8)' : 'rgba(236,72,153,0.8)',
        label: ob.type === 'BULLISH_OB' ? 'DEMAND OB' : 'SUPPLY OB'
      })
    })
  }

  // 3. Market structure BOS/CHoCH lines (last 8)
  if (t.structure && d.structure.length >= 10) {
    d.structure.slice(-8).forEach((sb) => {
      const isBull = sb.type.startsWith('BULLISH')
      const isChoch = sb.type.includes('CHOCH')
      const isMajor = sb.category === 'MAJOR'
      const color = isMajor
        ? (isBull ? '#00f5a0' : '#ff495c')
        : (isBull ? '#00e5ff' : '#ec4899')
      hLine(ctx, s, {
        price: sb.level, x1: sb.swingTime, x2: sb.breakTime,
        color,
        width: isMajor ? (isChoch ? 2 : 1.5) : 1,
        dash: isChoch ? [] : (isMajor ? [6, 4] : [2, 3]),
        label: `${isMajor ? 'MAJOR' : 'i'}${isChoch ? 'CHoCH' : 'BOS'}`,
        labelAbove: isBull
      })
    })
  }

  // 4. Liquidity pools BSL/SSL (last 6)
  if (t.liquidity && d.liquidity.length >= 10) {
    d.liquidity.slice(-6).forEach((pool) => {
      const isBSL = pool.type === 'BSL'
      const color = isBSL ? '#00e5ff' : '#ec4899'
      hLine(ctx, s, {
        price: pool.level,
        x1: pool.startTime,
        x2: pool.swept ? (pool.sweepTime || pool.startTime) : lastTime,
        color,
        width: pool.swept ? 1.5 : 1,
        dash: [2, 2],
        label: isBSL
          ? (pool.swept ? 'BSL SWEEPT' : 'BSL (Equal Highs)')
          : (pool.swept ? 'SSL SWEEPT' : 'SSL (Equal Lows)'),
        labelAbove: isBSL
      })
    })
  }

  // 5. Premium vs Discount equilibrium bands
  if (t.equilibrium && d.pd) {
    const pd = d.pd
    const yHigh = s.series.priceToCoordinate(pd.swingHigh)
    const yLow = s.series.priceToCoordinate(pd.swingLow)
    const yEq = s.series.priceToCoordinate(pd.equilibrium)
    const xStart = Math.max(0, s.timeScale.timeToCoordinate(pd.startTime) ?? 0)
    if (yHigh !== null && yLow !== null && yEq !== null && xStart < s.maxX) {
      const boxWidth = Math.max(30, s.maxX - xStart)
      ctx.fillStyle = 'rgba(255,73,92,0.05)'
      ctx.fillRect(xStart, yHigh, boxWidth, yEq - yHigh)
      ctx.fillStyle = 'rgba(0,245,160,0.05)'
      ctx.fillRect(xStart, yEq, boxWidth, yLow - yEq)
      hLine(ctx, s, { price: pd.equilibrium, x1: xStart, x2: s.maxX, color: '#ffd700', width: 1.2, dash: [4, 4], label: '0.50 EQUILIBRIUM', labelAbove: true })
      ctx.fillStyle = 'rgba(255,73,92,0.7)'
      ctx.font = FONT
      ctx.textAlign = 'right'
      ctx.fillText('PREMIUM (SELL ZONE)', s.maxX - 10, yHigh + 14)
      ctx.fillStyle = 'rgba(0,245,160,0.7)'
      ctx.fillText('DISCOUNT (BUY ZONE)', s.maxX - 10, yLow - 6)
      ctx.textAlign = 'left'
    }
  }

  // 6. ICT sessions / kill zones (last 10)
  if (t.sessions && d.sessions.length >= 10) {
    d.sessions.slice(-10).forEach((sess) => {
      const colors = {
        ASIA: { fill: 'rgba(147,51,234,0.08)', stroke: '#9333ea' },
        LONDON: { fill: 'rgba(0,229,255,0.09)', stroke: '#00e5ff' },
        NEW_YORK: { fill: 'rgba(255,170,0,0.09)', stroke: '#ffaa00' }
      }[sess.type] || { fill: 'rgba(147,51,234,0.08)', stroke: '#9333ea' }
      fullBand(ctx, s, { startTime: sess.startTime, endTime: sess.endTime, ...colors, label: sess.name })
    })
  }

  // 7. ICT silver bullet windows (last 6)
  if (t.sb && d.sb.length >= 10) {
    d.sb.slice(-6).forEach((sb) => {
      const xStart = Math.max(0, s.timeScale.timeToCoordinate(sb.startTime) ?? 0)
      const xEnd = Math.min(s.maxX, s.timeScale.timeToCoordinate(sb.endTime) ?? s.maxX)
      if (xEnd - xStart <= 4 || xStart >= s.maxX) return
      ctx.fillStyle = 'rgba(255,215,0,0.12)'
      ctx.fillRect(xStart, 0, xEnd - xStart, s.height)
      ctx.strokeStyle = 'rgba(255,215,0,0.8)'
      ctx.lineWidth = 1.2
      ctx.setLineDash([3, 3])
      ctx.beginPath(); ctx.moveTo(xStart, 0); ctx.lineTo(xStart, s.height); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(xEnd, 0); ctx.lineTo(xEnd, s.height); ctx.stroke()
      ctx.setLineDash([])
      ctx.fillStyle = 'rgba(255,215,0,0.25)'
      ctx.fillRect(xStart + (xEnd - xStart) / 2 - 42, 18, 84, 14)
      ctx.strokeStyle = '#ffd700'
      ctx.strokeRect(xStart + (xEnd - xStart) / 2 - 42, 18, 84, 14)
      ctx.fillStyle = '#fff'
      ctx.font = FONT
      ctx.textAlign = 'center'
      ctx.fillText('SILVER BULLET', xStart + (xEnd - xStart) / 2, 28)
      ctx.textAlign = 'left'
    })
  }

  // 8. ICT OTE zone (0.618 – 0.705 – 0.790)
  if (t.ote && d.ote) {
    const ote = d.ote
    const y618 = s.series.priceToCoordinate(ote.fib618)
    const y705 = s.series.priceToCoordinate(ote.fib705)
    const y790 = s.series.priceToCoordinate(ote.fib790)
    const xStart = Math.max(0, s.timeScale.timeToCoordinate(ote.startTime) ?? 0)
    if (y618 !== null && y705 !== null && y790 !== null && xStart < s.maxX) {
      const topY = Math.min(y618, y790)
      const botY = Math.max(y618, y790)
      const boxWidth = Math.max(30, s.maxX - xStart)
      ctx.fillStyle = 'rgba(0,229,255,0.12)'
      ctx.fillRect(xStart, topY, boxWidth, botY - topY)
      ctx.strokeStyle = 'rgba(0,229,255,0.6)'
      ctx.strokeRect(xStart, topY, boxWidth, botY - topY)
      ctx.strokeStyle = '#ffd700'
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(xStart, y705); ctx.lineTo(s.maxX, y705); ctx.stroke()
      ctx.fillStyle = '#ffd700'
      ctx.font = FONT
      ctx.textAlign = 'center'
      ctx.fillText('0.705 SWEET SPOT', xStart + boxWidth / 2, y705 - 4)
      ctx.fillStyle = '#00e5ff'
      ctx.textAlign = 'right'
      ctx.fillText('0.618 OTE', s.maxX - 10, y618 - 3)
      ctx.fillStyle = '#ec4899'
      ctx.fillText('0.790 OTE', s.maxX - 10, y790 + 10)
      ctx.textAlign = 'left'
    }
  }

  // 9. Judas swing badges (last 6)
  if (t.judas && d.judas.length >= 15) {
    d.judas.slice(-6).forEach((j) => {
      const isBear = j.type === 'BEARISH_JUDAS'
      tag(ctx, s, {
        time: j.candleTime, price: j.level,
        text: isBear ? 'JUDAS (BEAR)' : 'JUDAS (BULL)',
        fill: isBear ? 'rgba(255,73,92,0.25)' : 'rgba(0,245,160,0.25)',
        stroke: isBear ? '#ff495c' : '#00f5a0',
        width: 90, above: isBear
      })
    })
  }

  // 10. AMD Power of 3 cycles (last 2)
  if (t.amd && d.amd.length >= 20) {
    d.amd.slice(-2).forEach((cycle) => {
      const bull = cycle.trend === 'BULLISH'
      fullBand(ctx, s, { startTime: cycle.accumStartTime, endTime: cycle.accumEndTime, fill: 'rgba(147,51,234,0.06)', stroke: '#9333ea', label: 'ACCUM' })
      fullBand(ctx, s, { startTime: cycle.manipStartTime, endTime: cycle.manipEndTime, fill: 'rgba(255,73,92,0.06)', stroke: '#ff495c', label: 'MANIP' })
      fullBand(ctx, s, { startTime: cycle.distribStartTime, endTime: cycle.distribEndTime, fill: bull ? 'rgba(0,245,160,0.06)' : 'rgba(255,73,92,0.06)', stroke: bull ? '#00f5a0' : '#ff495c', label: `DISTRIB ${bull ? 'UP' : 'DN'}`, labelY: 24 })
    })
  }

  // 11. Supply & Demand zone boxes (last 4)
  if (t.sd && d.sd.length >= 7) {
    d.sd.slice(-4).forEach((z) => {
      const isDemand = z.type === 'DEMAND'
      zoneBox(ctx, s, {
        top: z.top, bottom: z.bottom, startTime: z.originTime, endTime: z.endTime,
        fill: isDemand ? 'rgba(0,245,160,0.12)' : 'rgba(255,73,92,0.12)',
        stroke: isDemand ? 'rgba(0,245,160,0.7)' : 'rgba(255,73,92,0.7)',
        label: `${isDemand ? 'DEMAND' : 'SUPPLY'} (${z.strength})`
      })
    })
  }

  // 12. Trendline liquidity (top 6 by touches)
  if (t.tl && d.tl.length) {
    d.tl.forEach((tl) => {
      const isSupport = tl.type === 'SUPPORT'
      const color = isSupport ? '#00f5a0' : '#ff495c'
      const x1 = s.timeScale.timeToCoordinate(tl.p1Time)
      const x2 = s.timeScale.timeToCoordinate(lastTime)
      if (x1 === null || x2 === null) return
      const y1 = s.series.priceToCoordinate(tl.p1Price)
      const y2 = s.series.priceToCoordinate(tl.projectedPrice)
      if (y1 === null || y2 === null) return
      ctx.strokeStyle = color
      ctx.lineWidth = 1
      ctx.setLineDash([4, 3])
      ctx.beginPath()
      ctx.moveTo(Math.max(0, x1), y1)
      ctx.lineTo(Math.min(s.maxX, x2), y2)
      ctx.stroke()
      ctx.setLineDash([])
      ctx.fillStyle = color
      ctx.font = FONT
      ctx.textAlign = 'center'
      ctx.fillText(`${isSupport ? 'S' : 'R'} ×${tl.touchCount}${tl.status !== 'ACTIVE' ? ` ${tl.status}` : ''}`, Math.max(0, x1), y1 - 4)
      ctx.textAlign = 'left'
    })
  }

  // 13. Candlestick patterns (last 8)
  if (t.cp && d.cp.length >= 3) {
    d.cp.slice(-8).forEach((p) => {
      const bull = p.type.startsWith('BULLISH') || p.type === 'INSIDE_BAR_BULL'
      const label = p.type.startsWith('BULLISH_PINBAR') || p.type.startsWith('BEARISH_PINBAR')
        ? 'PINBAR'
        : p.type.includes('ENGULF') ? 'ENGULF' : 'IN. BAR'
      tag(ctx, s, {
        time: p.candleTime, price: bull ? p.low : p.high,
        text: label,
        fill: bull ? 'rgba(0,245,160,0.2)' : 'rgba(255,73,92,0.2)',
        stroke: bull ? '#00f5a0' : '#ff495c',
        width: 64, above: !bull
      })
    })
  }
}
