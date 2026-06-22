import { onMount, onCleanup, createEffect, createSignal, For } from 'solid-js'
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
  let ltpSeries // short LTP "tail" — ends at the forming candle, not a full-width line
  let ltpTailAnchor = null // {time, value} — the tail's fixed left endpoint for the current bar
  let lastCandles = []
  const indicatorSeries = new Map() // id -> { series, config }
  let positionMarkers          // ISeriesMarkersPluginApi — entry-point arrows
  const positionLines = new Map() // id -> price line (entry price)
  const [capsules, setCapsules] = createSignal([]) // floating detail cards anchored to entry-price Y

  // Animation state for the live (last) candle + LTP line
  let rafId = null
  let renderedClose = null   // currently-painted close (lerps toward target)
  let lastVolPaint = null    // dedupe guard for volume bar repaints — {time,value,color}
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

    // Use the target's actual high/low — NOT Math.max/min(target, renderedClose).
    // Recomputing range from the lerping value every frame made the autoscaled
    // price axis recalculate every frame too, visibly "vibrating" the whole chart
    // when price moved fast. The live-tick effect already extends targetBar's
    // high/low the instant a new extreme prints, so the true range is always
    // known up front — the lerp only needs to animate `close` toward it.
    const isUp = targetBar.close >= targetBar.open
    // Highlight the active forming candle to make it pop against historical bars.
    // It will revert to the standard theme color when the minute rolls over and
    // the backbone fetch replaces it via setData.
    const highlightColor = isUp ? '#38bdf8' : '#fb923c' // Bright Blue for up, Bright Orange for down

    const liveBar = {
      time: targetBar.time,
      open: targetBar.open,
      high: targetBar.high,
      low: targetBar.low,
      close: renderedClose,
      color: highlightColor,
      wickColor: highlightColor,
      borderColor: highlightColor
    }

    candleSeries.update(liveBar)

    // Color by the TARGET's direction, not the lerping `liveBar.close` — the
    // animated value crosses `open` mid-lerp, which flipped the color every
    // frame it did. Direction is a property of the settled bar, not the
    // in-flight animation; it shouldn't change until a new bar starts.
    const volColor = targetBar.close >= targetBar.open ? 'rgba(52,211,153,0.35)' : 'rgba(251,113,133,0.35)'
    const volValue = targetBar.volume || 0
    if (lastVolPaint === null || lastVolPaint.value !== volValue || lastVolPaint.color !== volColor || lastVolPaint.time !== targetBar.time) {
      volumeSeries.update({ time: targetBar.time, value: volValue, color: volColor })
      lastVolPaint = { time: targetBar.time, value: volValue, color: volColor }
    }

    paintLtpTail(renderedClose)
    // Live bar updates can shift the autoscaled price range — keep capsules glued
    // to their entry-price level as the price→pixel mapping moves under them.
    if (capsules().length) recomputeCapsules()

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

  // `pos.entry_price` is the OPTION PREMIUM (e.g. ₹71 for a NIFTY PE) — wildly
  // off-scale from the underlying index price (~23,000) shown on this chart.
  // Anchoring a line/capsule there would sit far outside the visible range
  // (priceToCoordinate returns null, nothing renders). Instead anchor to the
  // underlying's own price at the moment of entry — the close of the candle
  // nearest `entryTime` — which is a meaningful "where the index was when I
  // bought this" reference level on the chart it's actually drawn on.
  function underlyingPriceNear(time) {
    if (!lastCandles.length || time == null) return null
    let lo = 0
    let hi = lastCandles.length - 1
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (lastCandles[mid].time < time) lo = mid + 1
      else hi = mid
    }
    const candidate = lastCandles[lo]
    const prev = lastCandles[lo - 1]
    if (prev && Math.abs(prev.time - time) <= Math.abs(candidate.time - time)) return prev.close
    return candidate.close
  }

  // Derives the display bundle for a position: option type (anchors marker side
  // since this bot only buys options — long CE reads bullish so plots below the
  // bar, long PE reads bearish so plots above), PnL color/label, etc.
  function describePosition(pos) {
    const optionType = /PE$/i.test(pos.symbol || '') ? 'PE' : 'CE'
    const isCall = optionType === 'CE'
    const pnl = pos.pnl ?? 0
    const pnlColor = pnl >= 0 ? '#34d399' : '#fb7185'
    const pnlLabel = `${pnl >= 0 ? '+' : ''}₹${Number(pnl).toFixed(0)}${pos.pnl_pct != null ? ` (${pos.pnl_pct >= 0 ? '+' : ''}${pos.pnl_pct}%)` : ''}`
    // Full symbols ("NIFTY-Jun2026-23100-PE") made the capsule wide enough that
    // the price/PnL spans clipped past the chart edge — show just strike+type.
    const strikeMatch = (pos.symbol || '').match(/(\d+)-(CE|PE)$/i)
    const shortSymbol = strikeMatch ? `${strikeMatch[1]} ${strikeMatch[2].toUpperCase()}` : (pos.symbol || 'POS')
    return { optionType, isCall, pnl, pnlColor, pnlLabel, shortSymbol }
  }

  // Resets the LTP tail's two-point window to the current bar — called once per
  // new bar (full `setData`), NOT every animation frame. A full data swap each
  // frame was what made the forming candle flicker (it forces lightweight-charts
  // to rebuild internal state for the whole series on every repaint).
  function resetLtpTail(value) {
    if (!ltpSeries || !targetBar || !Number.isFinite(value)) return
    // Scan backward for the last *distinct* timestamp — duplicate trailing
    // candles (forming bar appearing twice across REST/live merges) made a
    // naive `lastCandles[n-2].time` collide with `targetBar.time` and crash
    // `setData`'s asc-order assertion, killing this effect mid-run (which is
    // why volume stopped updating live — `kickAnimation()` never got reached).
    let prevTime = targetBar.time - 60
    for (let i = lastCandles.length - 1; i > 0; i--) {
      if (lastCandles[i - 1].time < targetBar.time) { prevTime = lastCandles[i - 1].time; break }
    }
    ltpTailAnchor = { time: prevTime, value: targetBar.open }
    ltpSeries.setData([ltpTailAnchor, { time: targetBar.time, value }])
  }

  // Per-frame repaint — `update()` only touches the series' last point, far
  // cheaper than a full `setData` swap and doesn't trigger the flicker above.
  // We don't need to manually draw into the empty axis gap either: lightweight-
  // charts already renders a dotted "tracking line" from a series' last point to
  // its own price-axis label whenever `lastValueVisible` is on (the same built-in
  // mechanism `createPriceLine`'s axis label used) — that tracking line *is* the
  // segment from the live candle to the LTP label.
  function paintLtpTail(value) {
    if (!ltpSeries || !targetBar || !Number.isFinite(value) || !ltpTailAnchor) return
    ltpSeries.update({ time: targetBar.time, value })
  }

  // Plots active positions on their underlying's chart: a thin dotted entry-price
  // line, an arrow marker at the entry candle, and a floating "capsule" detail
  // card anchored to the entry-price Y coordinate (recomputed in recomputeCapsules).
  function syncPositions() {
    if (!chart || !candleSeries || !positionMarkers) return
    const positions = props.positions ? props.positions() : []
    const seenIds = new Set()
    const markers = []

    for (const pos of positions) {
      seenIds.add(pos.id)
      const { optionType, isCall, pnlColor } = describePosition(pos)
      const entryTime = pos.created_at ? Math.floor(new Date(pos.created_at).getTime() / 1000) : null
      const anchorPrice = underlyingPriceNear(entryTime)

      // Skip the line/capsule entirely when we can't place it meaningfully on
      // THIS chart (no candle data yet to derive the underlying's entry-time
      // price) — still place the time-anchored marker below, since that only
      // needs the entry timestamp, not a price-scale anchor.
      if (anchorPrice != null) {
        let line = positionLines.get(pos.id)
        const lineOpts = {
          price: anchorPrice,
          color: pnlColor,
          lineWidth: 1,
          lineStyle: 3, // dotted — visually distinct from the solid LTP dashed line
          axisLabelVisible: true,
          title: `${optionType} ${pos.symbol || ''}`
        }
        if (!line) {
          line = candleSeries.createPriceLine(lineOpts)
          positionLines.set(pos.id, line)
        } else {
          line.applyOptions(lineOpts)
        }
      }

      if (entryTime) {
        markers.push({
          time: entryTime,
          position: isCall ? 'belowBar' : 'aboveBar',
          color: pnlColor,
          shape: isCall ? 'arrowUp' : 'arrowDown'
          // No text — capsule already carries full detail (symbol, entry, PnL);
          // the candle marker is just a clean visual entry-point pin.
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
    recomputeCapsules()
  }

  // Recomputes each capsule's Y pixel offset from its entry price via the series'
  // own price scale — must rerun on pan/zoom/resize, not just on position changes,
  // since the same price maps to a different pixel as the chart rescales.
  function recomputeCapsules() {
    if (!chart || !candleSeries) { setCapsules([]); return }
    const positions = props.positions ? props.positions() : []
    const next = positions
      .map(pos => {
        const entryTime = pos.created_at ? Math.floor(new Date(pos.created_at).getTime() / 1000) : null
        const anchorPrice = underlyingPriceNear(entryTime)
        if (anchorPrice == null) return null
        const raw = candleSeries.priceToCoordinate(anchorPrice)
        if (raw == null) return null
        // Round to whole pixels — autoscale wobbles by sub-pixel fractions every
        // frame as the live bar updates; feeding that straight into a signal
        // toggles the rendered `top` between adjacent values and flickers.
        return { id: pos.id, top: Math.round(raw), pos, ...describePosition(pos) }
      })
      .filter(Boolean)

    // Skip the signal write entirely when nothing visible actually changed —
    // same dedupe purpose: a no-op array swap still triggers a re-render/flicker.
    setCapsules(prev => {
      if (prev.length === next.length && prev.every((p, i) => p.top === next[i].top && p.pnlLabel === next[i].pnlLabel)) {
        return prev
      }
      return next
    })
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
      ...(props.theme || {
        upColor: '#34d399',
        downColor: '#fb7185',
        borderVisible: false,
        wickUpColor: '#34d399',
        wickDownColor: '#fb7185'
      }),
      // Built-in last-value label disabled — the `ltpSeries` LTP tail's own
      // axis label already shows current price; both together would duplicate it.
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

    ltpSeries = chart.addSeries(LineSeries, {
      color: '#60a5fa',
      lineWidth: 1,
      // Solid, not dashed — the segment only spans a few bars to the axis, and
      // a dash pattern needs more run length than that to render any strokes
      // at all (it was painting completely invisible dashes before).
      lineStyle: 0,
      lastValueVisible: true, // axis label still shows live LTP
      priceLineVisible: true,
      crosshairMarkerVisible: false,
      title: 'LTP'
    })

    let ro
    if (!props.fullHeight) {
      ro = new ResizeObserver(entries => {
        const entry = entries[0]
        if (entry && chart) chart.applyOptions({ width: entry.contentRect.width })
        recomputeCapsules()
      })
      ro.observe(containerEl)
    } else {
      ro = new ResizeObserver(() => recomputeCapsules())
      ro.observe(containerEl)
    }

    // Same price → different pixel as the user pans/zooms — reposition capsules.
    chart.timeScale().subscribeVisibleLogicalRangeChange(() => recomputeCapsules())
    chart.priceScale('right').subscribeSizeChange?.(() => recomputeCapsules())

    onCleanup(() => {
      if (rafId !== null) cancelAnimationFrame(rafId)
      ro?.disconnect()
      chart?.remove()
      chart = null
    })
  })

  createEffect(() => {
    if (!candleSeries || !props.theme) return
    candleSeries.applyOptions(props.theme)
  })

  // Sync historical bar data
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
      lastVolPaint = null
      didInitialFit = false
      for (const line of positionLines.values()) candleSeries.removePriceLine(line)
      positionLines.clear()
      positionMarkers?.setMarkers([])
      setCapsules([])
      candleSeries.setData([])
      volumeSeries.setData([])
      ltpSeries?.setData([])
      ltpTailAnchor = null
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
    if (isNewBar) lastVolPaint = null
    // Reset the tail's anchor on a new bar (full setData is fine here — once
    // per bar close, not per frame); within the same bar, animate() repaints
    // via the cheap `update()` path in paintLtpTail.
    if (isNewBar || !ltpTailAnchor) resetLtpTail(renderedClose)
    else paintLtpTail(renderedClose)

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
    const positions = props.positions ? props.positions() : []
    // Track pnl/pnl_pct explicitly — WS pushes mutate these in place on the
    // same array slot, and depending on the store's merge shape the array
    // reference alone may not change fast enough to feel "live". Reading the
    // raw numbers here forces this effect (and the capsule recompute it
    // triggers) to refire on every PnL tick, not just open/close events.
    void positions.map(p => `${p.id}:${p.pnl}:${p.pnl_pct}`).join('|')
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

  return (
    <div class={`relative w-full ${props.fullHeight ? 'h-full' : ''}`}>
      <div ref={containerEl} class={`w-full rounded-2xl overflow-hidden ${props.fullHeight ? 'h-full' : ''}`} />

      {/* Floating capsules — anchored to each position's entry-price Y coordinate.
          pointer-events-none on the layer so chart pan/zoom/crosshair pass through;
          re-enabled per-card so they're still hoverable. */}
      <div class="absolute inset-0 pointer-events-none">
        <For each={capsules()}>
          {cap => (
            <div
              class="absolute left-2 -translate-y-1/2 pointer-events-auto flex items-center gap-1.5 px-2.5 py-1 rounded-full border backdrop-blur-md text-[10px] font-bold whitespace-nowrap shadow-lg transition-[top] duration-150 z-10"
              style={{
                top: `${cap.top}px`,
                'border-color': `${cap.pnlColor}55`,
                background: 'rgba(17,24,39,0.85)'
              }}
              title={`${cap.optionType} ${cap.pos.symbol || ''} — entry ₹${cap.pos.entry_price}`}
            >
              <span class="px-1.5 py-0.5 rounded-full text-[9px] uppercase tracking-wider text-gray-950" style={{ background: cap.pnlColor }}>
                {cap.optionType}
              </span>
              <span class="text-gray-200">{cap.shortSymbol}</span>
              <span class="text-gray-500">@ ₹{cap.pos.entry_price}</span>
              <span style={{ color: cap.pnlColor }}>{cap.pnlLabel}</span>
            </div>
          )}
        </For>
      </div>
    </div>
  )
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
