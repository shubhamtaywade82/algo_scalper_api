import { createSignal, createMemo, createEffect, For, Show, onMount, onCleanup } from 'solid-js'
import AnimatedNumber from '../components/AnimatedNumber'
import { useReplay } from '../stores/useReplay'
import { createChart, CandlestickSeries, ColorType } from 'lightweight-charts'

export default function Replay() {
  const [isPlaying, setIsPlaying] = createSignal(false)
  const [playbackSpeed, setPlaybackSpeed] = createSignal('1x')
  const [activeTab, setActiveTab] = createSignal('trades')
  const { result, loading, error, loadReplay } = useReplay()

  const [currentIndex, setCurrentIndex] = createSignal(0)

  const candles = createMemo(() => result()?.candles || [])
  const events = createMemo(() => result()?.events || [])
  const replayTrades = createMemo(() => result()?.trades || [])

  // Initialize/reset currentIndex when candles array changes
  createEffect(() => {
    const list = candles()
    if (list.length > 0) {
      setCurrentIndex(Math.min(50, list.length))
    } else {
      setCurrentIndex(0)
    }
  })

  // Playback timer effect
  createEffect(() => {
    if (!isPlaying()) return

    const speedStr = playbackSpeed()
    let delay = 1000
    if (speedStr === '0.5x') delay = 2000
    else if (speedStr === '1x') delay = 1000
    else if (speedStr === '2x') delay = 500
    else if (speedStr === '5x') delay = 200

    const interval = setInterval(() => {
      if (currentIndex() < candles().length) {
        setCurrentIndex(prev => prev + 1)
      } else {
        setIsPlaying(false)
      }
    }, delay)

    onCleanup(() => clearInterval(interval))
  })

  const currentTimestamp = createMemo(() => candles()[currentIndex() - 1]?.time)
  const visibleCandles = createMemo(() => candles().slice(0, currentIndex()))
  const visibleTrades = createMemo(() => {
    const ts = currentTimestamp()
    if (!ts) return []
    return replayTrades().filter(t => t.entry_timestamp && t.entry_timestamp <= ts)
  })
  const visibleEvents = createMemo(() => {
    const ts = currentTimestamp()
    if (!ts) return []
    return events().filter(e => e.timestamp && e.timestamp <= ts)
  })

  const currentTimestampFormatted = createMemo(() => {
    const ts = currentTimestamp()
    if (!ts) return '--:--:--'
    return new Date(ts * 1000).toLocaleTimeString('en-IN', { hour12: false })
  })

  const metrics = createMemo(() => {
    const trades = visibleTrades()
    const total = trades.length
    if (total === 0) {
      return {
        netPnl: 0, netPnlPct: 0, totalTrades: 0, winRate: 0,
        winningTrades: 0, losingTrades: 0, profitFactor: 0,
        maxDrawdown: 0, maxDrawdownPct: 0, avgTrade: 0,
        expectancy: 0, signalCount: 0, signalWinRate: 0
      }
    }

    const wins = trades.filter(t => t.status === 'WIN')
    const losses = trades.filter(t => t.status === 'LOSS')

    const netPnl = trades.reduce((acc, t) => acc + (t.pnl || 0), 0)
    const netPnlPct = trades.reduce((acc, t) => acc + (t.pnlPct || 0), 0)

    const winningTrades = wins.length
    const losingTrades = losses.length
    const winRate = Math.round((winningTrades / total) * 100)

    const grossWin = wins.reduce((acc, t) => acc + (t.pnl || 0), 0)
    const grossLoss = Math.abs(losses.reduce((acc, t) => acc + (t.pnl || 0), 0))
    const profitFactor = grossLoss === 0 ? (grossWin === 0 ? 0 : 5) : Number((grossWin / grossLoss).toFixed(2))

    const avgTrade = Number((netPnl / total).toFixed(2))

    const sigCount = visibleEvents().filter(e => e.type === 'signal').length

    return {
      netPnl,
      netPnlPct: Number(netPnlPct.toFixed(2)),
      totalTrades: total,
      winRate,
      winningTrades,
      losingTrades,
      profitFactor,
      maxDrawdown: 0,
      maxDrawdownPct: 0,
      avgTrade,
      expectancy: avgTrade,
      signalCount: sigCount,
      signalWinRate: 0
    }
  })

  const latestTrade = createMemo(() => visibleTrades().length > 0 ? visibleTrades()[visibleTrades().length - 1] : null)

  return (
    <div class="space-y-6">

      {/* Control & Configuration Bar */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Strategy</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-bold">SMC Replay</div>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Instrument</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono font-bold">{result()?.symbol || '—'}</div>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Timeframe</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-bold">5 Minute</div>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Date</span>
            <div class="text-[10px] bg-white/[0.02] border border-white/5 px-2.5 py-1.5 rounded-lg text-white font-mono">
               {result() ? `${result().days_back}d` : 'Not loaded'}
            </div>
          </div>
        </div>

        <div class="flex items-center gap-2.5 mt-2 md:mt-0">
          <button
            onClick={() => loadReplay({ symbol: 'NIFTY', days_back: 30 })}
            disabled={loading()}
            class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all disabled:opacity-40"
          >
            {loading() ? 'Loading...' : 'Load Data'}
          </button>
          <Show when={result()}>
            <button
              onClick={() => setIsPlaying(!isPlaying())}
              class={`px-5 py-2.5 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all flex items-center gap-1.5 ${
                isPlaying() ? 'bg-amber-600 hover:bg-amber-500' : 'bg-emerald-600 hover:bg-emerald-500'
              }`}
            >
              <span>{isPlaying() ? '⏸' : '▶'}</span> {isPlaying() ? 'Pause Replay' : 'Start Replay'}
            </button>
          </Show>
        </div>
      </div>

      <Show when={error()}>
        <div class="bg-rose-500/10 border border-rose-500/25 rounded-xl p-3 text-xs text-rose-300 font-bold">
          {error()}
        </div>
      </Show>

      <Show when={!result() && !loading()}>
        <div class="flex items-center justify-center h-40 bg-white/[0.01] border border-dashed border-white/10 rounded-2xl">
          <span class="text-xs text-gray-600 font-bold uppercase tracking-wider">Click "Load Data" to start replay</span>
        </div>
      </Show>

      {/* Replay Metrics Row */}
      <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-4">
          <div class="glass p-4 rounded-xl">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Net P&L</span>
            <div class="text-base font-black text-emerald-400 text-data">+₹{metrics().netPnl.toLocaleString('en-IN')}</div>
            <span class="text-[8px] font-bold text-emerald-500 mt-1 block">+{metrics().netPnlPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total Trades</span>
            <div class="text-base font-black text-white text-data">{metrics().totalTrades}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Buy/Sell logs</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Win Rate</span>
          <div class="text-base font-black text-white text-data">{metrics().winRate}%</div>
            <span class="text-[8px] font-bold text-gray-500 mt-1 block">({metrics().winningTrades} / {metrics().totalTrades})</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Profit Factor</span>
          <div class="text-base font-black text-white text-data">{metrics().profitFactor}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Gross PnL Ratio</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Max Drawdown</span>
          <div class="text-base font-black text-rose-500 text-data">₹{metrics().maxDrawdown.toLocaleString('en-IN')}</div>
            <span class="text-[8px] font-bold text-rose-500 mt-1 block">{metrics().maxDrawdownPct}%</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Avg Trade</span>
          <div class="text-base font-black text-emerald-400 text-data">+₹{metrics().avgTrade}</div>
          <span class="text-[8px] font-bold text-emerald-500 mt-1 block">Wins & Losses</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Expectancy</span>
          <div class="text-base font-black text-white text-data">₹{metrics().expectancy.toFixed(0)}</div>
          <span class="text-[8px] font-bold text-gray-500 mt-1 block">Per Position</span>
        </div>
        <div class="glass p-4 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Sharpe Ratio</span>
          <div class="text-base font-black text-white text-data">{metrics().signalCount}</div>
            <span class="text-[8px] font-bold text-gray-500 mt-1 block">{metrics().signalWinRate}% wr</span>
        </div>
      </div>

      {/* WorkSpace Content Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column (8 units): Replay Candlestick Chart */}
        <div class="lg:col-span-8 space-y-6">
          <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[360px]">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <div>
                <span class="font-black text-white">{result()?.symbol || 'NIFTY'} — Replay</span>
                <span class="text-gray-500 font-mono ml-2">{visibleCandles().length} / {candles().length} candles</span>
              </div>
              <div class="text-emerald-400 font-bold uppercase tracking-wider">OHLC (5m)</div>
            </div>
            <div class="flex-1 py-4 relative">
              <Show when={visibleCandles().length > 0} fallback={
                <div class="flex items-center justify-center h-full text-[10px] text-gray-600 font-bold uppercase tracking-wider">
                  No candle data
                </div>
              }>
                <div ref={el => {
                  if (!el) return
                  const chart = createChart(el, {
                    layout: { background: { type: ColorType.Solid, color: 'transparent' }, textColor: '#6b7280' },
                    grid: { vertLines: { color: 'rgba(255,255,255,0.02)' }, horzLines: { color: 'rgba(255,255,255,0.02)' } },
                    width: el.clientWidth,
                    height: el.clientHeight,
                    rightPriceScale: { borderVisible: false },
                    timeScale: { borderVisible: false, visible: false }
                  })
                  const cs = chart.addSeries(CandlestickSeries, {
                    upColor: '#10b981', downColor: '#ef4444', wickUpColor: '#10b981', wickDownColor: '#ef4444',
                    borderVisible: false
                  })

                  createEffect(() => {
                    cs.setData(visibleCandles())
                    chart.timeScale().fitContent()
                  })

                  const ro = new ResizeObserver(() => {
                    chart.applyOptions({ width: el.clientWidth, height: el.clientHeight })
                  })
                  ro.observe(el)
                  onCleanup(() => { ro.disconnect(); chart.remove() })
                }} class="w-full h-full" />
              </Show>
            </div>
            {/* Playback controller toolbar */}
            <div class="flex items-center justify-between border-t border-white/5 pt-3">
              <div class="flex items-center gap-3">
                <button
                  onClick={() => {
                    setIsPlaying(false)
                    setCurrentIndex(Math.min(50, candles().length))
                  }}
                  class="p-2 bg-white/5 rounded-lg text-gray-300 hover:text-white transition-all text-xs font-bold"
                >
                  ⏮
                </button>
                <button
                  onClick={() => setIsPlaying(!isPlaying())}
                  class="w-8 h-8 rounded-full bg-primary-600 hover:bg-primary-500 text-white flex items-center justify-center transition-all text-xs"
                >
                  {isPlaying() ? '⏸' : '▶'}
                </button>
                <button
                  onClick={() => {
                    setIsPlaying(false)
                    setCurrentIndex(prev => Math.min(prev + 1, candles().length))
                  }}
                  class="p-2 bg-white/5 rounded-lg text-gray-300 hover:text-white transition-all text-xs font-bold"
                >
                  ⏭
                </button>
                <select
                  value={playbackSpeed()}
                  onChange={(e) => setPlaybackSpeed(e.target.value)}
                  class="glass-select text-[9px] px-2.5 py-1.5 rounded-lg"
                >
                  <option>0.5x</option>
                  <option>1x</option>
                  <option>2x</option>
                  <option>5x</option>
                </select>
              </div>
              <div class="flex-1 mx-6 flex items-center gap-2">
                <input
                  type="range"
                  class="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer accent-primary-500"
                  min="1"
                  max={candles().length || 1}
                  value={currentIndex()}
                  onInput={(e) => {
                    setIsPlaying(false)
                    setCurrentIndex(Number(e.target.value))
                  }}
                />
                <span class="text-[8px] font-mono text-gray-500">{currentTimestampFormatted()}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right Column (4 units): Inspector & Config */}
        <div class="lg:col-span-4 space-y-6">
          {/* Trade Information */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Trade Information</span>
              <Show when={latestTrade()} fallback={<span class="text-[8px] text-gray-600 font-bold">No trades</span>}>
                <span class={`text-[8px] font-black uppercase tracking-wider px-2 py-0.5 rounded ${
                  latestTrade().status === 'WIN' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                }`}>{latestTrade().status}</span>
              </Show>
            </div>
            <Show when={latestTrade()} fallback={
              <div class="text-[10px] text-gray-600 font-bold uppercase tracking-wider py-4 text-center">No trade data</div>
            }>
              <div class="text-[10px] space-y-2.5">
                <div class="flex justify-between border-b border-white/5 pb-2">
                  <span class="text-gray-500 uppercase font-bold">Signal</span>
                  <span class="font-black text-emerald-400">{latestTrade().type === 'BUY' ? 'BUY CALL' : 'SELL PUT'}</span>
                </div>
                <div class="flex justify-between border-b border-white/5 pb-2">
                  <span class="text-gray-500 uppercase font-bold">Instrument</span>
                  <span class="font-black text-white font-mono">{latestTrade().inst}</span>
                </div>
                <div class="flex justify-between border-b border-white/5 pb-2">
                  <span class="text-gray-500 uppercase font-bold">P&L (Realized)</span>
                  <span class={`font-black text-data ${latestTrade().pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {latestTrade().pnl >= 0 ? '+' : ''}₹{latestTrade().pnl.toLocaleString('en-IN')} ({latestTrade().pnlPct}%)
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-500 uppercase font-bold">Entry Price</span>
                  <span class="font-black text-white text-data">₹{latestTrade().entry}</span>
                </div>
              </div>
            </Show>
          </div>

          {/* Strategy State */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2">
              <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Strategy State</span>
            </div>
            <div class="flex items-center justify-center py-6 text-[10px] text-gray-600 font-bold uppercase tracking-wider">
              Not available in replay mode
            </div>
          </div>
        </div>
      </div>

      {/* Bottom Events Timeline & Tab Details */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Events Timeline (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <span class="text-[10px] font-black text-gray-400 uppercase tracking-widest">Events Timeline</span>
            <button class="text-[8px] font-black uppercase text-gray-500 hover:text-white transition-colors">Jump to Event</button>
          </div>
          <div class="flex-1 overflow-y-auto max-h-[160px] mt-2 divide-y divide-white/5">
            <For each={visibleEvents()}>
              {(e) => (
                <div class="py-2.5 flex items-start gap-3 text-[10px]">
                  <span class="text-gray-500 font-mono mt-0.5">{e.time}</span>
                  <div class="flex-1">
                    <p class="text-white font-bold leading-snug">{e.text}</p>
                    <span class={`text-[7px] font-black uppercase mt-1 inline-block ${
                      e.type === 'signal' ? 'text-emerald-400' : e.type === 'order' ? 'text-sky-400' : 'text-gray-500'
                    }`}>{e.type}</span>
                  </div>
                </div>
              )}
            </For>
          </div>
        </div>

        {/* Tab logs & trades review (8 cols) */}
        <div class="lg:col-span-8 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-3">
            <div class="flex items-center gap-1 text-[10px] font-black uppercase">
              <button
                onClick={() => setActiveTab('trades')}
                class={`px-3 py-1.5 rounded-lg ${activeTab() === 'trades' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500'}`}
              >
                Trades
              </button>
              <button
                onClick={() => setActiveTab('positions')}
                class={`px-3 py-1.5 rounded-lg ${activeTab() === 'positions' ? 'bg-primary-500/10 text-primary-300 border border-primary-500/25' : 'text-gray-500'}`}
              >
                Positions
              </button>
            </div>
            <span class="text-[8px] font-mono text-gray-500">{visibleTrades().length} trade{visibleTrades().length === 1 ? '' : 's'}</span>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse text-[10px]">
              <thead>
                <tr class="text-gray-600 font-black uppercase tracking-wider border-b border-white/5">
                  <th class="py-2.5">Time</th>
                  <th class="py-2.5">Instrument</th>
                  <th class="py-2.5 text-center">Type</th>
                  <th class="py-2.5 text-right font-black text-data">P&L</th>
                  <th class="py-2.5 text-right font-black">Status</th>
                </tr>
              </thead>
              <tbody>
                <For each={visibleTrades()}>
                  {(t) => (
                    <tr class="border-b border-white/5 hover:bg-white/[0.01]">
                      <td class="py-2.5 text-gray-500 font-mono">{t.time}</td>
                      <td class="py-2.5 font-bold text-white max-w-[150px] truncate">{t.inst}</td>
                      <td class="py-2.5 text-center">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          t.type === 'BUY' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                        }`}>{t.type}</span>
                      </td>
                      <td class={`py-2.5 text-right font-black text-data ${t.pnl >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        {t.pnl >= 0 ? '+' : ''}₹{t.pnl} ({t.pnlPct}%)
                      </td>
                      <td class="py-2.5 text-right font-black">
                        <span class={`px-1.5 py-0.5 rounded text-[8px] font-black uppercase ${
                          t.status === 'WIN' ? 'text-emerald-400 bg-emerald-500/10' : 'text-rose-400 bg-rose-500/10'
                        }`}>{t.status}</span>
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
