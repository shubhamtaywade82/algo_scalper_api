import { createMemo, createSignal, createEffect, For } from 'solid-js'
import { Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import { useDepth } from '../stores/useDepth'
import OrderBook from '../components/trading/OrderBook'
import MarketDepth from '../components/trading/MarketDepth'
import AnimatedNumber from '../components/AnimatedNumber'

const SYMBOLS = [
  { key: 'NIFTY', label: 'Nifty 50' },
  { key: 'BANKNIFTY', label: 'Bank Nifty' },
  { key: 'SENSEX', label: 'Sensex' },
]

function QuoteCard(props) {
  return (
    <div class="glass glass-hover p-5 rounded-2xl border-l-4 border-primary-500/50">
      <div class="flex items-center justify-between mb-3">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">{props.label}</span>
        <span class={`text-[9px] font-black uppercase tracking-wider px-2 py-0.5 rounded-full ${props.isPositive ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
          {props.isPositive ? '+' : ''}{props.changePct}%
        </span>
      </div>
      <div class="text-2xl font-black text-white text-data tracking-tight">
        <AnimatedNumber value={props.value} decimals={2} />
      </div>
    </div>
  )
}

export default function MarketWatch() {
  const { indices, marketStatus } = useDashboardContext()
  const [selectedSymbol, setSelectedSymbol] = createSignal('NIFTY')
  const { depth, loading, error, fetchDepth } = useDepth(selectedSymbol())

  createEffect(() => {
    const symbol = selectedSymbol()
    fetchDepth()
  })

  const quoteCards = createMemo(() => {
    const idxs = indices() || {}
    
    const getNiftyChange = () => {
      const val = idxs.nifty
      const prev = idxs.nifty_prev_close
      if (!val || !prev) return { isPositive: true, changePct: 0 }
      const change = val - prev
      const pct = (change / prev) * 100
      return { isPositive: change >= 0, changePct: pct.toFixed(2) }
    }

    const getBankniftyChange = () => {
      const val = idxs.banknifty
      const prev = idxs.banknifty_prev_close
      if (!val || !prev) return { isPositive: true, changePct: 0 }
      const change = val - prev
      const pct = (change / prev) * 100
      return { isPositive: change >= 0, changePct: pct.toFixed(2) }
    }

    const getSensexChange = () => {
      const val = idxs.sensex
      const prev = idxs.sensex_prev_close
      if (!val || !prev) return { isPositive: true, changePct: 0 }
      const change = val - prev
      const pct = (change / prev) * 100
      return { isPositive: change >= 0, changePct: pct.toFixed(2) }
    }

    const nifty = getNiftyChange()
    const banknifty = getBankniftyChange()
    const sensex = getSensexChange()

    return [
      { label: 'Nifty 50', value: idxs.nifty, isPositive: nifty.isPositive, changePct: nifty.changePct },
      { label: 'Bank Nifty', value: idxs.banknifty, isPositive: banknifty.isPositive, changePct: banknifty.changePct },
      { label: 'Sensex', value: idxs.sensex, isPositive: sensex.isPositive, changePct: sensex.changePct },
    ]
  })

  return (
    <div class="space-y-6">
      {/* Market Status Header */}
      <div class="flex items-center justify-between mb-2">
        <div>
          <p class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">
            <Show when={marketStatus()?.market_open} fallback="Market Closed">
              Market Open — Live Quotes
            </Show>
          </p>
        </div>
        <Show when={marketStatus()?.market_open}>
          <span class="flex items-center gap-2 text-[10px] font-black text-emerald-400 uppercase tracking-widest">
            <span class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            LIVE
          </span>
        </Show>
      </div>

      {/* Quote Cards */}
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <For each={quoteCards()}>
          {(card) => <QuoteCard {...card} />}
        </For>
      </div>

      {/* Symbol Selector for Depth */}
      <div class="flex items-center gap-3">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Depth:</span>
        <select
          class="glass-select text-[10px] px-3 py-1.5 rounded-lg border border-white/5 bg-white/[0.03] text-white font-bold"
          value={selectedSymbol()}
          onChange={e => setSelectedSymbol(e.target.value)}
        >
          <For each={SYMBOLS}>
            {s => <option value={s.key}>{s.label}</option>}
          </For>
        </select>
        <Show when={loading()}>
          <span class="text-[9px] text-gray-500 animate-pulse">Loading...</span>
        </Show>
        <Show when={error()}>
          <span class="text-[9px] text-rose-400">Error: {error()}</span>
        </Show>
      </div>

      {/* Order Book + Market Depth */}
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <OrderBook depth={depth()} symbol={selectedSymbol()} />
        <MarketDepth depth={depth()} />
      </div>
    </div>
  )
}
