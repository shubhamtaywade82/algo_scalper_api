// Backend: GET /api/depth?symbol=:index_key
// Expected response shape: { symbol, bid: [{price, qty, orders}], ask: [{price, qty, orders}], totalBidQty, totalAskQty }
// TODO: Wire to useDashboard()

import { createMemo, For, Show } from 'solid-js'

const MAX_ROWS = 12

export default function OrderBook(props) {
  const depth = () => props.depth || { bid: [], ask: [], totalBidQty: 0, totalAskQty: 0 }
  const symbol = () => props.symbol || 'NIFTY'

  const bids = createMemo(() => (depth().bid || []).slice(0, MAX_ROWS))
  const asks = createMemo(() => (depth().ask || []).slice(0, MAX_ROWS))
  const maxDepth = createMemo(() => Math.max(depth().totalBidQty || 1, depth().totalAskQty || 1))

  const spread = createMemo(() => {
    const bestBid = depth().bid?.[0]?.price
    const bestAsk = depth().ask?.[0]?.price
    if (bestBid == null || bestAsk == null) return null
    return { bid: bestBid, ask: bestAsk, value: bestAsk - bestBid, pct: ((bestAsk - bestBid) / bestBid) * 100 }
  })

  return (
    <div class="glass rounded-2xl overflow-hidden">
      <div class="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-white/[0.02]">
        <h3 class="text-[10px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-cyan-500" />
          Order Book
        </h3>
        <Show when={spread()}>
          {s => (
            <span class="text-[9px] font-bold text-gray-500">
              Spread: {s().value.toFixed(2)} ({s().pct.toFixed(2)}%)
            </span>
          )}
        </Show>
      </div>
      <div class="px-4 py-2 border-b border-white/5">
        <span class="text-[8px] font-black text-gray-600 uppercase tracking-widest">{symbol()}</span>
      </div>

      <div class="grid grid-cols-2 divide-x divide-white/5">
        {/* Ask side (sells) */}
        <div class="flex flex-col-reverse">
          <div class="text-[8px] font-black text-gray-600 uppercase tracking-widest px-3 py-1.5 bg-white/[0.01] text-center border-b border-white/5">
            Ask
          </div>
          <For each={asks()}>
            {(level) => {
              const pct = (level.qty / maxDepth()) * 100
              return (
                <div class="flex items-center text-[11px] relative h-7 px-3 border-b border-white/[0.02]">
                  <div class="absolute inset-y-0 right-0 bg-rose-500/10 transition-all" style={{ width: `${pct}%` }} />
                  <span class="relative z-10 w-16 text-right font-bold text-rose-400 font-mono">{level.price.toFixed(2)}</span>
                  <span class="relative z-10 ml-auto font-bold text-gray-300 font-mono">{level.qty}</span>
                  <span class="relative z-10 w-10 text-right text-[9px] text-gray-600 font-mono">{level.orders}</span>
                </div>
              )
            }}
          </For>
        </div>

        {/* Bid side (buys) */}
        <div>
          <div class="text-[8px] font-black text-gray-600 uppercase tracking-widest px-3 py-1.5 bg-white/[0.01] text-center border-b border-white/5">
            Bid
          </div>
          <For each={bids()}>
            {(level) => {
              const pct = (level.qty / maxDepth()) * 100
              return (
                <div class="flex items-center text-[11px] relative h-7 px-3 border-b border-white/[0.02]">
                  <div class="absolute inset-y-0 left-0 bg-emerald-500/10 transition-all" style={{ width: `${pct}%` }} />
                  <span class="relative z-10 w-10 text-[9px] text-gray-600 font-mono">{level.orders}</span>
                  <span class="relative z-10 mr-auto font-bold text-gray-300 font-mono">{level.qty}</span>
                  <span class="relative z-10 w-16 text-left font-bold text-emerald-400 font-mono">{level.price.toFixed(2)}</span>
                </div>
              )
            }}
          </For>
        </div>
      </div>

      <Show when={bids().length === 0 && asks().length === 0}>
        <div class="flex items-center justify-center py-8 text-gray-600 text-[10px] uppercase tracking-widest">
          No depth data available
        </div>
      </Show>
    </div>
  )
}
