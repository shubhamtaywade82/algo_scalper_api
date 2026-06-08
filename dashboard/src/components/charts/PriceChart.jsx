import { onMount, onCleanup, createEffect } from 'solid-js'
import { createChart, CandlestickSeries, HistogramSeries, LineSeries, createSeriesMarkers, ColorType } from 'lightweight-charts'

// Overlay indicators are just LineSeries fed derived {time, value} arrays.
// Add a new type by: (1) writing a compute fn here, (2) registering it in
// INDICATOR_COMPUTE, (3) adding it to the catalog passed from Charts.jsx.
function sma(bars, period) {
  const out = []
  let sum = 0
  for (let i = 0; i < bars.length; i++) {
    sum += bars[i].close
    if (i >= period) sum -= bars[i - period].close
    if (i >= period - 1) out.push({ time: bars[i].time, value: sum / period })
  }
  return out
}

function ema(bars, period) {
  const out = []
  const k = 2 / (period + 1)
  let prev = null
  for (let i = 0; i < bars.length; i++) {
    const close = bars[i].close
    prev = prev === null ? close : close * k + prev * (1 - k)
    if (i >= period - 1) out.push({ time: bars[i].time, value: prev })
  }
  return out
}

const INDICATOR_COMPUTE = { sma, ema }

// Exponential lerp toward a target — same approach as chart-studio's MotionEngine
// (current += (target - current) * smoothingFactor per animation frame).
// Snaps once the gap is imperceptible so we don't chase forever.
function lerp(current, target, factor, epsilon = 1e-6) {
  const diff = target - current
  if (Math.abs(diff) < epsilon) return target
  return current + diff * factor
}

const SMOOTHING = 0.18 // higher = snappier, lower = floatier (0.1-0.25 reads as "smooth")

// Default zoom on first load — show roughly this many bars rather than squeezing
// all 5 days of history into view (which renders candles as thin slivers).
const INITIAL_VISIBLE_BARS = 80

/**
 * Candlestick + volume chart wrapper around lightweight-charts (vanilla,
 * framework-agnostic — same library used by chart-studio / janus). Solid owns the
 * container element; the chart instance is imperative and lives outside reactivity.
 *
 * Live candle formation and the LTP line animate toward each new value via a
 * requestAnimationFrame lerp loop instead of snapping — mirrors chart-studio's
 * MotionEngine smoothing so price action reads as continuous motion, not steps.
 *
 * Props:
 *   candles:    () => [{ time, open, high, low, close, volume }]  (time = unix seconds)
 *   liveLtp:    () => number | null — real-time tick driving the forming bar + LTP line
 *   indicators: () => [{ id, type: 'sma'|'ema', period, color, enabled }] — overlay config
 *   positions:  () => [{ id, symbol, side, entry_price, created_at, pnl }] — active
 *               positions on this underlying; rendered as dotted entry-price lines
 *               + entry-time arrow markers, colored green/red by current PnL sign
 *   height:     number (optional, default 420)
 *   fullHeight: boolean — stretch to container via lightweight-charts autoSize
 */
export default function PriceChart(props) {
  let containerEl
  let chart
  let candleSeries
  let volumeSeries
  let priceLine
  let lastCandles = []
  const indicatorSeries = new Map() // id -> { series, config }
  let positionMarkers          // ISeriesMarkersPluginApi — entry-point arrows
  const positionLines = new Map() // id -> price line (entry price)

  // Animation state for the live (last) candle + LTP line
  let rafId = null
  let renderedClose = null   // currently-painted close (lerps toward target)
  let targetBar = null       // latest known OHLC for the live bar
  let staticBars = []        // all-but-last bars, painted once via setData
  let didInitialFit = false  // only auto-zoom on the very first data load

  function animate() {
    if (!chart || !candleSeries || !targetBar) {
      rafId = null
      return
    }

    if (renderedClose === null) renderedClose = targetBar.open

    renderedClose = lerp(renderedClose, targetBar.close, SMOOTHING)

    const liveBar = {
      time: targetBar.time,
      open: targetBar.open,
      high: Math.max(targetBar.high, renderedClose),
      low: Math.min(targetBar.low, renderedClose),
      close: renderedClose
    }

    candleSeries.update(liveBar)
    volumeSeries.update({
      time: targetBar.time,
      value: targetBar.volume || 0,
      color: liveBar.close >= liveBar.open ? 'rgba(52,211,153,0.35)' : 'rgba(251,113,133,0.35)'
    })

    if (priceLine) priceLine.applyOptions({ price: renderedClose })

    const settled = Math.abs(targetBar.close - renderedClose) < 1e-6
    if (!settled) {
      rafId = requestAnimationFrame(animate)
    } else {
      renderedClose = targetBar.close
      rafId = null
    }
  }

  function kickAnimation() {
    if (rafId === null) rafId = requestAnimationFrame(animate)
  }

  // Plots active positions on their underlying's chart: an entry-price dashed
  // line per position (so you can see at a glance whether price is above/below
  // your entry) plus an arrow marker at the moment of entry.
  function syncPositions() {
    if (!chart || !candleSeries || !positionMarkers) return
    const positions = props.positions ? props.positions() : []
    const seenIds = new Set()
    const markers = []

    for (const pos of positions) {
      seenIds.add(pos.id)
      const isLong = (pos.side || pos.direction || '').toUpperCase() !== 'SELL'
      const pnl = pos.pnl ?? 0
      const pnlColor = pnl >= 0 ? '#34d399' : '#fb7185'
      const pnlLabel = `${pnl >= 0 ? '+' : ''}₹${Number(pnl).toFixed(0)}${pos.pnl_pct != null ? ` (${pos.pnl_pct >= 0 ? '+' : ''}${pos.pnl_pct}%)` : ''}`

      let line = positionLines.get(pos.id)
      const lineOpts = {
        price: pos.entry_price,
        color: pnlColor,
        lineWidth: 1,
        lineStyle: 3, // dotted — visually distinct from the solid LTP dashed line
        axisLabelVisible: true,
        title: `${pos.symbol || 'POS'} @ ${pos.entry_price} · ${pnlLabel}`
      }
      if (!line) {
        line = candleSeries.createPriceLine(lineOpts)
        positionLines.set(pos.id, line)
      } else {
        line.applyOptions(lineOpts)
      }

      const entryTime = pos.created_at ? Math.floor(new Date(pos.created_at).getTime() / 1000) : null
      if (entryTime) {
        markers.push({
          time: entryTime,
          position: isLong ? 'belowBar' : 'aboveBar',
          color: pnlColor,
          shape: isLong ? 'arrowUp' : 'arrowDown',
          text: `${pos.symbol || ''} ${pos.entry_price} · ${pnlLabel}`.trim()
        })
      }
    }

    for (const [id, line] of positionLines) {
      if (!seenIds.has(id)) {
        candleSeries.removePriceLine(line)
        positionLines.delete(id)
      }
    }

    markers.sort((a, b) => a.time - b.time)
    positionMarkers.setMarkers(markers)
  }

  // Reconciles indicatorSeries against the current config: adds series for newly
  // enabled indicators, removes ones turned off, restyles changed ones, and
  // (re)computes data for anything whose config or the underlying candles changed.
  function syncIndicators() {
    if (!chart) return
    const configs = (props.indicators ? props.indicators() : []).filter(c => c.enabled)
    const seenIds = new Set()

    for (const cfg of configs) {
      seenIds.add(cfg.id)
      const computeFn = INDICATOR_COMPUTE[cfg.type]
      if (!computeFn) continue

      let entry = indicatorSeries.get(cfg.id)
      if (!entry) {
        const series = chart.addSeries(LineSeries, {
          color: cfg.color, lineWidth: 2, lastValueVisible: false, priceLineVisible: false
        })
        entry = { series, config: null }
        indicatorSeries.set(cfg.id, entry)
      }

      const prev = entry.config
      const restyled = !prev || prev.color !== cfg.color
      const recompute = !prev || prev.type !== cfg.type || prev.period !== cfg.period

      if (restyled) entry.series.applyOptions({ color: cfg.color })
      if (recompute) entry.series.setData(computeFn(lastCandles, cfg.period))
      entry.config = { ...cfg }
    }

    for (const [id, entry] of indicatorSeries) {
      if (!seenIds.has(id)) {
        chart.removeSeries(entry.series)
        indicatorSeries.delete(id)
      }
    }
  }

  onMount(() => {
    chart = createChart(containerEl, {
      layout: {
        background: { type: ColorType.Solid, color: 'transparent' },
        textColor: '#9ca3af'
      },
      grid: {
        vertLines: { color: 'rgba(255,255,255,0.04)' },
        horzLines: { color: 'rgba(255,255,255,0.04)' }
      },
      width: containerEl.clientWidth,
      height: props.fullHeight ? containerEl.clientHeight : (props.height || 420),
      autoSize: !!props.fullHeight,
      // rightOffset keeps a few empty bars between the latest candle and the
      // price axis instead of pinning it flush against the edge.
      timeScale: { timeVisible: true, secondsVisible: false, rightOffset: 5 },
      crosshair: { mode: 0 },
      // Built-in kinetic scroll/zoom easing — the chart's own "smooth animation" layer
      kineticScroll: { touch: true, mouse: true }
    })

    candleSeries = chart.addSeries(CandlestickSeries, {
      upColor: '#34d399',
      downColor: '#fb7185',
      borderVisible: false,
      wickUpColor: '#34d399',
      wickDownColor: '#fb7185',
      // Built-in last-value label disabled — our custom `priceLine` "LTP" label
      // already shows current price; both together duplicate the axis label.
      lastValueVisible: false,
      priceLineVisible: false
    })

    volumeSeries = chart.addSeries(HistogramSeries, {
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume'
    })
    chart.priceScale('volume').applyOptions({
      scaleMargins: { top: 0.85, bottom: 0 }
    })

    positionMarkers = createSeriesMarkers(candleSeries, [])

    priceLine = candleSeries.createPriceLine({
      price: 0,
      color: '#60a5fa',
      lineWidth: 1,
      lineStyle: 2, // dashed
      axisLabelVisible: true,
      title: 'LTP'
    })

    let ro
    if (!props.fullHeight) {
      ro = new ResizeObserver(entries => {
        const entry = entries[0]
        if (entry && chart) chart.applyOptions({ width: entry.contentRect.width })
      })
      ro.observe(containerEl)
    }

    onCleanup(() => {
      if (rafId !== null) cancelAnimationFrame(rafId)
      ro?.disconnect()
      chart?.remove()
      chart = null
    })
  })

  createEffect(() => {
    const candles = props.candles ? props.candles() : []
    if (!chart || !candleSeries) return

    if (rafId !== null) {
      cancelAnimationFrame(rafId)
      rafId = null
    }

    if (!candles.length) {
      staticBars = []
      targetBar = null
      renderedClose = null
      didInitialFit = false
      for (const line of positionLines.values()) candleSeries.removePriceLine(line)
      positionLines.clear()
      positionMarkers?.setMarkers([])
      candleSeries.setData([])
      volumeSeries.setData([])
      return
    }

    staticBars = candles.slice(0, -1)
    const lastBar = candles[candles.length - 1]

    candleSeries.setData(staticBars.map(toCandlePoint))
    volumeSeries.setData(staticBars.map(toVolumePoint))
    lastCandles = candles
    syncIndicators()
    syncPositions()

    // New live bar's open becomes the lerp start so each fresh refresh
    // re-animates from where the bar began rather than snapping to the latest close
    const isNewBar = !targetBar || targetBar.time !== lastBar.time
    targetBar = { ...lastBar }
    renderedClose = isNewBar ? lastBar.open : renderedClose

    kickAnimation()

    // Zoom to a fixed bar count on first load only — fitContent() squeezes all
    // history in (tiny candles) and re-fitting on every refresh would fight the
    // user's manual zoom/pan.
    if (!didInitialFit) {
      didInitialFit = true
      const total = candles.length
      chart.timeScale().setVisibleLogicalRange({
        from: Math.max(0, total - INITIAL_VISIBLE_BARS),
        to: total - 1 + 5 // include the rightOffset gap
      })
    }
  })

  // Indicator config changes (toggle on/off, edit period/color) — independent of
  // the candles effect so flipping a switch updates immediately, no refetch needed.
  createEffect(() => {
    props.indicators ? props.indicators() : null
    if (!chart || !lastCandles.length) return
    syncIndicators()
  })

  // Active-position overlay changes (open/close/PnL flip) — independent of the
  // candles refresh cadence so a fresh entry/exit shows up immediately.
  createEffect(() => {
    props.positions ? props.positions() : null
    if (!chart || !lastCandles.length) return
    syncPositions()
  })

  // Real-time WS ticks (sub-second) — overrides the forming bar's close so the
  // candle wick/body and LTP line move continuously between REST candle refreshes.
  createEffect(() => {
    const ltp = props.liveLtp ? props.liveLtp() : null
    if (ltp == null || !targetBar) return
    targetBar.close = ltp
    targetBar.high = Math.max(targetBar.high, ltp)
    targetBar.low = Math.min(targetBar.low, ltp)
    kickAnimation()
  })

  return <div ref={containerEl} class={`w-full rounded-2xl overflow-hidden ${props.fullHeight ? 'h-full' : ''}`} />
}

function toCandlePoint(c) {
  return { time: c.time, open: c.open, high: c.high, low: c.low, close: c.close }
}

function toVolumePoint(c) {
  return {
    time: c.time,
    value: c.volume || 0,
    color: c.close >= c.open ? 'rgba(52,211,153,0.35)' : 'rgba(251,113,133,0.35)'
  }
}
