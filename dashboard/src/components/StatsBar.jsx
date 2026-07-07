import { Show, createMemo } from 'solid-js'
import AnimatedNumber from './AnimatedNumber'

export default function StatsBar(props) {
  const stats = () => props.stats || {}
  const balance = () => props.balance || {}

  const netPnl = () => stats().total_pnl_rupees ?? 0
  const netPnlPct = () => stats().total_pnl_pct ?? 0
  const openPnl = () => stats().unrealized_pnl_rupees ?? 0
  const openPnlPct = () => stats().unrealized_pnl_pct ?? 0
  const realizedPnl = () => stats().realized_pnl_rupees ?? 0
  const realizedPnlPct = () => stats().realized_pnl_pct ?? 0

  const winRate = () => stats().win_rate ?? 0
  const winners = () => stats().winners ?? 0
  const totalTrades = () => stats().total_trades ?? 0

  const strategiesRunning = () => props.strategies?.running ?? 0
  const strategiesTotal = () => props.strategies?.total ?? 0

  const cash = () => balance().cash ?? 0
  const marginUsed = () => balance().margin_used ?? 0

  return (
    <div class="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-7 gap-4">
      {/* 1. Net P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Net P&L (Today)</span>
          <span class="text-[14px]">📈</span>
        </div>
        <div class="z-10">
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={netPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={netPnlPct()} suffix="%" showSign pnlColor />
          </span>
        </div>

      </div>

      {/* 2. Open P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between relative overflow-hidden group hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Open P&L</span>
          <span class="text-[14px]">💼</span>
        </div>
        <div class="z-10">
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={openPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={openPnlPct()} suffix="%" showSign pnlColor />
          </span>
        </div>

      </div>

      {/* 3. Realized P&L */}
      <div class="glass p-4.5 rounded-2xl flex flex-col justify-between hover:border-white/10 transition-all duration-300">
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Realized P&L</span>
          <span class="text-[14px]">🏆</span>
        </div>
        <div>
          <div class="text-xl font-black text-data">
            <AnimatedNumber value={realizedPnl()} currency decimals={0} showSign pnlColor />
          </div>
          <span class="text-[10px] font-bold mt-1 block">
            <AnimatedNumber value={realizedPnlPct()} suffix="%" showSign pnlColor />
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
            <AnimatedNumber value={winRate()} suffix="%" />
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            (<AnimatedNumber value={winners()} decimals={0} /> / <AnimatedNumber value={totalTrades()} decimals={0} />)
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
            <AnimatedNumber value={totalTrades()} decimals={0} />
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
            {strategiesRunning()} / {strategiesTotal()}
          </div>
          <Show when={strategiesRunning() > 0} fallback={
            <span class="text-[10px] font-bold text-gray-500 mt-1 flex items-center gap-1.5 uppercase tracking-wider">
              <span class="w-1.5 h-1.5 rounded-full bg-gray-500" /> Idle
            </span>
          }>
            <span class="text-[10px] font-bold text-emerald-400 mt-1 flex items-center gap-1.5 uppercase tracking-wider">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" /> Running
            </span>
          </Show>
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
            <AnimatedNumber value={cash()} currency decimals={0} />
          </div>
          <span class="text-[10px] font-bold text-gray-500 mt-1 block">
            Margin: ₹<AnimatedNumber value={marginUsed()} decimals={0} />
          </span>
        </div>
      </div>
    </div>
  )
}
