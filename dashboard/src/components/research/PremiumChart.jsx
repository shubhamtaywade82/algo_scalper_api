// Candlestick chart for a single option contract's premium bars, with a
// dotted price line marking the lifecycle's peak premium. Mirrors the setup
// conventions in charts/EquityCurve.jsx and charts/PriceChart.jsx, kept
// deliberately simpler since this only ever renders one static series (no
// live tick, no overlays).
import { onMount, onCleanup, createEffect } from 'solid-js'
import { createChart, CandlestickSeries, HistogramSeries, ColorType } from 'lightweight-charts'
import { istTickMarkFormatter, istTimeFormatter } from '../../lib/chartTime'

export default function PremiumChart(props) {
  let containerEl
  let chart
  let candleSeries
  let volumeSeries
  let peakLine = null

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
      height: props.height || 320,
      timeScale: { timeVisible: true, secondsVisible: false, rightOffset: 5, tickMarkFormatter: istTickMarkFormatter },
      localization: { timeFormatter: istTimeFormatter },
      rightPriceScale: { scaleMargins: { top: 0.08, bottom: 0.2 } }
    })

    candleSeries = chart.addSeries(CandlestickSeries, {
      upColor: '#34d399', downColor: '#fb7185', borderVisible: false,
      wickUpColor: '#34d399', wickDownColor: '#fb7185'
    })

    volumeSeries = chart.addSeries(HistogramSeries, {
      color: 'rgba(148,163,184,0.4)',
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume'
    })
    chart.priceScale('volume').applyOptions({ scaleMargins: { top: 0.85, bottom: 0 } })

    const ro = new ResizeObserver((entries) => {
      const entry = entries[0]
      if (entry && chart) chart.applyOptions({ width: entry.contentRect.width })
    })
    ro.observe(containerEl)

    onCleanup(() => {
      ro?.disconnect()
      chart?.remove()
      chart = null
    })
  })

  createEffect(() => {
    if (!candleSeries || !volumeSeries) return
    const bars = props.bars ? props.bars() : []
    if (!bars.length) {
      candleSeries.setData([])
      volumeSeries.setData([])
      return
    }

    candleSeries.setData(bars.map((b) => ({ time: b.time, open: b.open, high: b.high, low: b.low, close: b.close })))
    volumeSeries.setData(bars.map((b) => ({
      time: b.time, value: b.volume || 0,
      color: b.close >= b.open ? 'rgba(52,211,153,0.35)' : 'rgba(251,113,133,0.35)'
    })))

    if (peakLine) {
      candleSeries.removePriceLine(peakLine)
      peakLine = null
    }
    const peakPremium = props.peakPremium ? props.peakPremium() : null
    if (peakPremium) {
      peakLine = candleSeries.createPriceLine({
        price: peakPremium, color: '#eab308', lineWidth: 1, lineStyle: 2,
        axisLabelVisible: true, title: 'Peak'
      })
    }

    chart.timeScale().fitContent()
  })

  return <div ref={containerEl} class="w-full rounded-2xl overflow-hidden" />
}
