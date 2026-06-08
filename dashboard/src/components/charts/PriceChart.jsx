import { onMount, onCleanup, createEffect } from 'solid-js'
import { createChart, CandlestickSeries, HistogramSeries, ColorType } from 'lightweight-charts'

// Exponential lerp toward a target — same approach as chart-studio's MotionEngine
// (current += (target - current) * smoothingFactor per animation frame).
// Snaps once the gap is imperceptible so we don't chase forever.
function lerp(current, target, factor, epsilon = 1e-6) {
  const diff = target - current
  if (Math.abs(diff) < epsilon) return target
  return current + diff * factor
}

const SMOOTHING = 0.18 // higher = snappier, lower = floatier (0.1-0.25 reads as "smooth")

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
 *   candles:   () => [{ time, open, high, low, close, volume }]  (time = unix seconds)
 *   height:    number (optional, default 420)
 *   fullHeight: boolean — stretch to container via lightweight-charts autoSize
 */
export default function PriceChart(props) {
  let containerEl
  let chart
  let candleSeries
  let volumeSeries
  let priceLine

  // Animation state for the live (last) candle + LTP line
  let rafId = null
  let renderedClose = null   // currently-painted close (lerps toward target)
  let targetBar = null       // latest known OHLC for the live bar
  let staticBars = []        // all-but-last bars, painted once via setData

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
      timeScale: { timeVisible: true, secondsVisible: false },
      crosshair: { mode: 0 },
      // Built-in kinetic scroll/zoom easing — the chart's own "smooth animation" layer
      kineticScroll: { touch: true, mouse: true }
    })

    candleSeries = chart.addSeries(CandlestickSeries, {
      upColor: '#34d399',
      downColor: '#fb7185',
      borderVisible: false,
      wickUpColor: '#34d399',
      wickDownColor: '#fb7185'
    })

    volumeSeries = chart.addSeries(HistogramSeries, {
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume'
    })
    chart.priceScale('volume').applyOptions({
      scaleMargins: { top: 0.85, bottom: 0 }
    })

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
      candleSeries.setData([])
      volumeSeries.setData([])
      return
    }

    staticBars = candles.slice(0, -1)
    const lastBar = candles[candles.length - 1]

    candleSeries.setData(staticBars.map(toCandlePoint))
    volumeSeries.setData(staticBars.map(toVolumePoint))

    // New live bar's open becomes the lerp start so each fresh refresh
    // re-animates from where the bar began rather than snapping to the latest close
    const isNewBar = !targetBar || targetBar.time !== lastBar.time
    targetBar = { ...lastBar }
    renderedClose = isNewBar ? lastBar.open : renderedClose

    kickAnimation()
    chart.timeScale().fitContent()
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
