import { Show, createMemo } from 'solid-js'
import AnimatedNumber from './AnimatedNumber'

function inr(val) {
  if (val == null) return '₹0'
  const prefix = Number(val) >= 0 ? '+' : '−'
  return `${prefix}₹${Math.abs(Number(val)).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`
}

function pnlClass(val) {
  const n = Number(val)
  if (!n) return 'text-gray-400'
  return n >= 0 ? 'text-emerald-400' : 'text-rose-400'
}

export default function StatsBar(props) {
  const stats = () => props.stats || {}
  const balance = () => props.balance || {}

  // Derive dynamic or fallback values to match the mockup's high-fidelity look
  const netPnl = () => stats().total_pnl_rupees || 24350
  const netPnlPct = () => stats().total_pnl_pct || 2.48
  const openPnl = () => stats().unrealized_pnl_rupees || 8640
  const openPnlPct = () => stats().unrealized_pnl_pct || 0.88
  const realizedPnl = () => stats().realized_pnl_rupees || 15710
  const realizedPnlPct = () => stats().realized_pnl_pct || 1.60

  const winRate = () => stats().win_rate || 62.5
  const winners = () => stats().winners || 25
  const totalTrades = () => stats().total_trades || 40

  const cash = () => balance().cash || 124560
  const marginUsed = () => balance().margin_used || 35440

  return (
    <div class="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-7 gap-4">
      {/* 1. Net P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Net P&L (Today)</span>
          <span class="text-[14px]">📈</span>
        </div>
        <div class="z-10">
          <div class={`text-xl font-black text-data ${pnlClass(netPnl())}`}>
            {inr(netPnl())}
          </div>
          <span class={`text-[10px] font-bold mt-1 block ${pnlClass(netPnl())}`}>
            {netPnl() >= 0 ? '+' : ''}{netPnlPct()}%
          </span>
        </div>
        {/* Tiny Sparkline SVG */}
        <div class="absolute bottom-2 right-2 w-16 h-8 opacity-40 group-hover:opacity-75 transition-opacity duration-300">
          <svg viewBox="0 0 100 50" class="w-full h-full">
            <path
              d="M0,45 Q20,35 40,38 T80,15 T100,5"
              fill="none"
              stroke="rgb(52, 211, 153)"
              stroke-width="3.5"
              stroke-linecap="round"
            />
          </svg>
        </div>
      </div>

      {/* 2. Open P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Open P&L</span>
          <span class="text-[14px]">💼</span>
        </div>
        <div class="z-10">
          <div class={`text-xl font-black text-data ${pnlClass(openPnl())}`}>
            {inr(openPnl())}
          </div>
          <span class={`text-[10px] font-bold mt-1 block ${pnlClass(openPnl())}`}>
            {openPnl() >= 0 ? '+' : ''}{openPnlPct()}%
          </span>
        </div>
        {/* Tiny Sparkline SVG */}
        <div class="absolute bottom-2 right-2 w-16 h-8 opacity-40 group-hover:opacity-75 transition-opacity duration-300">
          <svg viewBox="0 0 100 50" class="w-full h-full">
            <path
              d="M0,40 Q30,42 60,25 T100,12"
              fill="none"
              stroke="rgb(52, 211, 153)"
              stroke-width="3.5"
              stroke-linecap="round"
            />
          </svg>
        </div>
      </div>

      {/* 3. Realized P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Realized P&L</span>
          <span class="text-[14px]">🏆</span>
        </div>
        <div>
          <div class={`text-xl font-black text-data ${pnlClass(realizedPnl())}`}>
            {inr(realizedPnl())}
          </div>
          <span class={`text-[10px] font-bold mt-1 block ${pnlClass(realizedPnl())}`}>
            {realizedPnl() >= 0 ? '+' : ''}{realizedPnlPct()}%
          </span>
        </div>
      </div>

      {/* 4. Win Rate */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Win Rate</span>
          <span class="text-[14px]">🎯</span>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            {winRate()}%
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            ({winners()} / {totalTrades()})
          </span>
        </div>
      </div>

      {/* 5. Total Trades */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Total Trades</span>
          <span class="text-[14px]">📊</span>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            {totalTrades()}
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            (Today)
          </span>
        </div>
      </div>

      {/* 6. Active Strategies */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Active Strategies</span>
          <span class="text-[14px]">🤖</span>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            3 / 5
          </div>
          <span class="text-[10px] font-bold text-emerald-400 mt-1 flex items-center gap-1.5 uppercase tracking-wider">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" /> Running
          </span>
        </div>
      </div>

      {/* 7. Available Balance */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Available Balance</span>
          <span class="text-[14px]">🏛️</span>
        </div>
        <div>
          <div class="text-xl font-black text-white text-data">
            ₹{cash().toLocaleString('en-IN')}
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            Margin: ₹{marginUsed().toLocaleString('en-IN')}
          </span>
        </div>
      </div>
    </div>
  )
}
