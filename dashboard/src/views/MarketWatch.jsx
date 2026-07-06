// Market Watch page — real-time quotes via existing /api/dashboard + ActionCable DashboardChannel
// Data flows through useDashboard which already provides indices, quotes, marketStatus
import { createMemo, For } from 'solid-js'
import { Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import AnimatedNumber from '../components/AnimatedNumber'

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

  // Data-driven from existing dashboard API — no additional endpoints needed
  const quoteCards = createMemo(() => [
    { label: 'Nifty 50', value: indices()?.nifty, isPositive: true, changePct: 0 },
    { label: 'Bank Nifty', value: indices()?.banknifty, isPositive: true, changePct: 0 },
    { label: 'Sensex', value: indices()?.sensex, isPositive: true, changePct: 0 },
  ])

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-lg font-black text-white uppercase tracking-widest">Market Watch</h1>
          <p class="text-[10px] font-bold text-gray-500 uppercase tracking-wider mt-1">
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

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <For each={quoteCards()}>
          {(card) => <QuoteCard {...card} />}
        </For>
      </div>
    </div>
  )
}
