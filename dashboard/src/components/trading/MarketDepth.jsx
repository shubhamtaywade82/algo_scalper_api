// DEPENDENCY: backend endpoint GET /api/depth?symbol=:index_key
// TODO: Wire to useDashboard() when endpoint is available

import { createMemo, createEffect, createSignal, onCleanup } from 'solid-js'
import { Show } from 'solid-js'

export default function MarketDepth(props) {
  let canvasRef
  const [ready, setReady] = createSignal(false)

  const depth = () => props.depth || { bid: [], ask: [] }

  const merged = createMemo(() => {
    const bid = depth().bid || []
    const ask = depth().ask || []
    const allPrices = [...new Set([...bid.map(b => b.price), ...ask.map(a => a.price)])].sort((a, b) => a - b)
    let cumulativeBid = 0
    let cumulativeAsk = 0

    const bidMap = {}
    const askMap = {}
    bid.forEach(b => { bidMap[b.price] = (bidMap[b.price] || 0) + b.qty })
    ask.forEach(a => { askMap[a.price] = (askMap[a.price] || 0) + a.qty })

    return allPrices.map(price => {
      cumulativeBid += bidMap[price] || 0
      cumulativeAsk += askMap[price] || 0
      return { price, bid: cumulativeBid, ask: cumulativeAsk }
    })
  })

  const maxY = createMemo(() => {
    const data = merged()
    if (!data.length) return 1
    return Math.max(...data.map(d => Math.max(d.bid, d.ask))) * 1.15
  })

  function draw() {
    const canvas = canvasRef
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    const { width, height } = canvas
    const data = merged()
    if (!data.length) return

    const pad = { top: 16, bottom: 20, left: 60, right: 12 }
    const chartW = width - pad.left - pad.right
    const chartH = height - pad.top - pad.bottom
    const maxVal = maxY()

    ctx.clearRect(0, 0, width, height)

    if (maxVal <= 0) return

    const xScale = (price) => {
      const min = data[0].price
      const max = data[data.length - 1].price
      const range = max - min || 1
      return pad.left + ((price - min) / range) * chartW
    }
    const yScale = (val) => pad.top + chartH - (val / maxVal) * chartH

    // Grid lines
    ctx.strokeStyle = 'rgba(255,255,255,0.04)'
    ctx.lineWidth = 1
    for (let i = 0; i <= 4; i++) {
      const y = pad.top + (chartH / 4) * i
      ctx.beginPath()
      ctx.moveTo(pad.left, y)
      ctx.lineTo(width - pad.right, y)
      ctx.stroke()
    }

    // Draw ask area (red)
    ctx.beginPath()
    ctx.moveTo(xScale(data[0].price), yScale(0))
    data.forEach(d => ctx.lineTo(xScale(d.price), yScale(d.ask)))
    ctx.lineTo(xScale(data[data.length - 1].price), yScale(0))
    ctx.closePath()
    const askGrad = ctx.createLinearGradient(0, pad.top, 0, height - pad.bottom)
    askGrad.addColorStop(0, 'rgba(251, 113, 133, 0.4)')
    askGrad.addColorStop(1, 'rgba(251, 113, 133, 0.05)')
    ctx.fillStyle = askGrad
    ctx.fill()

    // Draw ask line
    ctx.beginPath()
    data.forEach((d, i) => {
      i === 0 ? ctx.moveTo(xScale(d.price), yScale(d.ask)) : ctx.lineTo(xScale(d.price), yScale(d.ask))
    })
    ctx.strokeStyle = '#fb7185'
    ctx.lineWidth = 1.5
    ctx.stroke()

    // Draw bid area (green)
    ctx.beginPath()
    ctx.moveTo(xScale(data[0].price), yScale(0))
    data.forEach(d => ctx.lineTo(xScale(d.price), yScale(d.bid)))
    ctx.lineTo(xScale(data[data.length - 1].price), yScale(0))
    ctx.closePath()
    const bidGrad = ctx.createLinearGradient(0, pad.top, 0, height - pad.bottom)
    bidGrad.addColorStop(0, 'rgba(52, 211, 153, 0.4)')
    bidGrad.addColorStop(1, 'rgba(52, 211, 153, 0.05)')
    ctx.fillStyle = bidGrad
    ctx.fill()

    // Draw bid line
    ctx.beginPath()
    data.forEach((d, i) => {
      i === 0 ? ctx.moveTo(xScale(d.price), yScale(d.bid)) : ctx.lineTo(xScale(d.price), yScale(d.bid))
    })
    ctx.strokeStyle = '#34d399'
    ctx.lineWidth = 1.5
    ctx.stroke()

    // Y-axis labels
    ctx.fillStyle = '#6b7280'
    ctx.font = '9px monospace'
    ctx.textAlign = 'right'
    for (let i = 0; i <= 4; i++) {
      const val = (maxVal / 4) * i
      const y = pad.top + chartH - (val / maxVal) * chartH
      ctx.fillText(Math.round(val).toLocaleString('en-IN'), pad.left - 4, y + 3)
    }

    // Max price label
    ctx.fillStyle = '#6b7280'
    ctx.font = '9px monospace'
    ctx.textAlign = 'center'
    ctx.fillText(data[0].price.toFixed(0), pad.left, height - 4)
    ctx.fillText(data[data.length - 1].price.toFixed(0), width - pad.right, height - 4)
  }

  createEffect(() => {
    depth()
    if (ready()) draw()
  })

  createEffect(() => {
    if (!canvasRef) return
    setReady(true)
    const ro = new ResizeObserver(() => draw())
    ro.observe(canvasRef.parentElement)
    onCleanup(() => ro.disconnect())
  })

  return (
    <div class="glass rounded-2xl overflow-hidden">
      <div class="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-white/[0.02]">
        <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-cyan-500" />
          Market Depth
        </h3>
        <div class="flex items-center gap-3">
          <div class="flex items-center gap-1.5">
            <div class="w-2 h-2 rounded-full bg-emerald-500" />
            <span class="text-[9px] font-bold text-emerald-400">Bid</span>
          </div>
          <div class="flex items-center gap-1.5">
            <div class="w-2 h-2 rounded-full bg-rose-500" />
            <span class="text-[9px] font-bold text-rose-400">Ask</span>
          </div>
        </div>
      </div>
      <canvas
        ref={canvasRef}
        width={400}
        height={200}
        class="w-full h-48"
      />
    </div>
  )
}
