// Backend: GET /api/equity_curve?date_from=&date_to=
// Expected response shape: [{time: unix_seconds, equity: number, drawdown_pct: number}]
// TODO: Wire to useDashboard()

import { onMount, onCleanup, createEffect } from 'solid-js'
import { createChart, HistogramSeries, ColorType } from 'lightweight-charts'

export default function DrawdownChart(props) {
  let containerEl
  let chart
  let ddSeries

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
      height: props.height || 120,
      timeScale: { timeVisible: true, secondsVisible: false },
      rightPriceScale: {
        scaleMargins: { top: 0.1, bottom: 0.1 }
      }
    })

    ddSeries = chart.addSeries(HistogramSeries, {
      color: '#fb7185',
      priceFormat: { type: 'percent' },
      priceLineVisible: false,
      lastValueVisible: true,
      title: 'Drawdown'
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
    if (!ddSeries) return
    const data = props.data ? props.data() : []
    if (!data.length) {
      ddSeries.setData([])
      return
    }
    ddSeries.setData(data.map(d => {
      const dd = Math.abs(Number(d.drawdown_pct) || 0)
      return {
        time: d.time,
        value: -dd,
        color: dd > 5 ? '#ef4444' : dd > 2 ? '#fb7185' : '#fda4af'
      }
    }))
  })

  return <div ref={containerEl} class="w-full rounded-2xl overflow-hidden" />
}
