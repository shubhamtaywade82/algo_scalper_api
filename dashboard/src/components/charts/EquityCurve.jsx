// Backend: GET /api/equity_curve?date_from=&date_to=
// Expected response shape: [{time: unix_seconds, equity: number, drawdown_pct: number, peak: number}]
// TODO: Wire to useDashboard()

import { onMount, onCleanup, createEffect } from 'solid-js'
import { createChart, LineSeries, AreaSeries, ColorType } from 'lightweight-charts'

export default function EquityCurve(props) {
  let containerEl
  let chart
  let equitySeries
  let peakSeries

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
      height: props.height || 300,
      timeScale: { timeVisible: true, secondsVisible: false, rightOffset: 5 },
      rightPriceScale: {
        scaleMargins: { top: 0.05, bottom: 0.05 }
      }
    })

    equitySeries = chart.addSeries(AreaSeries, {
      lineColor: '#34d399',
      topColor: 'rgba(52, 211, 153, 0.25)',
      bottomColor: 'rgba(52, 211, 153, 0.02)',
      lineWidth: 2,
      lastValueVisible: true,
      priceLineVisible: false,
      title: 'Equity'
    })

    peakSeries = chart.addSeries(LineSeries, {
      color: '#eab308',
      lineWidth: 1,
      lineStyle: 2,
      lastValueVisible: false,
      priceLineVisible: false,
      title: 'Peak (HWM)'
    })

    const ro = new ResizeObserver(entries => {
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
    if (!equitySeries || !peakSeries) return
    const data = props.data ? props.data() : []
    if (!data.length) {
      equitySeries.setData([])
      peakSeries.setData([])
      return
    }
    equitySeries.setData(data.map(d => ({ time: d.time, value: d.equity })))
    peakSeries.setData(data.map(d => ({ time: d.time, value: d.peak || d.equity })))
  })

  return <div ref={containerEl} class="w-full rounded-2xl overflow-hidden" />
}
